import Foundation

/// One rippled JSON-RPC command: `{"method": ..., "params": [{...}]}`. The response carries
/// `result` with `status: success|error`; there is no JSON-RPC 2.0 envelope or id.
class JsonRpc<T> {
    let method: String
    let params: RpcJson

    init(method: String, params: RpcJson = [:]) {
        self.method = method
        self.params = params
    }

    var body: RpcJson {
        ["method": method, "params": [params]]
    }

    func parse(result _: RpcJson) throws -> T {
        fatalError("This method should be overridden")
    }
}

enum JsonRpcResponse {
    struct Parsed {
        let result: RpcJson
        /// `warning: "load"` — the node is rate limiting; prefer another one for subsequent calls.
        let loadWarning: Bool
    }

    static func parse(method: String, jsonObject: Any) throws -> Parsed {
        guard let dictionary = jsonObject as? RpcJson, let result = dictionary.object("result") else {
            throw InvalidResponse("\(method): missing result")
        }

        if result.string("status") == "error" {
            throw RpcError(code: result.string("error") ?? "unknown", message: result.string("error_message"))
        }

        return Parsed(result: result, loadWarning: result.string("warning") == "load")
    }
}
