import Foundation

/// Serializes `Amount` to the 8-byte (XRP) or 48-byte (issued currency) ledger format.
enum AmountCodec {
    private static let minExponent = -96
    private static let maxExponent = 80
    private static let minMantissa: UInt64 = 1_000_000_000_000_000 // 1e15
    private static let maxMantissa: UInt64 = 9_999_999_999_999_999 // 1e16 - 1
    private static let maxDrops: UInt64 = 100_000_000_000_000_000 // 1e17

    private static let notXrpBit: UInt64 = 1 << 63
    private static let positiveBit: UInt64 = 1 << 62

    static func encode(_ amount: Amount) throws -> Data {
        switch amount {
        case let .xrp(drops): return try encodeXrp(drops: drops)
        case let .issued(value, currency, issuer): return try encodeIssued(value: value, currency: currency, issuer: issuer)
        }
    }

    /// Parses the JSON form of an XRP amount: a string of drops.
    static func fromDropsString(_ drops: String) throws -> Amount {
        guard let drops = UInt64(drops) else {
            throw CodecError.invalidAmount(drops)
        }
        return .xrp(drops: drops)
    }

    static func issued(value: String, currency: String, issuer: String) throws -> Amount {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), decimal.isFinite else {
            throw CodecError.invalidAmount(value)
        }
        return try .issued(value: decimal, currency: CurrencyCodec.normalize(currency), issuer: issuer)
    }

    private static func encodeXrp(drops: UInt64) throws -> Data {
        guard drops < maxDrops else {
            throw CodecError.invalidAmount(String(drops))
        }
        return bigEndian(drops | positiveBit)
    }

    private static func encodeIssued(value: Decimal, currency: String, issuer: String) throws -> Data {
        let head: UInt64
        if value == 0 {
            head = notXrpBit
        } else {
            let normalized = try normalize(value)
            let sign: UInt64 = normalized.isNegative ? 0 : positiveBit
            head = notXrpBit | sign | (UInt64(normalized.exponent + 97) << 54) | normalized.mantissa
        }

        var data = bigEndian(head)
        data.append(try CurrencyCodec.toBytes(currency))
        data.append(try AccountId.fromAddress(issuer).bytes)
        return data
    }

    /// Splits a decimal into a 16-digit mantissa and an exponent, as the ledger stores it.
    private static func normalize(_ value: Decimal) throws -> (mantissa: UInt64, exponent: Int, isNegative: Bool) {
        // plain decimal notation, no exponent: NSDecimalNumber prints all the digits
        var text = NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
        let isNegative = text.hasPrefix("-")
        if isNegative {
            text.removeFirst()
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = String(parts[0])
        let fractionPart = parts.count > 1 ? String(parts[1]) : ""

        var digits = integerPart + fractionPart
        var exponent = -fractionPart.count

        while digits.hasPrefix("0") {
            digits.removeFirst()
        }
        while digits.hasSuffix("0") {
            digits.removeLast()
            exponent += 1
        }

        guard !digits.isEmpty, digits.count <= 16, let mantissa = UInt64(digits) else {
            throw CodecError.invalidAmount(text)
        }

        var normalizedMantissa = mantissa
        while normalizedMantissa < minMantissa {
            normalizedMantissa *= 10
            exponent -= 1
        }

        guard (minExponent ... maxExponent).contains(exponent) else {
            throw CodecError.invalidAmount(text)
        }

        return (normalizedMantissa, exponent, isNegative)
    }

    private static func bigEndian(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
