import Combine
import Foundation
import HsExtensions

/// Drives one sync cycle per timer tick: ledger and reserve parameters, account state, trust
/// lines, then transaction history (Android `Syncer`). The single writer to the main tables.
final class SyncManager {
    private static let maxToleratedFailures = 2
    private static let transientRetryDelay: TimeInterval = 3

    private let address: String
    private let apiSyncer: ApiSyncer
    private let rpcApiProvider: RpcApiProvider
    private let transactionSyncer: TransactionSyncer
    private let storage: IMainStorage

    @DistinctPublished private(set) var syncState: SyncState = .notSynced(error: SyncError.notStarted)
    @DistinctPublished private(set) var ledgerState: LedgerState?
    @DistinctPublished private(set) var accountState: AccountState
    @DistinctPublished private(set) var trustLines: [TrustLine]

    private let lock = NSLock()
    private var syncing = false
    private var started = false

    // A connectivity blip right after the app resumes fails one cycle and clears itself within
    // seconds. Once the kit has synced successfully, the first transient failure keeps the
    // current state and retries shortly; only a repeated failure is reported.
    private var hasSyncedOnce = false
    private var consecutiveFailures = 0

    private var tasks = Set<AnyTask>()

    init(address: String, apiSyncer: ApiSyncer, rpcApiProvider: RpcApiProvider, transactionSyncer: TransactionSyncer, storage: IMainStorage) {
        self.address = address
        self.apiSyncer = apiSyncer
        self.rpcApiProvider = rpcApiProvider
        self.transactionSyncer = transactionSyncer
        self.storage = storage

        ledgerState = storage.ledgerState()
        accountState = storage.accountState() ?? .empty
        trustLines = storage.trustLines()

        apiSyncer.delegate = self
    }

    var syncerState: SyncerState {
        apiSyncer.state
    }

    func start() {
        guard !started else { return }
        started = true
        apiSyncer.start()
    }

    func stop() {
        started = false
        tasks = Set()
        apiSyncer.stop()
        syncState = .notSynced(error: SyncError.notStarted)
        transactionSyncer.setNotStarted()
    }

    func pause() {
        apiSyncer.pause()
    }

    func resume() {
        apiSyncer.resume()
    }

    /// Runs a cycle now if the poller is ready; a stopped poller is restarted instead. No-op while paused.
    func refresh() {
        guard started else { return }

        switch apiSyncer.state {
        case .ready:
            sync()
        case .notReady:
            apiSyncer.stop()
            apiSyncer.start()
        }
    }

    /// Runs a full cycle now, outside the timer (after a send).
    func syncNow() async {
        guard acquire() else { return }
        defer { release() }
        await performSync()
    }

    private func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if syncing {
            return false
        }
        syncing = true
        return true
    }

    private func release() {
        lock.lock()
        syncing = false
        lock.unlock()
    }

    private func performSync() async {
        do {
            let serverState = try await rpcApiProvider.serverState()
            let ledgerState = LedgerState(validatedLedger: serverState.validatedLedger, reserveBaseDrops: serverState.reserveBaseDrops, reserveIncDrops: serverState.reserveIncDrops)
            if ledgerState != self.ledgerState {
                try storage.save(ledgerState: ledgerState)
                self.ledgerState = ledgerState
            }

            let info = try await rpcApiProvider.accountInfo(address: address)
            let accountState = info.map { AccountState(exists: true, balanceDrops: $0.balanceDrops, sequence: $0.sequence, ownerCount: $0.ownerCount, flags: $0.flags) } ?? .empty
            if accountState != self.accountState {
                try storage.save(accountState: accountState)
                self.accountState = accountState
            }

            let trustLines: [TrustLine]
            if accountState.exists, accountState.ownerCount > 0 {
                trustLines = try await rpcApiProvider.accountLines(address: address).map { line in
                    guard let balance = Decimal(xrplValue: line.balance), let limit = Decimal(xrplValue: line.limit) else {
                        throw InvalidResponse("account_lines: balance or limit is not a decimal")
                    }
                    return TrustLine(
                        currency: line.currency,
                        issuer: line.issuer,
                        balance: balance,
                        limit: limit,
                        noRipple: line.noRipple,
                        // account_lines reports "freeze" from the account's own side and
                        // "freeze_peer" from the issuer's; the issuer's freeze is what blocks sends
                        frozen: line.frozenByPeer,
                        frozenByHolder: line.frozen,
                        authorized: line.authorized
                    )
                }
            } else {
                trustLines = []
            }
            if trustLines != self.trustLines {
                try storage.replace(trustLines: trustLines)
                self.trustLines = trustLines
            }

            try await transactionSyncer.sync(validatedLedger: serverState.validatedLedger, accountExists: accountState.exists)

            hasSyncedOnce = true
            consecutiveFailures = 0
            syncState = .synced
        } catch is CancellationError {
            return
        } catch {
            consecutiveFailures += 1
            let tolerate = hasSyncedOnce && consecutiveFailures < Self.maxToleratedFailures && NetworkErrors.isTransient(error)
            if tolerate {
                Task { [weak self] in
                    try await Task.sleep(nanoseconds: UInt64(Self.transientRetryDelay * 1_000_000_000))
                    self?.sync()
                }.store(in: &tasks)
            } else {
                syncState = .notSynced(error: error)
                transactionSyncer.setNotSynced(error: error)
            }
        }
    }
}

extension SyncManager: IApiSyncerDelegate {
    func didUpdateSyncerState(_ state: SyncerState) {
        switch state {
        case .ready:
            syncState = .syncing(progress: nil)
        case let .notReady(error):
            transactionSyncer.setNotSynced(error: error)
            syncState = .notSynced(error: error)
        }
    }

    func sync() {
        guard started, acquire() else { return }

        Task { [weak self] in
            guard let self else { return }
            defer { self.release() }
            await performSync()
        }.store(in: &tasks)
    }
}
