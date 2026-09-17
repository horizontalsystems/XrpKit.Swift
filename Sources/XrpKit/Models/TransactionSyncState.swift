import Foundation
import GRDB

class TransactionSyncState: Record {
    private static let primaryKeyValue = "primaryKey"
    private let primaryKey: String = TransactionSyncState.primaryKeyValue

    /// Highest validated ledger whose transactions are stored. During the initial backwards walk
    /// this is the ledger the walk started from, so the first incremental sync fills the gap.
    let lastSyncedLedger: UInt32
    /// False while the initial backwards walk of history has not reached the account's first tx.
    let initialSyncDone: Bool

    init(lastSyncedLedger: UInt32, initialSyncDone: Bool) {
        self.lastSyncedLedger = lastSyncedLedger
        self.initialSyncDone = initialSyncDone
        super.init()
    }

    // MARK: - Record

    override class var databaseTableName: String {
        "transactionSyncState"
    }

    enum Columns: String, ColumnExpression {
        case primaryKey, lastSyncedLedger, initialSyncDone
    }

    required init(row: Row) throws {
        lastSyncedLedger = row[Columns.lastSyncedLedger]
        initialSyncDone = row[Columns.initialSyncDone]
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.primaryKey] = primaryKey
        container[Columns.lastSyncedLedger] = lastSyncedLedger
        container[Columns.initialSyncDone] = initialSyncDone
    }
}
