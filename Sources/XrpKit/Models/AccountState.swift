import Foundation
import GRDB

/// On-ledger state of the kit's account. A single row; `exists` is false until the account is funded.
public class AccountState: Record, Equatable {
    private static let primaryKeyValue = "primaryKey"
    private let primaryKey: String = AccountState.primaryKeyValue

    public static let lsfRequireDestTag: UInt32 = 0x0002_0000
    public static let lsfDisallowXrp: UInt32 = 0x0008_0000
    public static let lsfDepositAuth: UInt32 = 0x0100_0000

    public let exists: Bool
    public let balanceDrops: UInt64
    public let sequence: UInt32
    public let ownerCount: UInt32
    public let flags: UInt32

    public static let empty = AccountState(exists: false, balanceDrops: 0, sequence: 0, ownerCount: 0, flags: 0)

    init(exists: Bool, balanceDrops: UInt64, sequence: UInt32, ownerCount: UInt32, flags: UInt32) {
        self.exists = exists
        self.balanceDrops = balanceDrops
        self.sequence = sequence
        self.ownerCount = ownerCount
        self.flags = flags
        super.init()
    }

    public var balance: Amount {
        .xrp(drops: balanceDrops)
    }

    /// lsfRequireDestTag: payments to this account must carry a destination tag.
    public var requiresDestinationTag: Bool {
        flags & Self.lsfRequireDestTag != 0
    }

    public static func == (lhs: AccountState, rhs: AccountState) -> Bool {
        lhs.exists == rhs.exists && lhs.balanceDrops == rhs.balanceDrops && lhs.sequence == rhs.sequence && lhs.ownerCount == rhs.ownerCount && lhs.flags == rhs.flags
    }

    // MARK: - Record

    override public class var databaseTableName: String {
        "accountState"
    }

    enum Columns: String, ColumnExpression {
        case primaryKey, exists, balanceDrops, sequence, ownerCount, flags
    }

    public required init(row: Row) throws {
        exists = row[Columns.exists]
        balanceDrops = UInt64(bitPattern: row[Columns.balanceDrops] as Int64)
        sequence = row[Columns.sequence]
        ownerCount = row[Columns.ownerCount]
        flags = row[Columns.flags]
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.primaryKey] = primaryKey
        container[Columns.exists] = exists
        container[Columns.balanceDrops] = Int64(bitPattern: balanceDrops)
        container[Columns.sequence] = sequence
        container[Columns.ownerCount] = ownerCount
        container[Columns.flags] = flags
    }
}
