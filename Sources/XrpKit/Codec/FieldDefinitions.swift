import Foundation

/// Serialized type codes from rippled's SField definitions.
enum TypeCode: Int {
    case uint16 = 1
    case uint32 = 2
    case uint64 = 3
    case hash128 = 4
    case hash256 = 5
    case amount = 6
    case blob = 7
    case accountId = 8
    case stObject = 14
    case stArray = 15
    case uint8 = 16
}

struct Field {
    let name: String
    let typeCode: TypeCode
    let fieldCode: Int
    let isVLEncoded: Bool
    let isSigningField: Bool

    init(_ name: String, _ typeCode: TypeCode, _ fieldCode: Int, isVLEncoded: Bool = false, isSigningField: Bool = true) {
        self.name = name
        self.typeCode = typeCode
        self.fieldCode = fieldCode
        self.isVLEncoded = isVLEncoded
        self.isSigningField = isSigningField
    }

    /// Canonical field order: by type code, then field code.
    var ordinal: Int {
        (typeCode.rawValue << 16) | fieldCode
    }

    /// Field ID header: 1 to 3 bytes depending on the size of the type and field codes.
    func header() -> Data {
        let type = typeCode.rawValue
        switch (type < 16, fieldCode < 16) {
        case (true, true): return Data([UInt8((type << 4) | fieldCode)])
        case (true, false): return Data([UInt8(type << 4), UInt8(fieldCode)])
        case (false, true): return Data([UInt8(fieldCode), UInt8(type)])
        case (false, false): return Data([0, UInt8(type), UInt8(fieldCode)])
        }
    }
}

/// The subset of rippled's field table a wallet needs for Payment, TrustSet, AccountSet and
/// AccountDelete transactions, including Memos. Source: xrpl.js ripple-binary-codec definitions.json.
enum FieldDefinitions {
    private static let fields: [Field] = [
        // UInt8
        Field("TickSize", .uint8, 16),
        // UInt16
        Field("TransactionType", .uint16, 2),
        // UInt32
        Field("NetworkID", .uint32, 1),
        Field("Flags", .uint32, 2),
        Field("SourceTag", .uint32, 3),
        Field("Sequence", .uint32, 4),
        Field("TransferRate", .uint32, 11),
        Field("DestinationTag", .uint32, 14),
        Field("QualityIn", .uint32, 20),
        Field("QualityOut", .uint32, 21),
        Field("LastLedgerSequence", .uint32, 27),
        Field("SetFlag", .uint32, 33),
        Field("ClearFlag", .uint32, 34),
        Field("TicketSequence", .uint32, 41),
        // Hash128
        Field("EmailHash", .hash128, 1),
        // Hash256
        Field("AccountTxnID", .hash256, 9),
        Field("InvoiceID", .hash256, 17),
        // Amount
        Field("Amount", .amount, 1),
        Field("LimitAmount", .amount, 3),
        Field("Fee", .amount, 8),
        Field("SendMax", .amount, 9),
        Field("DeliverMin", .amount, 10),
        // Blob (variable length)
        Field("MessageKey", .blob, 2, isVLEncoded: true),
        Field("SigningPubKey", .blob, 3, isVLEncoded: true),
        Field("TxnSignature", .blob, 4, isVLEncoded: true, isSigningField: false),
        Field("Domain", .blob, 7, isVLEncoded: true),
        Field("MemoType", .blob, 12, isVLEncoded: true),
        Field("MemoData", .blob, 13, isVLEncoded: true),
        Field("MemoFormat", .blob, 14, isVLEncoded: true),
        // AccountID (variable length, always 20 bytes)
        Field("Account", .accountId, 1, isVLEncoded: true),
        Field("Destination", .accountId, 3, isVLEncoded: true),
        Field("RegularKey", .accountId, 8, isVLEncoded: true),
        // STObject
        Field("Memo", .stObject, 10),
        // STArray
        Field("Memos", .stArray, 9),
    ]

    private static let byName: [String: Field] = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0) })

    static let objectEndMarker: UInt8 = 0xE1
    static let arrayEndMarker: UInt8 = 0xF1

    static func field(name: String) throws -> Field {
        guard let field = byName[name] else {
            throw CodecError.unsupportedField(name)
        }
        return field
    }

    static func contains(name: String) -> Bool {
        byName[name] != nil
    }
}

enum TransactionType {
    static let payment = 0
    static let accountSet = 3
    static let trustSet = 20
    static let accountDelete = 21

    private static let codes: [String: Int] = [
        "Payment": payment,
        "AccountSet": accountSet,
        "TrustSet": trustSet,
        "AccountDelete": accountDelete,
    ]

    static func code(name: String) throws -> Int {
        guard let code = codes[name] else {
            throw CodecError.unsupportedTransactionType(name)
        }
        return code
    }

    static func isSupported(name: String) -> Bool {
        codes[name] != nil
    }
}
