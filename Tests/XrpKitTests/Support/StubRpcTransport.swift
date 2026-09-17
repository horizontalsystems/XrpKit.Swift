import Foundation
@testable import XrpKit

/// Scripted transport: answers by rippled method, records every call. Answers are consumed in
/// order per method; the last one repeats. An answer may be a JSON object or an error to throw.
final class StubRpcTransport: IRpcTransport {
    enum Answer {
        case result(RpcJson)
        case error(Error)
        case rpcError(code: String, message: String? = nil)

        static func ok(_ result: RpcJson) -> Answer {
            .result(result)
        }
    }

    struct Call: Equatable {
        let url: URL
        let method: String
        let params: RpcJson

        static func == (lhs: Call, rhs: Call) -> Bool {
            lhs.url == rhs.url && lhs.method == rhs.method && NSDictionary(dictionary: lhs.params).isEqual(to: rhs.params)
        }
    }

    private let queue = DispatchQueue(label: "stub-rpc-transport")
    private var answers: [String: [Answer]] = [:]
    private var answersByUrl: [URL: [String: [Answer]]] = [:]
    private(set) var calls: [Call] = []

    func answer(_ method: String, _ answers: Answer...) {
        queue.sync { self.answers[method] = answers }
    }

    func answer(url: URL, _ method: String, _ answers: Answer...) {
        queue.sync { answersByUrl[url, default: [:]][method] = answers }
    }

    func calls(method: String) -> [Call] {
        queue.sync { calls.filter { $0.method == method } }
    }

    func post(url: URL, body: RpcJson) async throws -> Any {
        let method = body["method"] as? String ?? ""
        let params = (body["params"] as? [RpcJson])?.first ?? [:]

        let answer: Answer? = queue.sync {
            calls.append(Call(url: url, method: method, params: params))
            var pending = answersByUrl[url]?[method] ?? answers[method] ?? []
            let answer = pending.first
            if pending.count > 1 {
                pending.removeFirst()
                if answersByUrl[url]?[method] != nil {
                    answersByUrl[url]?[method] = pending
                } else {
                    answers[method] = pending
                }
            }
            return answer
        }

        switch answer {
        case let .result(result):
            return ["result": result.merging(["status": "success"]) { current, _ in current }]
        case let .error(error):
            throw error
        case let .rpcError(code, message):
            var result: RpcJson = ["status": "error", "error": code]
            if let message {
                result["error_message"] = message
            }
            return ["result": result]
        case nil:
            throw URLError(.badServerResponse)
        }
    }
}

enum Fixtures {
    static let address = "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"
    static let other = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
    static let issuer = "rGm7WCVp9gb4jZHWTEtGUr4dd74z2XuWhE"

    static func serverState(validated: UInt32 = 1000, reserveBase: UInt64 = 1_000_000, reserveInc: UInt64 = 200_000) -> RpcJson {
        ["state": ["server_state": "full", "validated_ledger": ["seq": validated, "reserve_base": reserveBase, "reserve_inc": reserveInc, "base_fee": 10]]]
    }

    static func accountInfo(balance: String = "25000000", sequence: UInt32 = 5, ownerCount: UInt32 = 0, flags: UInt32 = 0) -> RpcJson {
        ["account_data": ["Account": address, "Balance": balance, "Sequence": sequence, "OwnerCount": ownerCount, "Flags": flags], "validated": true]
    }

    static func payment(hash: String, ledgerIndex: UInt32, from: String = other, to: String = address, drops: String = "1000000", date: UInt64 = 800_000_000, result: String = "tesSUCCESS", flags: UInt32 = 0, memoHex: String? = nil, delivered: Any? = nil, lastLedgerSequence: UInt32? = nil) -> RpcJson {
        var tx: RpcJson = [
            "TransactionType": "Payment", "Account": from, "Destination": to, "Amount": drops, "Fee": "12", "Sequence": 7,
            "Flags": flags, "hash": hash, "ledger_index": ledgerIndex, "date": date,
        ]
        if let memoHex {
            tx["Memos"] = [["Memo": ["MemoData": memoHex]]]
        }
        if let lastLedgerSequence {
            tx["LastLedgerSequence"] = lastLedgerSequence
        }
        var meta: RpcJson = ["TransactionResult": result]
        if let delivered {
            meta["delivered_amount"] = delivered
        }
        return ["tx": tx, "meta": meta, "validated": true]
    }

    static func accountTxPage(_ transactions: [RpcJson], marker: Any? = nil) -> RpcJson {
        var page: RpcJson = ["account": address, "transactions": transactions, "ledger_index_min": 1, "ledger_index_max": 1000]
        if let marker {
            page["marker"] = marker
        }
        return page
    }
}
