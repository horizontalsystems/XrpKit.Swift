import Foundation

class AccountTxJsonRpc: JsonRpc<AccountTxPage> {
    init(address: String, ledgerIndexMin: Int64, ledgerIndexMax: Int64, limit: Int, forward: Bool, marker: Any?) {
        var params: RpcJson = [
            "account": address,
            "ledger_index_min": ledgerIndexMin,
            "ledger_index_max": ledgerIndexMax,
            "limit": limit,
            "forward": forward,
        ]
        if let marker {
            params["marker"] = marker
        }
        super.init(method: "account_tx", params: params)
    }

    override func parse(result: RpcJson) throws -> AccountTxPage {
        let transactions = try result.requireArray("transactions").compactMap { element -> RawTransaction? in
            guard let item = element as? RpcJson else {
                return nil
            }
            // API v1 nests the transaction under "tx"; v2 servers answering v1 keep the same shape
            guard let tx = item.object("tx") ?? item.object("tx_json"), let meta = item.object("meta") else {
                return nil
            }
            guard let hash = tx.string("hash") ?? item.string("hash") else {
                return nil
            }
            guard let ledgerIndex = try tx.uint32("ledger_index") ?? item.uint32("ledger_index") else {
                return nil
            }
            return RawTransaction(
                hash: hash,
                tx: tx,
                meta: meta,
                validated: item.bool("validated"),
                ledgerIndex: ledgerIndex,
                date: try tx.uint64("date")
            )
        }
        let marker = result["marker"].flatMap { $0 is NSNull ? nil : $0 }
        return AccountTxPage(transactions: transactions, marker: marker)
    }
}

/// `nil` when the node does not know the transaction (`txnNotFound`); the provider maps that error.
class TxJsonRpc: JsonRpc<TxResult> {
    private let hash: String

    init(hash: String) {
        self.hash = hash
        super.init(method: "tx", params: ["transaction": hash])
    }

    override func parse(result: RpcJson) throws -> TxResult {
        TxResult(
            hash: result.string("hash") ?? hash,
            validated: result.bool("validated"),
            ledgerIndex: try result.uint32("ledger_index"),
            tx: result,
            meta: result.object("meta"),
            date: try result.uint64("date")
        )
    }
}

class SubmitJsonRpc: JsonRpc<SubmitResult> {
    init(blobHex: String) {
        super.init(method: "submit", params: ["tx_blob": blobHex, "fail_hard": false])
    }

    override func parse(result: RpcJson) throws -> SubmitResult {
        SubmitResult(
            engineResult: try result.requireString("engine_result"),
            engineResultCode: (result["engine_result_code"] as? NSNumber)?.intValue ?? 0,
            engineResultMessage: result.string("engine_result_message"),
            hash: result.object("tx_json")?.string("hash"),
            accepted: result.bool("accepted"),
            applied: result.bool("applied"),
            queued: result.bool("queued")
        )
    }
}
