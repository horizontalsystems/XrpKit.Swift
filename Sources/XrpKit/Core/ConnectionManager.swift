import Combine
import Foundation
import HsExtensions
import Network

/// Monitors network reachability using `NWPathMonitor` and exposes a Combine publisher that
/// fires only on distinct transitions (SolanaKit `ConnectionManager`).
///
/// `stop()` cancels the underlying `NWPathMonitor`, which cannot be restarted; `start()` creates a fresh one.
final class ConnectionManager {
    private var monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "io.horizontalsystems.xrp-kit.connection-manager")

    @DistinctPublished private(set) var isConnected = false

    deinit {
        monitor.cancel()
    }
}

extension ConnectionManager: IConnectionManager {
    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected
    }

    func start() {
        monitor.cancel()

        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: monitorQueue)
    }

    func stop() {
        monitor.cancel()
    }
}
