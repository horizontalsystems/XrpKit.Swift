import Foundation

/// Filter for the locally stored history, the same semantics as the Android `XrpTransactionsAdapter` filter.
public struct TagQuery {
    public enum Direction {
        case incoming
        case outgoing
    }

    public enum Token: Equatable {
        /// XRP: every non-Payment transaction plus Payments whose amount is XRP.
        case native
        /// An issued currency: Payments of it and TrustSet changes of its trust line.
        case issued(currency: String, issuer: String)
    }

    public let direction: Direction?
    public let token: Token?
    /// Counterparty: transactions where `account` or `destination` equals it.
    public let address: String?

    public init(direction: Direction? = nil, token: Token? = nil, address: String? = nil) {
        self.direction = direction
        self.token = token
        self.address = address
    }

    var isEmpty: Bool {
        direction == nil && token == nil && address == nil
    }

    /// In-memory form of the storage filter, for publishers of changed batches.
    public func matches(_ transaction: Transaction, ownAddress: String) -> Bool {
        switch direction {
        case .incoming:
            guard transaction.isIncoming(ownAddress: ownAddress) else { return false }
        case .outgoing:
            guard transaction.isOutgoing(ownAddress: ownAddress) else { return false }
        case nil:
            break
        }

        switch token {
        case .native:
            guard transaction.type != "Payment" || transaction.amount?.isXrp == true else { return false }
        case let .issued(currency, issuer):
            let amountMatches = transaction.amount.map { $0.currency == currency && $0.issuer == issuer } ?? false
            let limitMatches = transaction.limitAmount.map { $0.currency == currency && $0.issuer == issuer } ?? false
            guard amountMatches || limitMatches else { return false }
        case nil:
            break
        }

        if let address {
            guard transaction.account == address || transaction.destination == address else { return false }
        }

        return true
    }
}
