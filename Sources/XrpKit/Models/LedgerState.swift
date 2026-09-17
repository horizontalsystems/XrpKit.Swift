import Foundation
import GRDB

/// Validated ledger index and reserve parameters, refreshed every sync.
public class LedgerState: Record, Equatable {
    private static let primaryKeyValue = "primaryKey"
    private let primaryKey: String = LedgerState.primaryKeyValue

    public let validatedLedger: UInt32
    public let reserveBaseDrops: UInt64
    public let reserveIncDrops: UInt64

    init(validatedLedger: UInt32, reserveBaseDrops: UInt64, reserveIncDrops: UInt64) {
        self.validatedLedger = validatedLedger
        self.reserveBaseDrops = reserveBaseDrops
        self.reserveIncDrops = reserveIncDrops
        super.init()
    }

    public static func == (lhs: LedgerState, rhs: LedgerState) -> Bool {
        lhs.validatedLedger == rhs.validatedLedger && lhs.reserveBaseDrops == rhs.reserveBaseDrops && lhs.reserveIncDrops == rhs.reserveIncDrops
    }

    // MARK: - Record

    override public class var databaseTableName: String {
        "ledgerState"
    }

    enum Columns: String, ColumnExpression {
        case primaryKey, validatedLedger, reserveBaseDrops, reserveIncDrops
    }

    public required init(row: Row) throws {
        validatedLedger = row[Columns.validatedLedger]
        reserveBaseDrops = UInt64(bitPattern: row[Columns.reserveBaseDrops] as Int64)
        reserveIncDrops = UInt64(bitPattern: row[Columns.reserveIncDrops] as Int64)
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.primaryKey] = primaryKey
        container[Columns.validatedLedger] = validatedLedger
        container[Columns.reserveBaseDrops] = Int64(bitPattern: reserveBaseDrops)
        container[Columns.reserveIncDrops] = Int64(bitPattern: reserveIncDrops)
    }
}
