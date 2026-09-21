import GRDB
import XCTest
@testable import XrpKit

final class TransactionSyncerTests: XCTestCase {
    private var transport: StubRpcTransport!
    private var provider: RpcApiProvider!
    private var mainStorage: MainStorage!
    private var transactionStorage: TransactionStorage!
    private var syncer: TransactionSyncer!
    private var databasePath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databasePath = NSTemporaryDirectory() + "xrpkit-\(UUID().uuidString).sqlite"
        let pool = try DatabasePool(path: databasePath)
        mainStorage = try MainStorage(dbPool: pool)
        transactionStorage = try TransactionStorage(dbPool: pool, address: Fixtures.address)
        transport = StubRpcTransport()
        provider = RpcApiProvider(urls: [URL(string: "https://a.example/")!], transport: transport)
        syncer = TransactionSyncer(address: Fixtures.address, rpcApiProvider: provider, mainStorage: mainStorage, transactionStorage: transactionStorage)
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databasePath + suffix)
        }
        try super.tearDownWithError()
    }

    func testInitialSyncWalksBackwardsPageByPageAndMarksDone() async throws {
        transport.answer(
            "account_tx",
            .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "A", ledgerIndex: 900), Fixtures.payment(hash: "B", ledgerIndex: 800)], marker: ["ledger": 800, "seq": 1])),
            .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "C", ledgerIndex: 700)]))
        )

        try await syncer.sync(validatedLedger: 1000, accountExists: true)

        XCTAssertEqual(Set(try transactionStorage.allTransactions().map(\.hash)), ["A", "B", "C"])
        let state = try XCTUnwrap(mainStorage.transactionSyncState())
        XCTAssertTrue(state.initialSyncDone)
        XCTAssertEqual(state.lastSyncedLedger, 1000)
        XCTAssertEqual(syncer.syncState, .synced)

        let firstCall = transport.calls(method: "account_tx")[0]
        XCTAssertEqual(firstCall.params["ledger_index_max"] as? Int64, 1000)
        XCTAssertEqual(firstCall.params["forward"] as? Bool, false)
    }

    func testInterruptedInitialSyncResumesFromOldestStoredTransaction() async throws {
        transport.answer(
            "account_tx",
            .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "A", ledgerIndex: 900), Fixtures.payment(hash: "B", ledgerIndex: 800)], marker: ["ledger": 800, "seq": 1])),
            .error(URLError(.networkConnectionLost))
        )

        do {
            try await syncer.sync(validatedLedger: 1000, accountExists: true)
            XCTFail("expected the second page to fail")
        } catch {}

        XCTAssertEqual(Set(try transactionStorage.allTransactions().map(\.hash)), ["A", "B"], "the first page is kept")
        XCTAssertEqual(try mainStorage.transactionSyncState()?.initialSyncDone, false)
        XCTAssertTrue(syncer.syncState.notSynced)

        // next cycle: the ledger moved on and one more page of old history exists; the resumed walk
        // starts below the oldest stored ledger and the gap up to the new validated ledger is filled forward
        transport.answer(
            "account_tx",
            .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "B", ledgerIndex: 800), Fixtures.payment(hash: "C", ledgerIndex: 700)])),
            .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "D", ledgerIndex: 1005)]))
        )

        try await syncer.sync(validatedLedger: 1010, accountExists: true)

        XCTAssertEqual(Set(try transactionStorage.allTransactions().map(\.hash)), ["A", "B", "C", "D"])
        let calls = transport.calls(method: "account_tx")
        XCTAssertEqual(calls[2].params["ledger_index_max"] as? Int64, 800, "resumes from the oldest stored ledger")
        XCTAssertEqual(calls[3].params["ledger_index_min"] as? Int64, 1001, "then fills forward from the ledger the walk started at")
        XCTAssertEqual(calls[3].params["ledger_index_max"] as? Int64, 1010)
        let state = try XCTUnwrap(mainStorage.transactionSyncState())
        XCTAssertTrue(state.initialSyncDone)
        XCTAssertEqual(state.lastSyncedLedger, 1010)
    }

    func testIncrementalSyncFetchesOnlyNewLedgers() async throws {
        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: 1000, initialSyncDone: true))
        transport.answer("account_tx", .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "N", ledgerIndex: 1003)])))

        try await syncer.sync(validatedLedger: 1005, accountExists: true)

        let call = transport.calls(method: "account_tx")[0]
        XCTAssertEqual(call.params["ledger_index_min"] as? Int64, 1001)
        XCTAssertEqual(call.params["ledger_index_max"] as? Int64, 1005)
        XCTAssertEqual(call.params["forward"] as? Bool, true)
        XCTAssertEqual(try mainStorage.transactionSyncState()?.lastSyncedLedger, 1005)

        try await syncer.sync(validatedLedger: 1005, accountExists: true)
        XCTAssertEqual(transport.calls(method: "account_tx").count, 1, "nothing to fetch when the ledger did not move")
    }

    func testEndlessMarkerIsRejected() async throws {
        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: 1000, initialSyncDone: true))
        transport.answer("account_tx", .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "X", ledgerIndex: 1001)], marker: "forever")))

        do {
            try await syncer.sync(validatedLedger: 1005, accountExists: true)
            XCTFail("expected InvalidResponse")
        } catch is InvalidResponse {
            XCTAssertEqual(transport.calls(method: "account_tx").count, TransactionSyncer.maxPages)
        }
        XCTAssertEqual(try mainStorage.transactionSyncState()?.lastSyncedLedger, 1000, "cursor is not advanced")
    }

    func testPendingExpiresOnlyOnExplicitTxnNotFound() async throws {
        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: 1000, initialSyncDone: true))
        let pending = Transaction(
            hash: "P", ledgerIndex: nil, timestamp: 1, type: "Payment", account: Fixtures.address, destination: Fixtures.other,
            amount: .xrp(drops: 1), deliveredAmount: nil, feeDrops: 12, sequence: 5, destinationTag: nil, sourceTag: nil,
            limitAmount: nil, result: nil, validated: false, failed: false, lastLedgerSequence: 990, memo: nil
        )
        try transactionStorage.save(transactions: [pending])

        // node unreachable: decision postponed
        transport.answer("tx", .error(URLError(.timedOut)))
        try await syncer.sync(validatedLedger: 1000, accountExists: true)
        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: "P")).isPending)

        // node knows it but not validated yet: still pending
        transport.answer("tx", .ok(["hash": "P", "validated": false, "TransactionType": "Payment", "Account": Fixtures.address]))
        try await syncer.sync(validatedLedger: 1000, accountExists: true)
        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: "P")).isPending)

        // node explicitly does not know it: expired
        transport.answer("tx", .rpcError(code: "txnNotFound"))
        try await syncer.sync(validatedLedger: 1000, accountExists: true)
        let expired = try XCTUnwrap(transactionStorage.transaction(hash: "P"))
        XCTAssertTrue(expired.failed)
        XCTAssertEqual(expired.result, Transaction.expiredResult)
        XCTAssertTrue(try transactionStorage.pendingTransactions().isEmpty)
    }

    func testValidatedRecordReplacesPending() async throws {
        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: 1000, initialSyncDone: true))
        let pending = Transaction(
            hash: "Q", ledgerIndex: nil, timestamp: 1, type: "Payment", account: Fixtures.address, destination: Fixtures.other,
            amount: .xrp(drops: 1), deliveredAmount: nil, feeDrops: 12, sequence: 5, destinationTag: nil, sourceTag: nil,
            limitAmount: nil, result: nil, validated: false, failed: false, lastLedgerSequence: 1020, memo: nil
        )
        try transactionStorage.save(transactions: [pending])

        transport.answer("account_tx", .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "Q", ledgerIndex: 1003, from: Fixtures.address, to: Fixtures.other, drops: "1")])))
        try await syncer.sync(validatedLedger: 1005, accountExists: true)

        let stored = try transactionStorage.allTransactions()
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored[0].validated)
        XCTAssertEqual(stored[0].ledgerIndex, 1003)
        XCTAssertTrue(try transactionStorage.pendingTransactions().isEmpty)
    }

    // Paging from a hash that is no longer stored must not restart from the top: the list would
    // show the newest page again under the oldest one.
    func testPagingFromUnknownAnchorReturnsNothing() async throws {
        transport.answer("account_tx", .ok(Fixtures.accountTxPage([Fixtures.payment(hash: "A", ledgerIndex: 900, date: 800_000_100), Fixtures.payment(hash: "B", ledgerIndex: 800, date: 800_000_000)])))
        try await syncer.sync(validatedLedger: 1000, accountExists: true)

        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(), fromHash: "A", limit: 10).map(\.hash), ["B"])
        XCTAssertTrue(try transactionStorage.transactions(tagQuery: TagQuery(), fromHash: "GONE", limit: 10).isEmpty)
    }

    func testTagQueryFiltersAndPaging() throws {
        let usd = Amount.issued(value: 5, currency: "USD", issuer: Fixtures.issuer)
        let records = [
            Transaction(hash: "1", ledgerIndex: 1, timestamp: 100, type: "Payment", account: Fixtures.other, destination: Fixtures.address, amount: .xrp(drops: 1), deliveredAmount: .xrp(drops: 1), feeDrops: 1, sequence: 1, destinationTag: nil, sourceTag: nil, limitAmount: nil, result: "tesSUCCESS", validated: true, failed: false, lastLedgerSequence: nil, memo: nil),
            Transaction(hash: "2", ledgerIndex: 2, timestamp: 200, type: "Payment", account: Fixtures.address, destination: Fixtures.other, amount: usd, deliveredAmount: usd, feeDrops: 1, sequence: 2, destinationTag: nil, sourceTag: nil, limitAmount: nil, result: "tesSUCCESS", validated: true, failed: false, lastLedgerSequence: nil, memo: nil),
            Transaction(hash: "3", ledgerIndex: 3, timestamp: 300, type: "TrustSet", account: Fixtures.address, destination: nil, amount: nil, deliveredAmount: nil, feeDrops: 1, sequence: 3, destinationTag: nil, sourceTag: nil, limitAmount: usd, result: "tesSUCCESS", validated: true, failed: false, lastLedgerSequence: nil, memo: nil),
            Transaction(hash: "4", ledgerIndex: 4, timestamp: 400, type: "Payment", account: Fixtures.address, destination: Fixtures.other, amount: .xrp(drops: 2), deliveredAmount: .xrp(drops: 2), feeDrops: 1, sequence: 4, destinationTag: nil, sourceTag: nil, limitAmount: nil, result: "tesSUCCESS", validated: true, failed: false, lastLedgerSequence: nil, memo: nil),
        ]
        try transactionStorage.save(transactions: records)

        XCTAssertEqual(try transactionStorage.allTransactions().map(\.hash), ["4", "3", "2", "1"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(token: .native), fromHash: nil, limit: nil).map(\.hash), ["4", "3", "1"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(token: .issued(currency: "USD", issuer: Fixtures.issuer)), fromHash: nil, limit: nil).map(\.hash), ["3", "2"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(direction: .incoming), fromHash: nil, limit: nil).map(\.hash), ["1"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(direction: .outgoing, token: .native), fromHash: nil, limit: nil).map(\.hash), ["4", "3"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(address: Fixtures.other), fromHash: nil, limit: nil).map(\.hash), ["4", "2", "1"])
        XCTAssertEqual(try transactionStorage.transactions(tagQuery: TagQuery(), fromHash: "3", limit: 1).map(\.hash), ["2"])
        XCTAssertEqual(try transactionStorage.oldestValidatedTransaction()?.hash, "1")
    }
}
