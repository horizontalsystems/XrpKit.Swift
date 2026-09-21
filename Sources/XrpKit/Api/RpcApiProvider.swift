import Alamofire
import Foundation
import HsToolKit

/// One HTTP POST of a rippled command body to one endpoint. Abstracted so the provider's
/// failover policy is testable without the network (StellarKit `IApi` idiom).
protocol IRpcTransport {
    func post(url: URL, body: RpcJson) async throws -> Any
}

final class NetworkManagerRpcTransport: IRpcTransport {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func post(url: URL, body: RpcJson) async throws -> Any {
        try await networkManager.fetchJson(url: url, method: .post, parameters: body, encoding: JSONEncoding.default, responseCacherBehavior: .doNotCache)
    }
}

/// rippled JSON-RPC client with endpoint failover, the Android `RpcProvider` policy: transport and
/// HTTP failures move to the next URL; a rippled error about the request itself (e.g. `actNotFound`)
/// is thrown as `RpcError` without failover, because every node would answer the same, while one
/// about the node's own condition (`tooBusy`, `notSynced`) moves on like a transport failure;
/// a `warning: "load"` moves `preferredIndex` to the next node for subsequent calls.
final class RpcApiProvider {
    private static let passes = 2
    private static let dnsRetryDelay: TimeInterval = 1.5

    let urls: [URL]
    private let transport: IRpcTransport
    private let logger: Logger?

    private let lock = NSLock()
    private var _preferredIndex = 0

    init(urls: [URL], transport: IRpcTransport, logger: Logger? = nil) {
        precondition(!urls.isEmpty, "At least one RPC URL is required")
        self.urls = urls
        self.transport = transport
        self.logger = logger
    }

    convenience init(urls: [URL], networkManager: NetworkManager, logger: Logger? = nil) {
        self.init(urls: urls, transport: NetworkManagerRpcTransport(networkManager: networkManager), logger: logger)
    }

    var preferredIndex: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _preferredIndex
        }
        set {
            lock.lock()
            _preferredIndex = newValue
            lock.unlock()
        }
    }

    var source: String {
        urls.first?.host ?? "unknown"
    }

    func fetch<T>(rpc: JsonRpc<T>) async throws -> T {
        var lastError: Error?

        for pass in 0 ..< Self.passes {
            if pass > 0 {
                // Every host failed to resolve: the device's network is not up yet (typical right
                // after the app resumes). Give it a moment instead of failing the whole sync.
                guard let lastError, NetworkErrors.isDnsFailure(lastError) else {
                    break
                }
                try await Task.sleep(nanoseconds: UInt64(Self.dnsRetryDelay * 1_000_000_000))
            }

            let start = preferredIndex
            for attempt in urls.indices {
                let index = (start + attempt) % urls.count
                do {
                    return try await fetch(rpc: rpc, index: index)
                } catch let error as RpcError where error.isDeterministic {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger?.error("\(rpc.method) failed on \(urls[index].host ?? "?"): \(error)")
                    lastError = error
                }
            }
        }

        throw NoEndpointAvailable(underlying: lastError)
    }

    /// One call to one endpoint, no failover. `TransactionSubmitter` drives its own loop with this.
    func fetch<T>(rpc: JsonRpc<T>, url: URL) async throws -> T {
        guard let index = urls.firstIndex(of: url) else {
            throw NoEndpointAvailable(underlying: nil)
        }
        return try await fetch(rpc: rpc, index: index)
    }

    private func fetch<T>(rpc: JsonRpc<T>, index: Int) async throws -> T {
        let json = try await transport.post(url: urls[index], body: rpc.body)
        let parsed = try JsonRpcResponse.parse(method: rpc.method, jsonObject: json)
        preferredIndex = parsed.loadWarning ? (index + 1) % urls.count : index
        return try rpc.parse(result: parsed.result)
    }
}

// MARK: - rippled commands

extension RpcApiProvider {
    static let accountLinesLimit = 400
    /// Every marker loop is bounded; a node that never stops paging is treated as a bad response.
    static let maxPages = 25

    /// `nil` when the account has never been funded (`actNotFound`).
    func accountInfo(address: String) async throws -> AccountInfo? {
        do {
            return try await fetch(rpc: AccountInfoJsonRpc(address: address))
        } catch let error as RpcError where error.code == "actNotFound" {
            return nil
        }
    }

    func accountLines(address: String) async throws -> [TrustLineInfo] {
        var lines = [TrustLineInfo]()
        var marker: Any?
        var pages = 0

        repeat {
            let page: AccountLinesPage
            do {
                page = try await fetch(rpc: AccountLinesJsonRpc(address: address, limit: Self.accountLinesLimit, marker: marker))
            } catch let error as RpcError where error.code == "actNotFound" {
                return []
            }
            lines.append(contentsOf: page.lines)
            marker = page.marker
            pages += 1
            if marker != nil, pages >= Self.maxPages {
                throw InvalidResponse("account_lines: more than \(Self.maxPages) pages")
            }
        } while marker != nil

        return lines
    }

    func serverState() async throws -> ServerState {
        try await fetch(rpc: ServerStateJsonRpc())
    }

    func fee() async throws -> FeeInfo {
        try await fetch(rpc: FeeJsonRpc())
    }

    func accountTx(address: String, ledgerIndexMin: Int64 = -1, ledgerIndexMax: Int64 = -1, limit: Int = 200, forward: Bool = false, marker: Any? = nil) async throws -> AccountTxPage {
        do {
            return try await fetch(rpc: AccountTxJsonRpc(address: address, ledgerIndexMin: ledgerIndexMin, ledgerIndexMax: ledgerIndexMax, limit: limit, forward: forward, marker: marker))
        } catch let error as RpcError where error.code == "actNotFound" {
            return AccountTxPage(transactions: [], marker: nil)
        }
    }

    /// `nil` when the node does not know the transaction (`txnNotFound`).
    func tx(hash: String) async throws -> TxResult? {
        do {
            return try await fetch(rpc: TxJsonRpc(hash: hash))
        } catch let error as RpcError where error.code == "txnNotFound" {
            return nil
        }
    }
}
