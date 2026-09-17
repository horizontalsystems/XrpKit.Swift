import Foundation

class ServerStateJsonRpc: JsonRpc<ServerState> {
    init() {
        super.init(method: "server_state")
    }

    override func parse(result: RpcJson) throws -> ServerState {
        let state = try result.requireObject("state")
        let ledger = try state.requireObject("validated_ledger")
        return ServerState(
            validatedLedger: try ledger.requireUInt32("seq"),
            reserveBaseDrops: try ledger.requireUInt64("reserve_base"),
            reserveIncDrops: try ledger.requireUInt64("reserve_inc")
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
