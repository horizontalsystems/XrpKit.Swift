import Foundation
import GRDB

/// The transaction table, keyed by hash with REPLACE, so a validated record from `account_tx`
/// takes the place of the pending or failed row the kit wrote for the same hash.
final class TransactionStorage {
    private let dbPool: DatabasePool
    private let address: String

    init(dbPool: DatabasePool, address: String) throws {
        self.dbPool = dbPool
        self.address = address
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createTransactions") { db in
            try db.create(table: Transaction.databaseTableName) { t in
                t.column(Transaction.Columns.hash.name, .text).notNull()
                t.column(Transaction.Columns.ledgerIndex.name, .integer)
                t.column(Transaction.Columns.timestamp.name, .integer).notNull()
                t.column(Transaction.Columns.type.name, .text).notNull()
                t.column(Transaction.Columns.account.name, .text).notNull()
                t.column(Transaction.Columns.destination.name, .text)
                t.column(Transaction.Columns.amountValue.name, .text)
                t.column(Transaction.Columns.amountCurrency.name, .text)
                t.column(Transaction.Columns.amountIssuer.name, .text)
                t.column(Transaction.Columns.deliveredValue.name, .text)
                t.column(Transaction.Columns.deliveredCurrency.name, .text)
                t.column(Transaction.Columns.deliveredIssuer.name, .text)
                t.column(Transaction.Columns.feeDrops.name, .integer).notNull()
                t.column(Transaction.Columns.sequence.name, .integer).notNull()
                t.column(Transaction.Columns.destinationTag.name, .integer)
                t.column(Transaction.Columns.sourceTag.name, .integer)
                t.column(Transaction.Columns.limitValue.name, .text)
                t.column(Transaction.Columns.limitCurrency.name, .text)
                t.column(Transaction.Columns.limitIssuer.name, .text)
                t.column(Transaction.Columns.result.name, .text)
                t.column(Transaction.Columns.validated.name, .boolean).notNull()
                t.column(Transaction.Columns.failed.name, .boolean).notNull()
                t.column(Transaction.Columns.lastLedgerSequence.name, .integer)
                t.column(Transaction.Columns.memo.name, .text)
                t.primaryKey([Transaction.Columns.hash.name], onConflict: .replace)
            }
            try db.create(index: "transactions_ledgerIndex", on: Transaction.databaseTableName, columns: [Transaction.Columns.ledgerIndex.name])
            try db.create(index: "transactions_timestamp", on: Transaction.databaseTableName, columns: [Transaction.Columns.timestamp.name])
        }

        return migrator
    }
}

extension TransactionStorage: ITransactionStorage {
    func save(transactions: [Transaction]) throws {
        try dbPool.write { db in
            for transaction in transactions {
                try transaction.save(db)
            }
        }
    }

    func delete(hash: String) throws {
        _ = try dbPool.write { db in
            try Transaction.filter(Transaction.Columns.hash == hash).deleteAll(db)
        }
    }

    func transaction(hash: String) -> Transaction? {
        try! dbPool.read { db in
            try Transaction.filter(Transaction.Columns.hash == hash).fetchOne(db)
        }
    }

    func pendingTransactions() -> [Transaction] {
        try! dbPool.read { db in
            try Transaction
                .filter(Transaction.Columns.validated == false && Transaction.Columns.failed == false)
                .order(Transaction.Columns.timestamp)
                .fetchAll(db)
        }
    }

    func oldestValidatedTransaction() -> Transaction? {
        try! dbPool.read { db in
            try Transaction
                .filter(Transaction.Columns.validated == true && Transaction.Columns.ledgerIndex != nil)
                .order(Transaction.Columns.ledgerIndex.asc)
                .fetchOne(db)
        }
    }

    func allTransactions() -> [Transaction] {
        transactions(tagQuery: TagQuery(), fromHash: nil, limit: nil)
    }

    func transactions(tagQuery: TagQuery, fromHash: String?, limit: Int?) -> [Transaction] {
        try! dbPool.read { db in
            var conditions = [String]()
            var arguments = [DatabaseValueConvertible]()

            switch tagQuery.direction {
            case .incoming:
                conditions.append("(\(Transaction.Columns.destination.name) = ? AND \(Transaction.Columns.account.name) != ?)")
                arguments.append(contentsOf: [address, address] as [DatabaseValueConvertible])
            case .outgoing:
                conditions.append("\(Transaction.Columns.account.name) = ?")
                arguments.append(address)
            case nil:
                break
            }

            switch tagQuery.token {
            case .native:
                conditions.append("(\(Transaction.Columns.type.name) != 'Payment' OR \(Transaction.Columns.amountCurrency.name) = ?)")
                arguments.append(CurrencyCodec.xrp)
            case let .issued(currency, issuer):
                conditions.append("((\(Transaction.Columns.amountCurrency.name) = ? AND \(Transaction.Columns.amountIssuer.name) = ?) OR (\(Transaction.Columns.limitCurrency.name) = ? AND \(Transaction.Columns.limitIssuer.name) = ?))")
                arguments.append(contentsOf: [currency, issuer, currency, issuer] as [DatabaseValueConvertible])
            case nil:
                break
            }

            if let counterparty = tagQuery.address {
                conditions.append("(\(Transaction.Columns.account.name) = ? OR \(Transaction.Columns.destination.name) = ?)")
                arguments.append(contentsOf: [counterparty, counterparty] as [DatabaseValueConvertible])
            }

            if let fromHash, let anchor = try Transaction.filter(Transaction.Columns.hash == fromHash).fetchOne(db) {
                conditions.append("(\(Transaction.Columns.timestamp.name) < ? OR (\(Transaction.Columns.timestamp.name) = ? AND \(Transaction.Columns.hash.name) < ?))")
                arguments.append(contentsOf: [anchor.timestamp, anchor.timestamp, anchor.hash] as [DatabaseValueConvertible])
            }

            var sql = "SELECT * FROM \(Transaction.databaseTableName)"
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " ORDER BY \(Transaction.Columns.timestamp.name) DESC, \(Transaction.Columns.hash.name) DESC"
            if let limit {
                sql += " LIMIT \(limit)"
            }

            let rows = try Row.fetchAll(db.makeStatement(sql: sql), arguments: StatementArguments(arguments))
            return try rows.map { try Transaction(row: $0) }
        }
    }
}
