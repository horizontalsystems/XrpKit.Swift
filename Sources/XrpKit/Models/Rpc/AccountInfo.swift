import Foundation

public struct AccountInfo: Equatable {
    public let address: String
    public let balanceDrops: UInt64
    public let sequence: UInt32
    public let ownerCount: UInt32
    public let flags: UInt32

    /// lsfRequireDestTag: payments to this account must carry a destination tag.
    public var requiresDestinationTag: Bool {
        flags & AccountState.lsfRequireDestTag != 0
    }

    /// lsfDisallowXRP: the account advises against receiving XRP (not enforced on-ledger).
    public var disallowXrp: Bool {
        flags & AccountState.lsfDisallowXrp != 0
    }

    /// lsfDepositAuth: only pre-authorized accounts may send payments to this one.
    public var depositAuth: Bool {
        flags & AccountState.lsfDepositAuth != 0
    }
}
