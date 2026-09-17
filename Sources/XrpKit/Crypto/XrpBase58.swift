import Foundation
import HsCryptoKit

/// Base58 with the XRP Ledger alphabet. Same algorithm as Bitcoin's, different symbol order,
/// so `r` is the leading character of an address instead of `1`. `HsCryptoKit.Base58` does not
/// parameterize the alphabet, hence the kit's own codec.
enum XrpBase58 {
    static let alphabet = Array("rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz")
    private static let zeroCharacter = alphabet[0]
    private static let indexes: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
    private static let base = 58

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        let leadingZeros = data.prefix { $0 == 0 }.count

        var digits = [Int]()
        for byte in data {
            var carry = Int(byte)
            for index in 0 ..< digits.count {
                carry += digits[index] << 8
                digits[index] = carry % base
                carry /= base
            }
            while carry > 0 {
                digits.append(carry % base)
                carry /= base
            }
        }

        var result = String(repeating: zeroCharacter, count: leadingZeros)
        for digit in digits.reversed() {
            result.append(alphabet[digit])
        }
        return result
    }

    static func decode(_ string: String) throws -> Data {
        guard !string.isEmpty else {
            return Data()
        }

        let leadingZeros = string.prefix { $0 == zeroCharacter }.count

        var bytes = [UInt8]()
        for character in string {
            guard var carry = indexes[character] else {
                throw AddressError.invalidFormat
            }
            for index in 0 ..< bytes.count {
                carry += Int(bytes[index]) * base
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }

        return Data(repeating: 0, count: leadingZeros) + Data(bytes.reversed())
    }

    /// Encodes payload with a 4-byte double-SHA256 checksum appended.
    static func encodeChecked(_ payload: Data) -> String {
        encode(payload + Hashes.doubleSha256(payload).prefix(4))
    }

    /// Decodes and verifies the 4-byte checksum, returning the payload.
    static func decodeChecked(_ string: String) throws -> Data {
        let decoded = try decode(string)
        guard decoded.count >= 5 else {
            throw AddressError.invalidFormat
        }

        let payload = decoded.prefix(decoded.count - 4)
        let checksum = decoded.suffix(4)
        guard checksum == Hashes.doubleSha256(payload).prefix(4) else {
            throw AddressError.invalidFormat
        }

        return Data(payload)
    }
}
