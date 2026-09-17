import Foundation
import GRDB

public class TrustLine: Record, Equatable {
    public let currency: String
    public let issuer: String
    public let balance: Decimal
    public let limit: Decimal
    public let noRipple: Bool
    /// Frozen by the issuer: the balance cannot be sent.
    public let frozen: Bool
    /// Frozen by this account (rare for an end-user wallet).
    public let frozenByHolder: Bool
    public let authorized: Bool

    init(currency: String, issuer: String, balance: Decimal, limit: Decimal, noRipple: Bool, frozen: Bool, frozenByHolder: Bool, authorized: Bool) {
        self.currency = currency
        self.issuer = issuer
        self.balance = balance
        self.limit = limit
        self.noRipple = noRipple
        self.frozen = frozen
        self.frozenByHolder = frozenByHolder
        self.authorized = authorized
        super.init()
    }

    public var amount: Amount {
        .issued(value: balance, currency: currency, issuer: issuer)
    }

    public static func == (lhs: TrustLine, rhs: TrustLine) -> Bool {
        lhs.currency == rhs.currency && lhs.issuer == rhs.issuer && lhs.balance == rhs.balance && lhs.limit == rhs.limit
            && lhs.noRipple == rhs.noRipple && lhs.frozen == rhs.frozen && lhs.frozenByHolder == rhs.frozenByHolder && lhs.authorized == rhs.authorized
    }

    // MARK: - Record

    override public class var databaseTableName: String {
        "trustLines"
    }

    enum Columns: String, ColumnExpression {
        case currency, issuer, balance, limit, noRipple, frozen, frozenByHolder, authorized
    }

    public required init(row: Row) throws {
        currency = row[Columns.currency]
        issuer = row[Columns.issuer]
        balance = Decimal(string: row[Columns.balance], locale: Locale(identifier: "en_US_POSIX")) ?? 0
        limit = Decimal(string: row[Columns.limit], locale: Locale(identifier: "en_US_POSIX")) ?? 0
        noRipple = row[Columns.noRipple]
        frozen = row[Columns.frozen]
        frozenByHolder = row[Columns.frozenByHolder]
        authorized = row[Columns.authorized]
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.currency] = currency
        container[Columns.issuer] = issuer
        container[Columns.balance] = balance.xrplString
        container[Columns.limit] = limit.xrplString
        container[Columns.noRipple] = noRipple
        container[Columns.frozen] = frozen
        container[Columns.frozenByHolder] = frozenByHolder
        container[Columns.authorized] = authorized
    }
}
