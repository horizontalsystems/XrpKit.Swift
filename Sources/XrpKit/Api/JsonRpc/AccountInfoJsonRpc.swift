import Foundation

/// `nil` when the account has never been funded (`actNotFound`); the provider maps that error.
class AccountInfoJsonRpc: JsonRpc<AccountInfo> {
    init(address: String) {
        super.init(method: "account_info", params: ["account": address, "ledger_index": "validated"])
    }

    /// Each owned object locks an owner reserve increment, so a real account cannot hold anywhere
    /// near this many. Bounded for the same reason as the reserve itself: the product feeds
    /// `minimumBalance`.
    static let maxOwnerCount: UInt32 = 1_000_000

    override func parse(result: RpcJson) throws -> AccountInfo {
        let data = try result.requireObject("account_data")
        let ownerCount = try data.requireUInt32("OwnerCount")

        guard ownerCount <= Self.maxOwnerCount else {
            throw InvalidResponse("account_info: OwnerCount out of range")
        }

        return AccountInfo(
            address: try data.requireString("Account"),
            balanceDrops: try data.requireDrops("Balance"),
            sequence: try data.requireUInt32("Sequence"),
            ownerCount: ownerCount,
            flags: try data.uint32("Flags") ?? 0
        )
    }
}

struct AccountLinesPage {
    let lines: [TrustLineInfo]
    let marker: Any?
}

class AccountLinesJsonRpc: JsonRpc<AccountLinesPage> {
    init(address: String, limit: Int, marker: Any?) {
        var params: RpcJson = ["account": address, "ledger_index": "validated", "limit": limit]
        if let marker {
            params["marker"] = marker
        }
        super.init(method: "account_lines", params: params)
    }

    override func parse(result: RpcJson) throws -> AccountLinesPage {
        let lines = try result.requireArray("lines").map { element -> TrustLineInfo in
            guard let line = element as? RpcJson else {
                throw InvalidResponse("account_lines: line is not an object")
            }
            return TrustLineInfo(
                currency: try line.requireString("currency"),
                issuer: try line.requireString("account"),
                balance: try line.requireString("balance"),
                limit: try line.requireString("limit"),
                limitPeer: line.string("limit_peer") ?? "0",
                noRipple: line.bool("no_ripple"),
                frozen: line.bool("freeze"),
                frozenByPeer: line.bool("freeze_peer"),
                authorized: line.bool("authorized")
            )
        }
        let marker = result["marker"].flatMap { $0 is NSNull ? nil : $0 }
        return AccountLinesPage(lines: lines, marker: marker)
    }
}
