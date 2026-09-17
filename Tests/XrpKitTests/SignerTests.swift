import HdWalletKit
import XCTest
@testable import XrpKit

final class SignerTests: XCTestCase {
    func testSignatureMatchesRippleKeypairsFixture() throws {
        // ripple-keypairs test/fixtures/api.json, secp256k1: sign("test message") is
        // ECDSA over SHA-512Half of the message with RFC 6979 nonces, so it is reproducible
        let privateKey = try XCTUnwrap("D78B9735C3F26501C7337B8A5727FD53A6EFDBC6AA55984F098488561F985E23".xrpHexData)
        let signer = try Signer(privateKey: privateKey)

        XCTAssertEqual(signer.publicKey.xrpHex, "030D58EB48B4420B1F7B9DF55087E0E29FEF0E8468F9A6825B01CA2C361042D435")
        XCTAssertEqual(signer.address, "rU6K7V3Po4snVhBBaU29sesqs2qTQJWDw1")

        let digest = Hashes.sha512Half(Data("test message".utf8))
        let signature = try signer.sign(digest: digest)
        XCTAssertEqual(
            signature.xrpHex,
            "30440220583A91C95E54E6A651C47BEC22744E0B101E2C4060E7B08F6341657DAD9BC3EE02207D1489C7395DB0188D3A56A977ECBA54B36FA9371B40319655B1B4429E33EF2D"
        )

        // DER, 70-72 bytes, deterministic
        XCTAssertEqual(signature.first, 0x30)
        XCTAssertTrue((70 ... 72).contains(signature.count))
        XCTAssertEqual(try signer.sign(digest: digest), signature)
    }

    func testRejectsDigestOfWrongLength() throws {
        let privateKey = try XCTUnwrap("D78B9735C3F26501C7337B8A5727FD53A6EFDBC6AA55984F098488561F985E23".xrpHexData)
        let signer = try Signer(privateKey: privateKey)

        XCTAssertThrowsError(try signer.sign(digest: Data(count: 31)))
        XCTAssertThrowsError(try signer.sign(digest: Data(count: 33)))
        XCTAssertThrowsError(try Signer(privateKey: Data(count: 31)))
    }

    func testBip44DerivationIsDeterministic() throws {
        let words = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".split(separator: " ").map(String.init)
        let seed = try XCTUnwrap(Mnemonic.seed(mnemonic: words))

        // m/44'/144'/0'/0/0 with secp256k1; the same words give the same address in Ledger, Trust Wallet and Xaman
        let address = try Signer.address(seed: seed)
        // computed independently (BIP39 → BIP32 secp256k1 → RIPEMD160(SHA256) → ripple base58check) on 2026-09-17
        XCTAssertEqual(address, "rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3")
        XCTAssertEqual(try Signer.instance(seed: seed).address, address)
        XCTAssertTrue(address.hasPrefix("r"))
        XCTAssertEqual(address.count, 34)
    }
}
