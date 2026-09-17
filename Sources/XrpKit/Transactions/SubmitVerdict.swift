import Alamofire
import Foundation

/// How one node's answer to a submission is classified. The same signed blob is idempotent on the
/// ledger, so trying the next node is safe; what must never happen is treating "unknown" as "rejected".
enum SubmitVerdict {
    /// The node accepted the transaction (or already had it): stop, keep the pending record.
    case accepted
    /// Deterministic rejection every node would repeat: stop, drop the pending record.
    case rejected(engineResult: String, message: String?)
    /// The node itself could not take it right now (busy, no network, fee below its threshold): try the next node.
    case nodeLocal(Error)
    /// The blob may or may not have been relayed (transport failure, `tefPAST_SEQ`): remember, try the next node.
    case unknown(Error?)
}

/// Chain-specific mapping from a submit response, or the error it failed with, to a verdict.
protocol ISubmitResultClassifier {
    func verdict(result: SubmitResult) -> SubmitVerdict
    func verdict(error: Error) -> SubmitVerdict
}

struct XrpSubmitResultClassifier: ISubmitResultClassifier {
    /// rippled engine results that mean "already here" rather than "rejected".
    private static let acceptedResults: Set<String> = ["terQUEUED", "tefALREADY"]
    /// The sequence was consumed: by this very transaction on another node, or by another one. Not decidable here.
    private static let ambiguousResults: Set<String> = ["tefPAST_SEQ"]
    /// Node-local error tokens rippled returns with `status: error` for a submit it could not process.
    private static let nodeLocalErrors: Set<String> = ["tooBusy", "noNetwork", "noCurrent", "noClosed", "highFee", "amendmentBlocked"]

    func verdict(result: SubmitResult) -> SubmitVerdict {
        let code = result.engineResult
        if result.isSuccess || result.isQueued || Self.acceptedResults.contains(code) {
            return .accepted
        }
        if Self.ambiguousResults.contains(code) {
            return .unknown(RpcError(code: code, message: result.engineResultMessage))
        }
        if code.hasPrefix("tel") {
            return .nodeLocal(RpcError(code: code, message: result.engineResultMessage))
        }
        // tem*, tef*, tec*, ter* other than queued: the ledger rules said no
        return .rejected(engineResult: code, message: result.engineResultMessage)
    }

    func verdict(error: Error) -> SubmitVerdict {
        if let rpcError = error as? RpcError {
            return Self.nodeLocalErrors.contains(rpcError.code) ? .nodeLocal(rpcError) : .rejected(engineResult: rpcError.code, message: rpcError.message)
        }
        if error is InvalidResponse {
            return .unknown(error)
        }
        if let urlError = error as? URLError ?? error.asAFError?.underlyingError as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet, .secureConnectionFailed, .serverCertificateUntrusted:
                // nothing left the device
                return .nodeLocal(error)
            default:
                // timed out, connection lost mid-flight: the request may have been delivered
                return .unknown(error)
            }
        }
        if let afError = error.asAFError, case .responseValidationFailed = afError {
            // an HTTP error status: the node answered, it did not relay a blob it refused to read
            return .nodeLocal(error)
        }
        return .unknown(error)
    }
}
