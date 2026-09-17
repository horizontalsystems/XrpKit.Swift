import XCTest
@testable import XrpKit

final class TransactionConverterTests: XCTestCase {
    private func raw(_ json: RpcJson) throws -> RawTransaction {
        let page = try AccountTxJsonRpc(address: Fixtures.address, ledgerIndexMin: -1, ledgerIndexMax: -1, limit: 1, forward: false, marker: nil)
            .parse(result: Fixtures.accountTxPage([json]))
        return try XCTUnwrap(page.transactions.first)
    }

    func testSuccessfulPaymentUsesDeliveredAmount() throws {
        let tx = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "A", ledgerIndex: 10, drops: "5000000", delivered: "4000000")))

        XCTAssertEqual(tx.amount, .xrp(drops: 5_000_000))
        XCTAssertEqual(tx.deliveredAmount, .xrp(drops: 4_000_000))
        XCTAssertEqual(tx.timestamp, 800_000_000 + TransactionConverter.rippleEpochOffset)
        XCTAssertTrue(tx.isSuccess)
        XCTAssertFalse(tx.failed)
        XCTAssertTrue(tx.isIncoming(ownAddress: Fixtures.address))
        XCTAssertEqual(tx.feeDrops, 12)
    }

    func testPartialPaymentWithoutDeliveredAmountHasNoFallback() throws {
        let partial = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "B", ledgerIndex: 10, drops: "10000000000", flags: TransactionConverter.tfPartialPayment)))
        XCTAssertEqual(partial.amount, .xrp(drops: 10_000_000_000))
        XCTAssertNil(partial.deliveredAmount)

        let partialDelivered = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "C", ledgerIndex: 10, drops: "10000000000", flags: TransactionConverter.tfPartialPayment, delivered: "1")))
        XCTAssertEqual(partialDelivered.deliveredAmount, .xrp(drops: 1))

        let full = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "D", ledgerIndex: 10, drops: "7")))
        XCTAssertEqual(full.deliveredAmount, .xrp(drops: 7), "a successful non-partial payment falls back to Amount")
    }

    func testUnavailableDeliveredAmountIsNil() throws {
        let tx = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "E", ledgerIndex: 10, delivered: "unavailable")))
        XCTAssertNil(tx.deliveredAmount)
    }

    func testFailedPaymentIsFailedAndNotSuccess() throws {
        let tx = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "F", ledgerIndex: 10, result: "tecUNFUNDED_PAYMENT")))
        XCTAssertTrue(tx.failed)
        XCTAssertFalse(tx.isSuccess)
        XCTAssertNil(tx.deliveredAmount)
    }

    func testIssuedAmountsAndTrustSetLimit() throws {
        var json = Fixtures.payment(hash: "G", ledgerIndex: 10)
        var tx = json["tx"] as! RpcJson
        tx["Amount"] = ["value": "12.5", "currency": "USD", "issuer": Fixtures.issuer]
        json["tx"] = tx
        var meta = json["meta"] as! RpcJson
        meta["delivered_amount"] = ["value": "12.5", "currency": "USD", "issuer": Fixtures.issuer]
        json["meta"] = meta

        let payment = try TransactionConverter.transaction(accountTx: raw(json))
        XCTAssertEqual(payment.amount, .issued(value: Decimal(string: "12.5")!, currency: "USD", issuer: Fixtures.issuer))
        XCTAssertEqual(payment.deliveredAmount, payment.amount)

        let trustSet: RpcJson = [
            "tx": ["TransactionType": "TrustSet", "Account": Fixtures.address, "Fee": "12", "Sequence": 8, "hash": "H", "ledger_index": 11, "date": 1,
                   "LimitAmount": ["value": "1000000", "currency": "USD", "issuer": Fixtures.issuer]],
            "meta": ["TransactionResult": "tesSUCCESS"], "validated": true,
        ]
        let record = try TransactionConverter.transaction(accountTx: raw(trustSet))
        XCTAssertEqual(record.type, "TrustSet")
        XCTAssertNil(record.amount)
        XCTAssertEqual(record.limitAmount, .issued(value: 1_000_000, currency: "USD", issuer: Fixtures.issuer))
    }

    func testMemoDecoding() throws {
        let text = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "I", ledgerIndex: 10, memoHex: Data("hi\nthere".utf8).xrpHex)))
        XCTAssertEqual(text.memo, "hi\nthere")

        let control = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "J", ledgerIndex: 10, memoHex: "6869001B")))
        XCTAssertNil(control.memo)

        let invalidUtf8 = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "K", ledgerIndex: 10, memoHex: "FFFE")))
        XCTAssertNil(invalidUtf8.memo)

        let none = try TransactionConverter.transaction(accountTx: raw(Fixtures.payment(hash: "L", ledgerIndex: 10)))
        XCTAssertNil(none.memo)
    }

    func testMalformedAmountIsAbsentNotCrash() throws {
        var json = Fixtures.payment(hash: "M", ledgerIndex: 10)
        var tx = json["tx"] as! RpcJson
        tx["Amount"] = "-5"
        json["tx"] = tx
        let record = try TransactionConverter.transaction(accountTx: raw(json))
        XCTAssertNil(record.amount)
    }
}
