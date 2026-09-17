import Foundation

struct ServerState: Equatable {
    let validatedLedger: UInt32
    let reserveBaseDrops: UInt64
    let reserveIncDrops: UInt64
}

struct FeeInfo: Equatable {
    let baseFeeDrops: UInt64
    let openLedgerFeeDrops: UInt64
    let minimumFeeDrops: UInt64
    let medianFeeDrops: UInt64
}

struct TrustLineInfo: Equatable {
    let currency: String
    let issuer: String
    let balance: String
    let limit: String
    let limitPeer: String
    let noRipple: Bool
    let frozen: Bool
    let frozenByPeer: Bool
    let authorized: Bool
}
