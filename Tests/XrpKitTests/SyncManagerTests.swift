import Combine
import GRDB
import XCTest
@testable import XrpKit

final class SyncManagerTests: XCTestCase {
    private var transport: StubRpcTransport!
    private var connection: StubConnectionManager!
    private var syncManager: SyncManager!
    private var databasePath: String!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        databasePath = NSTemporaryDirectory() + "xrpkit-\(UUID().uuidString).sqlite"
        let pool = try DatabasePool(path: databasePath)
        let mainStorage = try MainStorage(dbPool: pool)
        let transactionStorage = try TransactionStorage(dbPool: pool, address: Fixtures.address)
        transport = StubRpcTransport()
        transport.answer("server_state", .ok(Fixtures.serverState()))
        transport.answer("account_info", .ok(Fixtures.accountInfo()))
        transport.answer("account_lines", .ok(["lines": []]))
        transport.answer("account_tx", .ok(Fixtures.accountTxPage([])))
        let provider = RpcApiProvider(urls: [URL(string: "https://a.example/")!], transport: transport)
        let transactionSyncer = TransactionSyncer(address: Fixtures.address, rpcApiProvider: provider, mainStorage: mainStorage, transactionStorage: transactionStorage)
        connection = StubConnectionManager(connected: true)
        let apiSyncer = ApiSyncer(connectionManager: connection, syncInterval: 60)
        syncManager = SyncManager(address: Fixtures.address, apiSyncer: apiSyncer, rpcApiProvider: provider, transactionSyncer: transactionSyncer, storage: mainStorage)
    }

    override func tearDownWithError() throws {
        syncManager.stop()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databasePath + suffix)
        }
        try super.tearDownWithError()
    }

    private func isNoNetwork(_ state: SyncState) -> Bool {
        if case let .notSynced(error) = state, let syncError = error as? SyncError, case .noNetworkConnection = syncError {
            return true
        }
        return false
    }

    // Reachability is known synchronously, so a connected device goes straight to syncing and
    // never shows the not-connected placeholder before the first sync.
    func testConnectedStartGoesStraightToSyncing() {
        let sawNoNetwork = expectation(description: "no network reported")
        sawNoNetwork.isInverted = true
        let synced = expectation(description: "synced")
        var states = [SyncState]()

        syncManager.$syncState
            .sink { [weak self] state in
                guard let self else { return }
                states.append(state)
                if isNoNetwork(state) { sawNoNetwork.fulfill() }
                if state == .synced { synced.fulfill() }
            }
            .store(in: &cancellables)

        syncManager.start()

        wait(for: [synced, sawNoNetwork], timeout: 3)
        // the publisher emits transitions only: syncing first, synced after the cycle
        XCTAssertEqual(states.first, .syncing(progress: nil))
    }

    // A device that is offline at start reports it at once, as EvmKit and TronKit do.
    func testOfflineStartReportsNoNetworkImmediately() {
        connection.set(connected: false)

        syncManager.start()

        XCTAssertTrue(isNoNetwork(syncManager.syncState))
    }

    // Connectivity coming back moves the kit to syncing and on to synced.
    func testConnectivityReturningResumesSync() {
        connection.set(connected: false)
        let synced = expectation(description: "synced")

        syncManager.$syncState
            .sink { state in
                if state == .synced { synced.fulfill() }
            }
            .store(in: &cancellables)

        syncManager.start()
        XCTAssertTrue(isNoNetwork(syncManager.syncState))

        connection.set(connected: true)

        wait(for: [synced], timeout: 3)
    }
}
