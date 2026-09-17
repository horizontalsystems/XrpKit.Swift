import Foundation
import HdWalletKit
import HsCryptoKit

/// secp256k1 signer for XRPL transactions.
///
/// Keys follow the BIP44 path used by Ledger, Trust Wallet, Exodus and Xaman for mnemonic accounts:
/// m/44'/144'/0'/0/0, with the BIP32 leaf private key used directly as the XRPL signing key.
public class Signer {
    private let privateKey: Data

    /// 33-byte compressed public key, the value of the SigningPubKey transaction field.
    public let publicKey: Data
    public let accountId: AccountId

    init(privateKey: Data) throws {
        guard privateKey.count == 32 else {
            throw SignError.invalidPrivateKey
        }
        self.privateKey = privateKey
        publicKey = Crypto.publicKey(privateKey: privateKey, compressed: true)
        accountId = try AccountId.fromPublicKey(publicKey)
    }

    public var address: String {
        accountId.address
    }

    /// Signs a 32-byte digest (SHA-512Half of the signing prefix and serialized transaction).
    /// `Crypto.sign` is secp256k1 ECDSA with RFC 6979 nonces, a canonical low-S value and DER
    /// encoding, exactly what XRPL requires; it does not check the digest length, so the guard is here.
    func sign(digest: Data) throws -> Data {
        guard digest.count == 32 else {
            throw SignError.invalidDigest
        }
        return try Crypto.sign(data: digest, privateKey: privateKey)
    }
}

public extension Signer {
    static let coinType: UInt32 = 144

    static func instance(seed: Data) throws -> Signer {
        try Signer(privateKey: privateKey(seed: seed))
    }

    static func address(seed: Data) throws -> String {
        try instance(seed: seed).address
    }

    static func privateKey(seed: Data) throws -> Data {
        let hdWallet = HDWallet(seed: seed, coinType: coinType, xPrivKey: HDExtendedKeyVersion.xprv.rawValue)
        return try hdWallet.privateKey(account: 0, index: 0, chain: .external).raw
    }
}

public extension Signer {
    enum SignError: Error {
        case invalidPrivateKey
        case invalidDigest
    }
}
