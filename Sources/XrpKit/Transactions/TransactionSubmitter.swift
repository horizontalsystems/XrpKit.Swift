import Foundation
import HsToolKit

/// Submission with node fallback: the same signed payload is offered to the endpoints in turn,
/// starting from the provider's preferred one and wrapping around the list, until a node accepts it
/// or gives a deterministic rejection. When every attempt is unreachable or ambiguous the outcome is
/// `unknown`, never a rejection — the caller keeps its pending record and lets the ledger decide.
///
/// The number of attempts is bounded, and deliberately small. An endpoint that has gone dark costs a
/// full request timeout, while the payload itself is only valid until its `LastLedgerSequence`, about
/// a minute after signing; attempts beyond that window would offer the network a transaction it can
/// no longer include, and leave the user waiting for them. A single-endpoint list is tried once.
final class TransactionSubmitter {
    /// One fallback after the chosen node, as the app configures it.
    static let defaultMaxAttempts = 2
    enum Outcome<T> {
        case accepted(T)
        case rejected(engineResult: String, message: String?)
        case unknown(lastError: Error?)
    }

    private let rpcApiProvider: RpcApiProvider
    private let maxAttempts: Int
    private let logger: Logger?

    init(rpcApiProvider: RpcApiProvider, maxAttempts: Int = TransactionSubmitter.defaultMaxAttempts, logger: Logger? = nil) {
        self.rpcApiProvider = rpcApiProvider
        self.maxAttempts = maxAttempts
        self.logger = logger
    }

    func submit<T>(rpc: JsonRpc<T>, classifier: some ISubmitResultClassifier, verdict: (T) -> SubmitVerdict) async -> Outcome<T> {
        let urls = rpcApiProvider.urls
        let start = rpcApiProvider.preferredIndex
        var lastError: Error?

        // never more attempts than there are endpoints: re-offering the payload to a node that has
        // just refused it adds a timeout, not a chance
        for attempt in 0 ..< min(maxAttempts, urls.count) {
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
