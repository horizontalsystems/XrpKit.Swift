import CryptoKit
import Foundation
import HsCryptoKit

enum Hashes {
    /// First 32 bytes of SHA-512: the hash function used for signing and transaction ids.
    static func sha512Half(_ parts: Data...) -> Data {
        var hasher = SHA512()
        for part in parts {
            hasher.update(data: part)
        }
        return Data(hasher.finalize()).prefix(32)
    }

    static func sha256(_ data: Data) -> Data {
        Crypto.sha256(data)
    }

    static func doubleSha256(_ data: Data) -> Data {
        Crypto.doubleSha256(data)
    }

    /// RIPEMD160(SHA256(input)): the XRPL AccountID of a public key.
    static func sha256Ripemd160(_ data: Data) -> Data {
        Crypto.ripeMd160Sha256(data)
    }
}
