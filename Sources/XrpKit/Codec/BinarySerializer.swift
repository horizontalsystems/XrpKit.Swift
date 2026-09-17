import Foundation

/// Canonical binary serialization of a transaction given as a JSON-like dictionary.
///
/// Values by field type: integers (`Int`, `UInt32`, `UInt64` or `NSNumber`) for UInt fields, hex
/// `String` for Hash and Blob fields, an `r...` address `String` for AccountID fields, `Amount`, a
/// drops `String` or a value/currency/issuer dictionary for Amount fields, an array of single-key
/// dictionaries for STArray, and a dictionary for a nested STObject.
enum BinarySerializer {
    private static let transactionSignPrefix = Data([0x53, 0x54, 0x58, 0x00]) // "STX\0"
    private static let transactionIdPrefix = Data([0x54, 0x58, 0x4E, 0x00]) // "TXN\0"

    static func serialize(_ tx: [String: Any], forSigning: Bool = false) throws -> Data {
        var out = Data()
        try writeObject(&out, tx, forSigning: forSigning)
        return out
    }

    /// Hash that is signed: SHA-512Half over the "STX\0" prefix and the signing-field serialization.
    static func signingHash(_ tx: [String: Any]) throws -> Data {
        try Hashes.sha512Half(transactionSignPrefix, serialize(tx, forSigning: true))
    }

    /// Transaction id: SHA-512Half over the "TXN\0" prefix and the full signed serialization.
    static func transactionHash(signedBlob: Data) -> Data {
        Hashes.sha512Half(transactionIdPrefix, signedBlob)
    }

    private static func writeObject(_ out: inout Data, _ object: [String: Any], forSigning: Bool) throws {
        var entries = [(field: Field, value: Any)]()
        for (name, value) in object {
            if value is NSNull {
                continue
            }
            let field = try FieldDefinitions.field(name: name)
            if forSigning, !field.isSigningField {
                continue
            }
            entries.append((field, value))
        }

        for (field, value) in entries.sorted(by: { $0.field.ordinal < $1.field.ordinal }) {
            out.append(field.header())
            let body = try encodeValue(field: field, value: value, forSigning: forSigning)
            if field.isVLEncoded {
                out.append(try encodeLength(body.count))
            }
            out.append(body)
        }
    }

    private static func encodeValue(field: Field, value: Any, forSigning: Bool) throws -> Data {
        switch field.typeCode {
        case .uint8:
            guard let number = UInt8(exactly: try integer(value, field: field)) else {
                throw CodecError.valueOutOfRange(field: field.name)
            }
            return Data([number])
        case .uint16:
            let raw: UInt64
            if field.name == "TransactionType", let name = value as? String {
                raw = UInt64(try TransactionType.code(name: name))
            } else {
                raw = try integer(value, field: field)
            }
            guard let number = UInt16(exactly: raw) else {
                throw CodecError.valueOutOfRange(field: field.name)
            }
            return bigEndian(number)
        case .uint32:
            guard let number = UInt32(exactly: try integer(value, field: field)) else {
                throw CodecError.valueOutOfRange(field: field.name)
            }
            return bigEndian(number)
        case .uint64:
            return bigEndian(try integer(value, field: field))
        case .hash128:
            return try fixedHex(value, size: 16, field: field)
        case .hash256:
            return try fixedHex(value, size: 32, field: field)
        case .amount:
            return try AmountCodec.encode(try amount(value, field: field))
        case .blob:
            guard let hex = value as? String, let data = hex.isEmpty ? Data() : hex.xrpHexData else {
                throw CodecError.invalidValue(field: field.name)
            }
            return data
        case .accountId:
            guard let address = value as? String else {
                throw CodecError.invalidValue(field: field.name)
            }
            return try AccountId.fromAddress(address).bytes
        case .stObject:
            guard let object = value as? [String: Any] else {
                throw CodecError.invalidValue(field: field.name)
            }
            var inner = Data()
            try writeObject(&inner, object, forSigning: forSigning)
            inner.append(FieldDefinitions.objectEndMarker)
            return inner
        case .stArray:
            guard let items = value as? [[String: Any]] else {
                throw CodecError.invalidValue(field: field.name)
            }
            var inner = Data()
            for item in items {
                // each array element is a single-key object naming the wrapped STObject field (e.g. Memo)
                guard item.count == 1, let entry = item.first, let object = entry.value as? [String: Any] else {
                    throw CodecError.invalidValue(field: field.name)
                }
                let objectField = try FieldDefinitions.field(name: entry.key)
                inner.append(objectField.header())
                try writeObject(&inner, object, forSigning: forSigning)
                inner.append(FieldDefinitions.objectEndMarker)
            }
            inner.append(FieldDefinitions.arrayEndMarker)
            return inner
        }
    }

    private static func fixedHex(_ value: Any, size: Int, field: Field) throws -> Data {
        guard let hex = value as? String, let data = hex.xrpHexData, data.count == size else {
            throw CodecError.invalidValue(field: field.name)
        }
        return data
    }

    /// Non-negative integer from any of the accepted value shapes; anything else is an error, never a truncation.
    private static func integer(_ value: Any, field: Field) throws -> UInt64 {
        switch value {
        case let number as UInt64: return number
        case let number as UInt32: return UInt64(number)
        case let number as Int:
            guard number >= 0 else { throw CodecError.valueOutOfRange(field: field.name) }
            return UInt64(number)
        case let number as Int64:
            guard number >= 0 else { throw CodecError.valueOutOfRange(field: field.name) }
            return UInt64(number)
        case let number as NSNumber:
            guard let uint = UInt64(exactly: number) else { throw CodecError.valueOutOfRange(field: field.name) }
            return uint
        case let string as String:
            guard let number = UInt64(string) else { throw CodecError.invalidValue(field: field.name) }
            return number
        default:
            throw CodecError.invalidValue(field: field.name)
        }
    }

    private static func amount(_ value: Any, field: Field) throws -> Amount {
        switch value {
        case let amount as Amount:
            return amount
        case let drops as String:
            return try AmountCodec.fromDropsString(drops)
        case let object as [String: Any]:
            guard let value = object["value"] as? String, let currency = object["currency"] as? String, let issuer = object["issuer"] as? String else {
                throw CodecError.invalidValue(field: field.name)
            }
            return try AmountCodec.issued(value: value, currency: currency, issuer: issuer)
        default:
            throw CodecError.invalidValue(field: field.name)
        }
    }

    /// Variable-length prefix for Blob and AccountID fields.
    static func encodeLength(_ length: Int) throws -> Data {
        switch length {
        case 0 ... 192:
            return Data([UInt8(length)])
        case 193 ... 12480:
            let value = length - 193
            return Data([UInt8(193 + (value >> 8)), UInt8(value & 0xFF)])
        case 12481 ... 918_744:
            let value = length - 12481
            return Data([UInt8(241 + (value >> 16)), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
        default:
            throw CodecError.lengthTooLarge(length)
        }
    }

    private static func bigEndian(_ value: some FixedWidthInteger) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
