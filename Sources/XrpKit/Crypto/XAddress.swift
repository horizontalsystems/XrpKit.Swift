import Foundation

/// X-address (XLS-5d): a classic address and an optional destination tag packed into one
/// base58check string. Mainnet X-addresses start with `X`, testnet ones with `T`.
public enum XAddress {
    private static let mainNetPrefix = Data([0x05, 0x44])
    private static let testNetPrefix = Data([0x04, 0x93])

    public struct Decoded: Equatable {
        public let accountId: AccountId
        /// An explicit tag of 0 is a real tag, distinct from `nil` (no tag).
        public let tag: UInt32?
        public let isTestNet: Bool

        public var classicAddress: String {
            accountId.address
        }
    }

    public static func isXAddress(_ input: String) -> Bool {
        (40 ... 50).contains(input.count) && (input.hasPrefix("X") || input.hasPrefix("T"))
    }

    public static func encode(accountId: AccountId, tag: UInt32?, testNet: Bool = false) -> String {
        var payload = Data(count: 31)
        payload.replaceSubrange(0 ..< 2, with: testNet ? testNetPrefix : mainNetPrefix)
        payload.replaceSubrange(2 ..< 22, with: accountId.bytes)
        payload[22] = tag == nil ? 0 : 1
        if let tag {
            payload[23] = UInt8(tag & 0xFF)
            payload[24] = UInt8((tag >> 8) & 0xFF)
            payload[25] = UInt8((tag >> 16) & 0xFF)
            payload[26] = UInt8((tag >> 24) & 0xFF)
        }
        return XrpBase58.encodeChecked(payload)
    }

    public static func decode(_ xAddress: String) throws -> Decoded {
        let payload = try XrpBase58.decodeChecked(xAddress)
        guard payload.count == 31 else {
            throw AddressError.invalidFormat
        }

        let isTestNet: Bool
        switch payload.prefix(2) {
        case mainNetPrefix: isTestNet = false
        case testNetPrefix: isTestNet = true
        default: throw AddressError.invalidFormat
        }

        let accountId = try AccountId(bytes: payload.subdata(in: 2 ..< 22))

        let tag: UInt32?
        switch payload[22] {
        case 0:
            tag = nil
        case 1:
            tag = UInt32(payload[23])
                | (UInt32(payload[24]) << 8)
                | (UInt32(payload[25]) << 16)
                | (UInt32(payload[26]) << 24)
        default:
            throw AddressError.invalidFormat
        }

        // only 32-bit tags exist; a wider tag flag or non-zero reserved bytes are rejected
        guard payload.subdata(in: 27 ..< 31).allSatisfy({ $0 == 0 }) else {
            throw AddressError.invalidFormat
        }

        return Decoded(accountId: accountId, tag: tag, isTestNet: isTestNet)
    }
}
