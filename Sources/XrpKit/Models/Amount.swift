import Foundation

/// An XRPL amount: XRP in drops, or an issued currency held on a trust line.
public enum Amount: Equatable {
    public static let dropsPerXrp: Decimal = 1_000_000

    case xrp(drops: UInt64)
    case issued(value: Decimal, currency: String, issuer: String)

    public var decimalValue: Decimal {
        switch self {
        case let .xrp(drops): return Decimal(drops) / Self.dropsPerXrp
        case let .issued(value, _, _): return value
        }
    }

    public var isXrp: Bool {
        if case .xrp = self {
            return true
        }
        return false
    }

    public var currency: String {
        switch self {
        case .xrp: return CurrencyCodec.xrp
        case let .issued(_, currency, _): return currency
        }
    }

    public var issuer: String? {
        switch self {
        case .xrp: return nil
        case let .issued(_, _, issuer): return issuer
        }
    }
}
