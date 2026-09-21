import Foundation

class ServerStateJsonRpc: JsonRpc<ServerState> {
    init() {
        super.init(method: "server_state")
    }

    /// Validators vote the reserve in units of XRP; it has never left single digits. A million XRP
    /// is six orders of magnitude of headroom, and the bound is what keeps `minimumBalance` from
    /// overflowing on a hostile or broken node — a value that lands in the database and would then
    /// crash on every launch.
    static let maxReserveDrops: UInt64 = 1_000_000_000_000

    override func parse(result: RpcJson) throws -> ServerState {
        let state = try result.requireObject("state")
        let ledger = try state.requireObject("validated_ledger")
        let reserveBase = try ledger.requireUInt64("reserve_base")
        let reserveInc = try ledger.requireUInt64("reserve_inc")

        guard reserveBase <= Self.maxReserveDrops, reserveInc <= Self.maxReserveDrops else {
            throw InvalidResponse("server_state: reserve out of range")
        }

        return ServerState(
            validatedLedger: try ledger.requireUInt32("seq"),
            reserveBaseDrops: reserveBase,
            reserveIncDrops: reserveInc
        )
    }
}

class FeeJsonRpc: JsonRpc<FeeInfo> {
    init() {
        super.init(method: "fee")
    }

    override func parse(result: RpcJson) throws -> FeeInfo {
        let drops = try result.requireObject("drops")
        return FeeInfo(
            baseFeeDrops: try drops.requireDrops("base_fee"),
            openLedgerFeeDrops: try drops.requireDrops("open_ledger_fee"),
            minimumFeeDrops: try drops.requireDrops("minimum_fee"),
            medianFeeDrops: try drops.requireDrops("median_fee")
        )
    }
}
