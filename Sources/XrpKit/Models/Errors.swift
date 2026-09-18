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
