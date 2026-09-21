import Combine
import Foundation

/// Reachability as the other kits see it: HsToolKit `ReachabilityManager` in production (EvmKit
/// `ApiRpcSyncer`, TronKit `SyncTimer`), a stub in tests. The value is known synchronously at
/// creation, so the first `start()` decides on the real status, not a placeholder.
protocol IConnectionManager {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }
}

/// Reads throw like writes do: a failed read means the database itself is broken, and answering
/// "no state" would show a funded wallet as empty and send the sync back to the beginning.
protocol IMainStorage {
    func accountState() throws -> AccountState?
    func save(accountState: AccountState) throws
    func ledgerState() throws -> LedgerState?
    func save(ledgerState: LedgerState) throws
    func trustLines() throws -> [TrustLine]
    func replace(trustLines: [TrustLine]) throws
    func transactionSyncState() throws -> TransactionSyncState?
    func save(transactionSyncState: TransactionSyncState) throws
}

protocol ITransactionStorage {
    func save(transactions: [Transaction]) throws
    func delete(hash: String) throws
    func transaction(hash: String) throws -> Transaction?
    func pendingTransactions() throws -> [Transaction]
    /// The validated transaction with the lowest ledger index: where an interrupted initial sync resumes.
    func oldestValidatedTransaction() throws -> Transaction?
    func allTransactions() throws -> [Transaction]
    func transactions(tagQuery: TagQuery, fromHash: String?, limit: Int?) throws -> [Transaction]
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
