import Combine
import GRDB
import HdWalletKit
import XCTest
@testable import XrpKit

final class TransactionSenderTests: XCTestCase {
    private let urls = [URL(string: "https://a.example/")!, URL(string: "https://b.example/")!, URL(string: "https://c.example/")!]
    private var transport: StubRpcTransport!
    private var provider: RpcApiProvider!
    private var transactionStorage: TransactionStorage!
    private var transactionSyncer: TransactionSyncer!
    private var sender: TransactionSender!
    private var signer: Signer!
    private var databasePath: String!
    private var published: [[Transaction]] = []
    private var cancellables = Set<AnyCancellable>()

    // the ripple-keypairs key: its address is the kit's address in these tests
    private let address = "rU6K7V3Po4snVhBBaU29sesqs2qTQJWDw1"

    override func setUpWithError() throws {
        try super.setUpWithError()
        databasePath = NSTemporaryDirectory() + "xrpkit-sender-\(UUID().uuidString).sqlite"
        let pool = try DatabasePool(path: databasePath)
        let mainStorage = try MainStorage(dbPool: pool)
        transactionStorage = try TransactionStorage(dbPool: pool, address: address)
        transport = StubRpcTransport()
        provider = RpcApiProvider(urls: urls, transport: transport)
        transactionSyncer = TransactionSyncer(address: address, rpcApiProvider: provider, mainStorage: mainStorage, transactionStorage: transactionStorage)
        sender = TransactionSender(address: address, rpcApiProvider: provider, submitter: TransactionSubmitter(rpcApiProvider: provider), storage: transactionStorage, transactionSyncer: transactionSyncer)
        signer = try Signer(privateKey: XCTUnwrap("D78B9735C3F26501C7337B8A5727FD53A6EFDBC6AA55984F098488561F985E23".xrpHexData))
        transactionSyncer.transactionsPublisher.sink { [weak self] in self?.published.append($0) }.store(in: &cancellables)

        transport.answer("account_info", .ok(["account_data": ["Account": address, "Balance": "25000000", "Sequence": 5, "OwnerCount": 0]]))
        transport.answer("fee", .ok(["drops": ["base_fee": "10", "open_ledger_fee": "12", "minimum_fee": "10", "median_fee": "5000"]]))
        transport.answer("server_state", .ok(Fixtures.serverState(validated: 1000)))
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databasePath + suffix)
        }
        try super.tearDownWithError()
    }

    private func send() async throws -> Transaction {
        try await sender.sendPayment(signer: signer, destination: Fixtures.other, amount: .xrp(drops: 1_000_000), destinationTag: 42, memo: "hi")
    }

    private func submitBlobs() -> [String] {
        transport.calls(method: "submit").compactMap { $0.params["tx_blob"] as? String }
    }

    func testAcceptedSubmitKeepsPendingRecordAndPublishesIt() async throws {
        transport.answer("submit", .ok(["engine_result": "tesSUCCESS", "engine_result_code": 0, "accepted": true, "applied": true]))

        let transaction = try await send()

        XCTAssertTrue(transaction.isPending)
        XCTAssertEqual(transaction.sequence, 5)
        XCTAssertEqual(transaction.lastLedgerSequence, 1000 + TransactionSender.lastLedgerOffset)
        XCTAssertEqual(transaction.feeDrops, 12)
        XCTAssertEqual(transaction.destinationTag, 42)
        XCTAssertEqual(transaction.memo, "hi")
        XCTAssertEqual(transactionStorage.transaction(hash: transaction.hash)?.hash, transaction.hash)
        XCTAssertEqual(published.flatMap { $0 }.map(\.hash), [transaction.hash])
        XCTAssertEqual(submitBlobs().count, 1)
    }

    func testDeterministicRejectionDropsPendingRecord() async {
        transport.answer("submit", .ok(["engine_result": "temBAD_AMOUNT", "engine_result_code": -298, "engine_result_message": "Malformed: Bad amount."]))

        do {
            _ = try await send()
            XCTFail("expected rejection")
        } catch let error as SendError {
            XCTAssertEqual(error, .rejected(engineResult: "temBAD_AMOUNT", message: "Malformed: Bad amount."))
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(transactionStorage.pendingTransactions().isEmpty)
        XCTAssertTrue(transactionStorage.allTransactions().isEmpty)
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(submitBlobs().count, 1, "a deterministic rejection is not retried on other nodes")
    }

    func testNodeLocalFailureFallsBackWithTheSameBlob() async throws {
        transport.answer(url: urls[0], "submit", .rpcError(code: "tooBusy"))
        transport.answer(url: urls[1], "submit", .ok(["engine_result": "telINSUF_FEE_P", "engine_result_code": -394]))
        transport.answer(url: urls[2], "submit", .ok(["engine_result": "terQUEUED", "engine_result_code": -89, "queued": true]))

        let transaction = try await send()

        let blobs = submitBlobs()
        XCTAssertEqual(blobs.count, 3)
        XCTAssertEqual(Set(blobs).count, 1, "the very same signed blob goes to every node")
        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: transaction.hash)).isPending)
    }

    func testSilenceOnEveryNodeKeepsPendingRecord() async throws {
        for url in urls {
            transport.answer(url: url, "submit", .error(URLError(.timedOut)))
        }

        let transaction = try await send()

        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: transaction.hash)).isPending, "unknown outcome is not a rejection")
        XCTAssertEqual(submitBlobs().count, 3)
        XCTAssertEqual(published.flatMap { $0 }.map(\.hash), [transaction.hash])
    }

    func testPastSequenceAfterSilenceIsUnknownNotRejected() async throws {
        transport.answer(url: urls[0], "submit", .error(URLError(.networkConnectionLost)))
        transport.answer(url: urls[1], "submit", .ok(["engine_result": "tefPAST_SEQ", "engine_result_code": -190]))
        transport.answer(url: urls[2], "submit", .ok(["engine_result": "tefPAST_SEQ", "engine_result_code": -190]))

        let transaction = try await send()
        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: transaction.hash)).isPending)
    }

    func testAlreadyKnownIsAccepted() async throws {
        transport.answer(url: urls[0], "submit", .error(URLError(.timedOut)))
        transport.answer(url: urls[1], "submit", .ok(["engine_result": "tefALREADY", "engine_result_code": -196]))

        let transaction = try await send()
        XCTAssertTrue(try XCTUnwrap(transactionStorage.transaction(hash: transaction.hash)).isPending)
        XCTAssertEqual(submitBlobs().count, 2, "tefALREADY stops the loop")
    }

    func testConnectionRefusedIsNodeLocalNotUnknown() async throws {
        transport.answer(url: urls[0], "submit", .error(URLError(.cannotConnectToHost)))
        transport.answer(url: urls[1], "submit", .ok(["engine_result": "tesSUCCESS", "engine_result_code": 0]))

        _ = try await send()
        XCTAssertEqual(submitBlobs().count, 2)
    }

    func testFeeIsMaxOfBaseAndOpenLedgerCapped() {
        XCTAssertEqual(TransactionSender.feeDrops(FeeInfo(baseFeeDrops: 10, openLedgerFeeDrops: 12, minimumFeeDrops: 10, medianFeeDrops: 100)), 12)
        XCTAssertEqual(TransactionSender.feeDrops(FeeInfo(baseFeeDrops: 10, openLedgerFeeDrops: 5, minimumFeeDrops: 10, medianFeeDrops: 100)), 10)
        XCTAssertEqual(TransactionSender.feeDrops(FeeInfo(baseFeeDrops: 10, openLedgerFeeDrops: 1_000_000, minimumFeeDrops: 10, medianFeeDrops: 100)), TransactionSender.maxFeeDrops)
    }

    func testGuardsBeforeAnythingIsSigned() async throws {
        let otherSigner = try Signer.instance(seed: XCTUnwrap(HdWalletKitMnemonic.seed()))
        do {
            _ = try await sender.sendPayment(signer: otherSigner, destination: Fixtures.other, amount: .xrp(drops: 1), destinationTag: nil, memo: nil)
            XCTFail("expected signerMismatch")
        } catch let error as SendError {
            XCTAssertEqual(error, .signerMismatch)
        }

        do {
            _ = try await sender.sendPayment(signer: signer, destination: Fixtures.other, amount: .xrp(drops: 1), destinationTag: nil, memo: String(repeating: "m", count: 1100))
            XCTFail("expected memoTooLong")
        } catch let error as SendError {
            XCTAssertEqual(error, .memoTooLong)
        }

        transport.answer("account_info", .rpcError(code: "actNotFound"))
        do {
            _ = try await send()
            XCTFail("expected accountNotFound")
        } catch let error as SendError {
            XCTAssertEqual(error, .accountNotFound)
        }

        XCTAssertTrue(transport.calls(method: "submit").isEmpty)
        XCTAssertTrue(transactionStorage.allTransactions().isEmpty)
    }
}

enum HdWalletKitMnemonic {
    static func seed() -> Data? {
        Mnemonic.seed(mnemonic: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about".split(separator: " ").map(String.init))
    }
}
