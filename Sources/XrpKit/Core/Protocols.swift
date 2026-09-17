import Combine
import Foundation

protocol IConnectionManager {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }

    func start()
    func stop()
}

protocol IMainStorage {
    func accountState() -> AccountState?
    func save(accountState: AccountState) throws
    func ledgerState() -> LedgerState?
    func save(ledgerState: LedgerState) throws
    func trustLines() -> [TrustLine]
    func replace(trustLines: [TrustLine]) throws
    func transactionSyncState() -> TransactionSyncState?
    func save(transactionSyncState: TransactionSyncState) throws
}

protocol ITransactionStorage {
    func save(transactions: [Transaction]) throws
    func delete(hash: String) throws
    func transaction(hash: String) -> Transaction?
    func pendingTransactions() -> [Transaction]
    /// The validated transaction with the lowest ledger index: where an interrupted initial sync resumes.
    func oldestValidatedTransaction() -> Transaction?
    func allTransactions() -> [Transaction]
    func transactions(tagQuery: TagQuery, fromHash: String?, limit: Int?) -> [Transaction]
}

/// Readiness of the polling loop, separate from the public `SyncState`.
enum SyncerState: Equatable {
    case ready
    case notReady(error: Error)

    static func == (lhs: SyncerState, rhs: SyncerState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready): return true
        case let (.notReady(lhsError), .notReady(rhsError)): return "\(lhsError)" == "\(rhsError)"
        default: return false
        }
    }
}

protocol IApiSyncerDelegate: AnyObject {
    func didUpdateSyncerState(_ state: SyncerState)
    /// One timer tick: run a sync cycle.
    func sync()
}
