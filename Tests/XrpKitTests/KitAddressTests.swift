import XCTest
@testable import XrpKit

final class KitAddressTests: XCTestCase {
    private let classic = "rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpf"
    private let mainNetWithTag = "XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi" // tag 4294967295
    private let testNetWithTag = "T7oKJ3q7s94kDH6tpkBowhetT1JKfcfdSCmAXbS75iATyLD" // r3SVzk8ApofDJuVBPKdmbbLjWGCCXpBQ2g, tag 123

    func testValidation() {
        XCTAssertTrue(Kit.isValid(address: classic))
        XCTAssertTrue(Kit.isValid(address: mainNetWithTag))
        XCTAssertTrue(Kit.isValid(address: testNetWithTag))
        XCTAssertFalse(Kit.isValid(address: "rGWrZyQqhTp9Xu7G5Pkayo7bXjH4k4QYpg"))
        XCTAssertFalse(Kit.isValid(address: "XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHj"))
        XCTAssertFalse(Kit.isValid(address: ""))
        XCTAssertNil(Kit.decode(xAddress: classic))
        XCTAssertEqual(Kit.decode(xAddress: mainNetWithTag)?.tag, 4_294_967_295)
    }

    func testClassicAddressKeepsTypedTag() throws {
        let resolved = try Kit.resolveDestination(address: classic, tag: 7, network: .mainNet)
        XCTAssertEqual(resolved.classic, classic)
        XCTAssertEqual(resolved.tag, 7)
        XCTAssertNil(try Kit.resolveDestination(address: classic, tag: nil, network: .mainNet).tag)
    }

    func testXAddressPinsItsTag() throws {
        let resolved = try Kit.resolveDestination(address: mainNetWithTag, tag: nil, network: .mainNet)
        XCTAssertEqual(resolved.classic, classic)
        XCTAssertEqual(resolved.tag, 4_294_967_295)

        let sameTag = try Kit.resolveDestination(address: mainNetWithTag, tag: 4_294_967_295, network: .mainNet)
        XCTAssertEqual(sameTag.tag, 4_294_967_295)
    }

    func testTypedTagConflictingWithXAddressIsAnError() {
        XCTAssertThrowsError(try Kit.resolveDestination(address: mainNetWithTag, tag: 1, network: .mainNet)) { error in
            XCTAssertEqual(error as? AddressError, .tagConflict)
        }
    }

    func testXAddressOfOtherNetworkIsAnError() {
        XCTAssertThrowsError(try Kit.resolveDestination(address: testNetWithTag, tag: nil, network: .mainNet)) { error in
            XCTAssertEqual(error as? AddressError, .networkMismatch)
        }
        XCTAssertThrowsError(try Kit.resolveDestination(address: mainNetWithTag, tag: nil, network: .testNet)) { error in
            XCTAssertEqual(error as? AddressError, .networkMismatch)
        }
        XCTAssertEqual(try Kit.resolveDestination(address: testNetWithTag, tag: nil, network: .testNet).tag, 123)
    }

    func testTaglessXAddressKeepsTypedTagAndExplicitZeroWins() throws {
        let accountId = try AccountId.fromAddress(classic)
        let tagless = XAddress.encode(accountId: accountId, tag: nil)
        XCTAssertEqual(try Kit.resolveDestination(address: tagless, tag: 9, network: .mainNet).tag, 9)

        let zero = XAddress.encode(accountId: accountId, tag: 0)
        XCTAssertEqual(try Kit.resolveDestination(address: zero, tag: nil, network: .mainNet).tag, 0)
        XCTAssertThrowsError(try Kit.resolveDestination(address: zero, tag: 9, network: .mainNet))
    }

    func testDropsConversion() throws {
        XCTAssertEqual(try Kit.drops(xrp: 1), 1_000_000)
        XCTAssertEqual(try Kit.drops(xrp: Decimal(string: "0.000001")!), 1)
        XCTAssertEqual(try Kit.drops(xrp: Decimal(string: "12.345678")!), 12_345_678)
        XCTAssertThrowsError(try Kit.drops(xrp: Decimal(string: "0.0000001")!), "finer than a drop")
        XCTAssertThrowsError(try Kit.drops(xrp: -1))
    }

    func testMinimumBalance() {
        XCTAssertEqual(Kit.minimumBalance(accountState: .empty, ledgerState: nil), 0)
        let active = AccountState(exists: true, balanceDrops: 5_000_000, sequence: 1, ownerCount: 2, flags: 0)
        XCTAssertEqual(Kit.minimumBalance(accountState: active, ledgerState: nil), Decimal(string: "1.4")!)
        let ledger = LedgerState(validatedLedger: 1, reserveBaseDrops: 10_000_000, reserveIncDrops: 2_000_000)
        XCTAssertEqual(Kit.minimumBalance(accountState: active, ledgerState: ledger), 14)
    }

    func testCurrencyHelpers() {
        XCTAssertTrue(Kit.isValidCurrencyCode("USD"))
        XCTAssertFalse(Kit.isValidCurrencyCode("XRP"))
        XCTAssertEqual(Kit.displayCurrencyCode("524C555344000000000000000000000000000000"), "RLUSD")
    }
}
