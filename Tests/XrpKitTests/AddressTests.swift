import XCTest
@testable import XrpKit

final class AddressTests: XCTestCase {
    func testBase58RoundTrip() throws {
        let samples: [Data] = [
            Data(),
            Data([0]),
            Data([0, 0, 1]),
            Data([0x7F, 0x00, 0xFF]),
            Data((0 ..< 20).map { UInt8($0) }),
            Data((0 ..< 33).map { UInt8(($0 * 7) & 0xFF) }),
        ]
        for sample in samples {
            XCTAssertEqual(try XrpBase58.decode(XrpBase58.encode(sample)), sample)
        }
    }

    func testAccountIdFromPublicKey() throws {
        // ripple-keypairs fixture: secp256k1 key pair of seed sp5fghtJtpUorTwvof1NpDXAzNwf5
        let publicKey = try XCTUnwrap("030D58EB48B4420B1F7B9DF55087E0E29FEF0E8468F9A6825B01CA2C361042D435".xrpHexData)
        XCTAssertEqual(try AccountId.fromPublicKey(publicKey).address, "rU6K7V3Po4snVhBBaU29sesqs2qTQJWDw1")

        // the genesis "masterpassphrase" account
        let master = try XCTUnwrap("0330E7FC9D56BB25D6893BA3F317AE5BCF33B3291BD63DB32654A313222F7FD020".xrpHexData)
        XCTAssertEqual(try AccountId.fromPublicKey(master).address, "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")
    }

    func testAccountIdFromAddress() throws {
        let address = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
        let accountId = try AccountId.fromAddress(address)
        XCTAssertEqual(accountId.bytes.xrpHex, "B5F762798A53D543A014CAF8B297CFF8F2F937E8")
        XCTAssertEqual(accountId.address, address)
    }

    func testInvalidAddresses() {
        XCTAssertFalse(AccountId.isValid(address: ""))
        XCTAssertFalse(AccountId.isValid(address: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTg")) // checksum
        XCTAssertFalse(AccountId.isValid(address: "GBHFGY3ZNEJWLNO4LBUKLYOCEK4V7ENEBJGPRHHX7JU47GWHBREH37UR")) // stellar
        XCTAssertFalse(AccountId.isValid(address: "0x8292bb45bf1ee4d140127049757c2e0ff06317ed"))
        XCTAssertFalse(AccountId.isValid(address: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh0")) // '0' not in alphabet
        XCTAssertFalse(AccountId.isValid(address: "1Hb9CJAWyB4rj91VRWn96DkukG4bwdtyTh")) // bitcoin alphabet leading '1'
        XCTAssertTrue(AccountId.isValid(address: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"))
    }

    func testXAddressEncodeDecode() throws {
        // ripple-address-codec README vectors
        let classic = try AccountId.fromAddress("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")
        XCTAssertEqual(XAddress.encode(accountId: classic, tag: 4_294_967_295), "XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi")

        let decoded = try XAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi")
        XCTAssertEqual(decoded.classicAddress, "rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")
        XCTAssertEqual(decoded.tag, 4_294_967_295)
        XCTAssertFalse(decoded.isTestNet)

        let testNet = try AccountId.fromAddress("r3SVzk8ApofDJuVBPKdmbbLjWGCCXpBQ2g")
        XCTAssertEqual(XAddress.encode(accountId: testNet, tag: 123, testNet: true), "T7oKJ3q7s94kDH6tpkBowhetT1JKfcfdSCmAXbS75iATyLD")
        let decodedTestNet = try XAddress.decode("T7oKJ3q7s94kDH6tpkBowhetT1JKfcfdSCmAXbS75iATyLD")
        XCTAssertEqual(decodedTestNet.tag, 123)
        XCTAssertTrue(decodedTestNet.isTestNet)

        let noTag = try XAddress.decode(XAddress.encode(accountId: classic, tag: nil))
        XCTAssertNil(noTag.tag)
        XCTAssertEqual(noTag.accountId, classic)
    }

    func testXAddressExplicitZeroTagIsATag() throws {
        let classic = try AccountId.fromAddress("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")
        let zeroTag = try XAddress.decode(XAddress.encode(accountId: classic, tag: 0))
        XCTAssertEqual(zeroTag.tag, 0)
        XCTAssertNotEqual(XAddress.encode(accountId: classic, tag: 0), XAddress.encode(accountId: classic, tag: nil))
    }

    func testXAddressRejectsUnsupportedForms() throws {
        let classic = try AccountId.fromAddress("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf")

        // tag flag 2 (64-bit tag, never issued) and non-zero reserved bytes are rejected
        var payload = Data([0x05, 0x44]) + classic.bytes + Data(count: 9)
        payload[22] = 2
        XCTAssertThrowsError(try XAddress.decode(XrpBase58.encodeChecked(payload)))

        payload[22] = 1
        payload[30] = 1
        XCTAssertThrowsError(try XAddress.decode(XrpBase58.encodeChecked(payload)))

        // wrong prefix, bad checksum, classic address
        XCTAssertThrowsError(try XAddress.decode(XrpBase58.encodeChecked(Data([0x01, 0x02]) + classic.bytes + Data(count: 9))))
        XCTAssertThrowsError(try XAddress.decode("XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHj"))
        XCTAssertThrowsError(try XAddress.decode("rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf"))
    }
}
