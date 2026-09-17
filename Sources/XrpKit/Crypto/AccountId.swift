import Foundation

/// A 20-byte XRPL AccountID and its classic `r...` address encoding.
public struct AccountId: Hashable {
    private static let addressPrefix: UInt8 = 0x00

    public let bytes: Data

    init(bytes: Data) throws {
        guard bytes.count == 20 else {
            throw AddressError.invalidFormat
        }
        self.bytes = bytes
    }

    public var address: String {
        XrpBase58.encodeChecked(Data([Self.addressPrefix]) + bytes)
    }

    /// AccountID of a 33-byte compressed secp256k1 public key.
    public static func fromPublicKey(_ publicKey: Data) throws -> AccountId {
        guard publicKey.count == 33 else {
            throw AddressError.invalidFormat
        }
        return try AccountId(bytes: Hashes.sha256Ripemd160(publicKey))
    }

    /// Parses a classic address.
    public static func fromAddress(_ address: String) throws -> AccountId {
        guard address.hasPrefix("r") else {
            throw AddressError.invalidFormat
        }
        let payload = try XrpBase58.decodeChecked(address)
        guard payload.count == 21, payload[payload.startIndex] == addressPrefix else {
            throw AddressError.invalidFormat
        }
        return try AccountId(bytes: Data(payload.dropFirst()))
    }

    public static func isValid(address: String) -> Bool {
        (try? fromAddress(address)) != nil
    }
}
