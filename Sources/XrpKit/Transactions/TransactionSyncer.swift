import Combine
import Foundation
import HsExtensions

/// Keeps the local transaction table in step with `account_tx`.
///
/// The first sync walks history newest-first, page by page into the database (StellarKit
/// `OperationManager` idiom): an interrupted walk resumes from the oldest stored transaction.
/// Later syncs fetch only ledgers after the last synced one. Pending transactions the kit
/// submitted are replaced when they show up validated, and marked failed once the validated
/// ledger passes their LastLedgerSequence and the node confirms it does not know them.
final class TransactionSyncer {
    static let pageLimit = 200
    static let maxPages = 25

    private let address: String
    private let rpcApiProvider: RpcApiProvider
    private let mainStorage: IMainStorage
    private let transactionStorage: ITransactionStorage

    @DistinctPublished private(set) var syncState: SyncState = .notSynced(error: SyncError.notStarted)

    private let transactionsSubject = PassthroughSubject<[Transaction], Never>()

    /// Emits every batch of new or updated transactions found by a sync.
    var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        transactionsSubject.eraseToAnyPublisher()
    }

    init(address: String, rpcApiProvider: RpcApiProvider, mainStorage: IMainStorage, transactionStorage: ITransactionStorage) {
        self.address = address
        self.rpcApiProvider = rpcApiProvider
        self.mainStorage = mainStorage
        self.transactionStorage = transactionStorage
    }

    func setNotStarted() {
        syncState = .notSynced(error: SyncError.notStarted)
    }

    func setNotSynced(error: Error) {
        syncState = .notSynced(error: error)
    }

    /// Publishes a record the sender wrote before submitting, so the list shows it at once.
    func publish(transactions: [Transaction]) {
        transactionsSubject.send(transactions)
    }

    func sync(validatedLedger: UInt32, accountExists: Bool) async throws {
        // initial sync shows Syncing; later incremental syncs keep the sticky Synced state
        let state = mainStorage.transactionSyncState()
        let initialSyncDone = state?.initialSyncDone ?? false
        if !initialSyncDone {
            syncState = .syncing(progress: nil)
        }

        do {
            var changed = [Transaction]()
            if accountExists {
                if let state, state.initialSyncDone {
                    if validatedLedger > state.lastSyncedLedger {
                        changed += try await incrementalSync(fromLedger: state.lastSyncedLedger == .max ? .max : state.lastSyncedLedger + 1, toLedger: validatedLedger)
                    }
                } else {
                    // the walk starts from the ledger it first saw; anything validated later is picked up by
                    // the incremental sync that follows in the same cycle
                    let startLedger = state?.lastSyncedLedger ?? validatedLedger
                    if state == nil {
                        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: startLedger, initialSyncDone: false))
                    }
                    changed += try await initialSync(startLedger: startLedger)
                    if validatedLedger > startLedger {
                        changed += try await incrementalSync(fromLedger: startLedger + 1, toLedger: validatedLedger)
                    }
                }
            }
            changed += try await expirePending(validatedLedger: validatedLedger)

            if !changed.isEmpty {
                transactionsSubject.send(changed)
            }
            syncState = .synced
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The account syncer owns the failure policy (it tolerates one transient blip after a
            // successful sync) and calls setNotSynced when the failure is real. Only a first sync
            // that never completed is reported here, so the list does not show stale "synced".
            if !initialSyncDone {
                syncState = .notSynced(error: error)
            }
            throw error
        }
    }

    private func initialSync(startLedger: UInt32) async throws -> [Transaction] {
        var stored = [Transaction]()
        // resume below the oldest validated transaction already stored; the boundary ledger is
        // fetched again and de-duplicated by hash
        var ledgerIndexMax = transactionStorage.oldestValidatedTransaction()?.ledgerIndex ?? startLedger
        var marker: Any?
        var pages = 0

        repeat {
            let page = try await rpcApiProvider.accountTx(address: address, ledgerIndexMin: -1, ledgerIndexMax: Int64(ledgerIndexMax), limit: Self.pageLimit, forward: false, marker: marker)
            let transactions = try page.transactions.map { try TransactionConverter.transaction(accountTx: $0) }
            try transactionStorage.save(transactions: transactions)
            stored += transactions
            marker = page.marker
            pages += 1
            if let oldest = transactions.compactMap(\.ledgerIndex).min() {
                ledgerIndexMax = oldest
            }
        } while marker != nil && pages < Self.maxPages

        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: startLedger, initialSyncDone: true))
        return stored
    }

    private func incrementalSync(fromLedger: UInt32, toLedger: UInt32) async throws -> [Transaction] {
        var stored = [Transaction]()
        var marker: Any?
        var pages = 0

        repeat {
            let page = try await rpcApiProvider.accountTx(address: address, ledgerIndexMin: Int64(fromLedger), ledgerIndexMax: Int64(toLedger), limit: Self.pageLimit, forward: true, marker: marker)
            let transactions = try page.transactions.map { try TransactionConverter.transaction(accountTx: $0) }
            try transactionStorage.save(transactions: transactions)
            stored += transactions
            marker = page.marker
            pages += 1
            if marker != nil, pages >= Self.maxPages {
                throw InvalidResponse("account_tx: more than \(Self.maxPages) pages")
            }
        } while marker != nil

        try mainStorage.save(transactionSyncState: TransactionSyncState(lastSyncedLedger: toLedger, initialSyncDone: true))
        return stored
    }

    /// A transaction that is still unvalidated once the validated ledger is past its
    /// LastLedgerSequence can never be included. It is marked failed only when the node explicitly
    /// does not know it (`txnNotFound`); a failed lookup postpones the decision to the next cycle.
    private func expirePending(validatedLedger: UInt32) async throws -> [Transaction] {
        var expired = [Transaction]()

        for pending in transactionStorage.pendingTransactions() {
            guard let last = pending.lastLedgerSequence, validatedLedger > last else {
                continue
            }

            let known: TxResult?
            do {
                known = try await rpcApiProvider.tx(hash: pending.hash)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }

            let updated: Transaction
            if let known {
                guard known.validated else {
                    continue
                }
                updated = try TransactionConverter.transaction(txResult: known)
            } else {
                updated = pending.expired()
            }
            try transactionStorage.save(transactions: [updated])
            expired.append(updated)
        }

        return expired
    }
}
