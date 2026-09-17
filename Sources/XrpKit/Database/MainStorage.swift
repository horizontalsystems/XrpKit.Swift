import Foundation
import GRDB

/// Single-row tables for the account, the ledger parameters and the transaction sync cursor,
/// plus the trust lines (SolanaKit `MainStorage` form).
final class MainStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createMainTables") { db in
            try db.create(table: AccountState.databaseTableName) { t in
                t.column(AccountState.Columns.primaryKey.name, .text).notNull()
                t.column(AccountState.Columns.exists.name, .boolean).notNull()
                t.column(AccountState.Columns.balanceDrops.name, .integer).notNull()
                t.column(AccountState.Columns.sequence.name, .integer).notNull()
                t.column(AccountState.Columns.ownerCount.name, .integer).notNull()
                t.column(AccountState.Columns.flags.name, .integer).notNull()
                t.primaryKey([AccountState.Columns.primaryKey.name], onConflict: .replace)
            }

            try db.create(table: LedgerState.databaseTableName) { t in
                t.column(LedgerState.Columns.primaryKey.name, .text).notNull()
                t.column(LedgerState.Columns.validatedLedger.name, .integer).notNull()
                t.column(LedgerState.Columns.reserveBaseDrops.name, .integer).notNull()
                t.column(LedgerState.Columns.reserveIncDrops.name, .integer).notNull()
                t.primaryKey([LedgerState.Columns.primaryKey.name], onConflict: .replace)
            }

            try db.create(table: TrustLine.databaseTableName) { t in
                t.column(TrustLine.Columns.currency.name, .text).notNull()
                t.column(TrustLine.Columns.issuer.name, .text).notNull()
                t.column(TrustLine.Columns.balance.name, .text).notNull()
                t.column(TrustLine.Columns.limit.name, .text).notNull()
                t.column(TrustLine.Columns.noRipple.name, .boolean).notNull()
                t.column(TrustLine.Columns.frozen.name, .boolean).notNull()
                t.column(TrustLine.Columns.frozenByHolder.name, .boolean).notNull()
                t.column(TrustLine.Columns.authorized.name, .boolean).notNull()
                t.primaryKey([TrustLine.Columns.currency.name, TrustLine.Columns.issuer.name], onConflict: .replace)
            }

            try db.create(table: TransactionSyncState.databaseTableName) { t in
                t.column(TransactionSyncState.Columns.primaryKey.name, .text).notNull()
                t.column(TransactionSyncState.Columns.lastSyncedLedger.name, .integer).notNull()
                t.column(TransactionSyncState.Columns.initialSyncDone.name, .boolean).notNull()
                t.primaryKey([TransactionSyncState.Columns.primaryKey.name], onConflict: .replace)
            }
        }

        return migrator
    }
}

extension MainStorage: IMainStorage {
    func accountState() -> AccountState? {
        try! dbPool.read { db in
            try AccountState.fetchOne(db)
        }
    }

    func save(accountState: AccountState) throws {
        try dbPool.write { db in
            try accountState.save(db)
        }
    }

    func ledgerState() -> LedgerState? {
        try! dbPool.read { db in
            try LedgerState.fetchOne(db)
        }
    }

    func save(ledgerState: LedgerState) throws {
        try dbPool.write { db in
            try ledgerState.save(db)
        }
    }

    func trustLines() -> [TrustLine] {
        try! dbPool.read { db in
            try TrustLine.order(TrustLine.Columns.currency, TrustLine.Columns.issuer).fetchAll(db)
        }
    }

    func replace(trustLines: [TrustLine]) throws {
        try dbPool.write { db in
            try TrustLine.deleteAll(db)
            for line in trustLines {
                try line.save(db)
            }
        }
    }

    func transactionSyncState() -> TransactionSyncState? {
        try! dbPool.read { db in
            try TransactionSyncState.fetchOne(db)
        }
    }

    func save(transactionSyncState: TransactionSyncState) throws {
        try dbPool.write { db in
            try transactionSyncState.save(db)
        }
    }
}
