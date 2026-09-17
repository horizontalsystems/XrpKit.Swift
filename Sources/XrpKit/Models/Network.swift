import Foundation

public enum Network: String, CaseIterable {
    case mainNet
    case testNet

    /// `network_id` as reported by `server_state`.
    public var id: Int {
        switch self {
        case .mainNet: return 0
        case .testNet: return 1
        }
    }

    public var isMainNet: Bool {
        self == .mainNet
    }

    /// Default JSON-RPC endpoints in failover order, the same list as the Android kit.
    public var rpcUrls: [URL] {
        switch self {
        case .mainNet:
            return [
                URL(string: "https://xrplcluster.com/")!,
                URL(string: "https://s2.ripple.com:51234/")!,
                URL(string: "https://s1.ripple.com:51234/")!,
            ]
        case .testNet:
            return [
                URL(string: "https://s.altnet.rippletest.net:51234/")!,
                URL(string: "https://testnet.xrpl-labs.com/")!,
            ]
        }
    }

    public var explorerUrl: String {
        switch self {
        case .mainNet: return "https://livenet.xrpl.org"
        case .testNet: return "https://testnet.xrpl.org"
        }
    }

    public func transactionUrl(hash: String) -> String {
        "\(explorerUrl)/transactions/\(hash)"
    }

    public func accountUrl(address: String) -> String {
        "\(explorerUrl)/accounts/\(address)"
    }
}
