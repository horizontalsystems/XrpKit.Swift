import Foundation
import HsToolKit

/// Submission with node fallback: the same signed payload is offered to the endpoints in turn,
/// starting from the provider's preferred one, until a node accepts it or gives a deterministic
/// rejection. When every node is unreachable or ambiguous the outcome is `unknown`, never a
/// rejection — the caller keeps its pending record and lets the ledger decide.
///
/// Generic over the request and classifier so a second kit can reuse it.
final class TransactionSubmitter {
    enum Outcome<T> {
        case accepted(T)
        case rejected(engineResult: String, message: String?)
        case unknown(lastError: Error?)
    }

    private let rpcApiProvider: RpcApiProvider
    private let logger: Logger?

    init(rpcApiProvider: RpcApiProvider, logger: Logger? = nil) {
        self.rpcApiProvider = rpcApiProvider
        self.logger = logger
    }

    func submit<T>(rpc: JsonRpc<T>, classifier: some ISubmitResultClassifier, verdict: (T) -> SubmitVerdict) async -> Outcome<T> {
        let urls = rpcApiProvider.urls
        let start = rpcApiProvider.preferredIndex
        var lastError: Error?

        for attempt in urls.indices {
            let url = urls[(start + attempt) % urls.count]
            let nodeVerdict: SubmitVerdict
            let result: T?

            do {
                let response = try await rpcApiProvider.fetch(rpc: rpc, url: url)
                result = response
                nodeVerdict = verdict(response)
            } catch is CancellationError {
                return .unknown(lastError: CancellationError())
            } catch {
                result = nil
                nodeVerdict = classifier.verdict(error: error)
            }

            switch nodeVerdict {
            case .accepted:
                if let result {
                    return .accepted(result)
                }
            case let .rejected(engineResult, message):
                return .rejected(engineResult: engineResult, message: message)
            case let .nodeLocal(error):
                logger?.error("\(rpc.method) refused by \(url.host ?? "?"): \(error)")
                lastError = error
            case let .unknown(error):
                logger?.error("\(rpc.method) outcome unknown on \(url.host ?? "?"): \(String(describing: error))")
                lastError = error ?? lastError
            }
        }

        return .unknown(lastError: lastError)
    }
}
