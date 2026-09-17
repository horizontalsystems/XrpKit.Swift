import Foundation

public struct NodePingResult: Equatable {
    /// Latency thresholds for UI coloring, the same as the Monero kit.
    public static let pingGood: TimeInterval = 0.333
    public static let pingMedium: TimeInterval = 0.667

    public let url: URL
    /// Wall-clock time of one `server_state` round-trip; nil = unreachable.
    public let responseTime: TimeInterval?
    /// The node's validated ledger index. 0 when unreachable or unparseable.
    public let height: UInt64
    /// Reachable, answered `server_state` with a fully synced state on the expected network.
    public let isValid: Bool

    public var isReachable: Bool {
        responseTime != nil
    }
}

/// Measures response time and validated ledger of rippled JSON-RPC nodes with a single
/// `server_state` call per node. Static and independent of any Kit instance (MoneroKit `NodePinger`).
public enum NodePinger {
    /// `server_state` values in which the node serves current ledger data.
    static let syncedStates: Set<String> = ["full", "proposing", "validating"]

    public static func ping(urls: [URL], network: Network, timeout: TimeInterval = 5) async -> [NodePingResult] {
        await withTaskGroup(of: (Int, NodePingResult).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    await (index, ping(url: url, network: network, timeout: timeout))
                }
            }

            var results = [NodePingResult?](repeating: nil, count: urls.count)
            for await (index, result) in group {
                results[index] = result
            }

            return results.compactMap { $0 }
        }
    }

    public static func ping(url: URL, network: Network, timeout: TimeInterval = 5) async -> NodePingResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ServerStateJsonRpc().body)
        request.timeoutInterval = timeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        // Monotonic clock: wall-clock Date() would corrupt a sample if NTP steps the clock
        let start = DispatchTime.now()

        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else {
                return NodePingResult(url: url, responseTime: elapsed, height: 0, isValid: false)
            }

            return result(url: url, responseTime: elapsed, jsonObject: json, network: network)
        } catch {
            return NodePingResult(url: url, responseTime: nil, height: 0, isValid: false)
        }
    }

    /// Pure classification of a `server_state` response, separated so it can be pinned by tests.
    static func result(url: URL, responseTime: TimeInterval, jsonObject: Any, network: Network) -> NodePingResult {
        guard let parsed = try? JsonRpcResponse.parse(method: "server_state", jsonObject: jsonObject),
              let state = parsed.result.object("state")
        else {
            return NodePingResult(url: url, responseTime: responseTime, height: 0, isValid: false)
        }

        let height = (try? state.object("validated_ledger")?.uint64("seq")) ?? 0
        let synced = state.string("server_state").map { syncedStates.contains($0) } ?? false
        // `network_id` is not in the documented response, newer rippled versions add it; check it only when present
        let networkMatches = (try? state.uint64("network_id")).map { $0 == UInt64(network.id) } ?? true

        return NodePingResult(url: url, responseTime: responseTime, height: height, isValid: height > 0 && synced && networkMatches)
    }
}
