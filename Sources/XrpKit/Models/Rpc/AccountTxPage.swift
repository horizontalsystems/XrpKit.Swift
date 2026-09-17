import Foundation

/// One entry of an `account_tx` page (API v1 shape).
struct RawTransaction {
    let hash: String
    let tx: RpcJson
    let meta: RpcJson
    let validated: Bool
    let ledgerIndex: UInt32
    /// Ledger close time in seconds since the Ripple epoch (2000-01-01).
    let date: UInt64?
}

struct AccountTxPage {
    let transactions: [RawTransaction]
    let marker: Any?
}

struct SubmitResult: Equatable {
    let engineResult: String
    let engineResultCode: Int
    let engineResultMessage: String?
    let hash: String?
    let accepted: Bool
    let applied: Bool
    let queued: Bool

    var isSuccess: Bool {
        engineResult.hasPrefix("tes")
    }

    var isQueued: Bool {
        engineResult == "terQUEUED" || queued
    }
}

struct TxResult {
    let hash: String
    let validated: Bool
    let ledgerIndex: UInt32?
    let tx: RpcJson
    let meta: RpcJson?
    let date: UInt64?
}
