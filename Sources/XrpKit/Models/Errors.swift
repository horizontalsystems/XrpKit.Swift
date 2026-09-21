import Foundation

/// rippled returned `status: error`. `code` is the rippled error token, e.g. `actNotFound`.
public struct RpcError: Error, Equatable {
    public let code: String
    public let message: String?

    public init(code: String, message: String?) {
        self.code = code
        self.message = message
    }
}

public extension RpcError {
    /// rippled reports both kinds of failure through the same `status: error` envelope: something
    /// wrong with the request, and something wrong with the node right now (busy, not synced, no
    /// ledger yet, an internal fault). Only the first kind is worth believing from a single node;
    /// the second is a reason to ask another one. The list is therefore the request-shaped tokens,
    /// and the default is "try the next node" - a wrong guess there costs one extra call, while
    /// the opposite wrong guess lets one bad node block every send.
    private static let deterministicCodes: Set<String> = [
        "actBitcoin", "actMalformed", "actNotFound",
        "badSecret", "badSeed",
        "entryNotFound",
        "invalidParams", "invalidTransaction",
        "lgrIdxMalformed", "lgrIdxsInvalid", "lgrNotFound",
        "malformedAddress", "malformedCurrency", "malformedOwner", "malformedRequest",
        "srcActMalformed", "srcActMissing",
        "txnNotFound",
        "unknownCmd",
    ]

    /// True when every node would answer this way, so failing over could only repeat it.
    var isDeterministic: Bool {
        Self.deterministicCodes.contains(code)
    }
}

/// A response did not have the shape the kit expects. Treated as untrusted input.
public struct InvalidResponse: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Every endpoint failed, or the last one returned an unusable response.
public struct NoEndpointAvailable: Error {
    public let underlying: Error?

    public init(underlying: Error?) {
        self.underlying = underlying
    }
}

// User-facing descriptions, worded as the Android kit's exception messages.

extension RpcError: LocalizedError {
    public var errorDescription: String? {
        message.map { "\(code): \($0)" } ?? code
    }
}

extension InvalidResponse: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension NoEndpointAvailable: LocalizedError {
    public var errorDescription: String? {
        underlying?.localizedDescription ?? "No endpoint available"
    }
}
