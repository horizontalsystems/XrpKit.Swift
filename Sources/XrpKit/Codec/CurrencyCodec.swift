import Foundation

/// Currency codes on the ledger are 160 bits. A standard 3-character ISO-style code is stored
/// in bytes 12..14 with everything else zero; anything else is given as 40 hex characters.
public enum CurrencyCodec {
    public static let xrp = "XRP"

    private static let standardCodeCharacters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789?!@#$%^&*<>(){}[]|")

    public static func isStandardCode(_ code: String) -> Bool {
        code.count == 3 && code != xrp && code.allSatisfy { standardCodeCharacters.contains($0) }
    }

    public static func isHexCode(_ code: String) -> Bool {
        code.count == 40 && code.isXrpHex
    }

    public static func isValid(_ code: String) -> Bool {
        isStandardCode(code) || isHexCode(code)
    }

    /// 20-byte ledger representation of a currency code.
    static func toBytes(_ code: String) throws -> Data {
        if code == xrp {
            return Data(count: 20)
        }
        if isStandardCode(code) {
            var bytes = Data(count: 20)
            bytes.replaceSubrange(12 ..< 15, with: Data(code.utf8))
            return bytes
        }
        if isHexCode(code), let bytes = code.xrpHexData {
            return bytes
        }
        throw CodecError.invalidCurrencyCode(code)
    }

    /// Canonical string form: XRP, a 3-character code, or 40 upper-case hex characters.
    static func fromBytes(_ bytes: Data) throws -> String {
        guard bytes.count == 20 else {
            throw CodecError.invalidCurrencyCode(bytes.xrpHex)
        }
        if bytes.allSatisfy({ $0 == 0 }) {
            return xrp
        }

        let head = bytes.prefix(12)
        let tail = bytes.suffix(5)
        if head.allSatisfy({ $0 == 0 }), tail.allSatisfy({ $0 == 0 }),
           let code = String(data: bytes.subdata(in: 12 ..< 15), encoding: .ascii), isStandardCode(code)
        {
            return code
        }

        return bytes.xrpHex
    }

    /// Ledger form as it appears in JSON (3-char code or 40-hex). Normalizes lower-case hex.
    public static func normalize(_ code: String) throws -> String {
        if code == xrp || isStandardCode(code) {
            return code
        }
        if isHexCode(code) {
            return code.uppercased()
        }
        throw CodecError.invalidCurrencyCode(code)
    }

    /// Human-readable code: a 40-hex code whose bytes are printable ASCII followed by zero padding
    /// (e.g. RLUSD, USDC) is decoded to text; otherwise the code is returned as is.
    public static func displayCode(_ code: String) -> String {
        guard isHexCode(code), let bytes = code.xrpHexData else {
            return code
        }

        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        guard end > bytes.startIndex else {
            return code
        }

        let text = bytes[bytes.startIndex ..< end]
        let printable = text.allSatisfy { (0x21 ... 0x7E).contains($0) }
        let padded = bytes[end...].allSatisfy { $0 == 0 }

        guard printable, padded, let string = String(data: text, encoding: .ascii) else {
            return code
        }
        return string
    }
}
