import Foundation

/// Strict readers for rippled JSON. Every number that the documentation types as a JSON number
/// is read with `UInt64(exactly:)`/`UInt32(exactly:)`, every drops or issued value as a string;
/// anything else is `InvalidResponse`, never a truncation or a trap.
typealias RpcJson = [String: Any]

extension [String: Any] {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func requireString(_ key: String) throws -> String {
        guard let value = string(key) else {
            throw InvalidResponse("missing field '\(key)'")
        }
        return value
    }

    func bool(_ key: String) -> Bool {
        self[key] as? Bool ?? false
    }

    func object(_ key: String) -> RpcJson? {
        self[key] as? RpcJson
    }

    func requireObject(_ key: String) throws -> RpcJson {
        guard let value = object(key) else {
            throw InvalidResponse("missing object '\(key)'")
        }
        return value
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func requireArray(_ key: String) throws -> [Any] {
        guard let value = array(key) else {
            throw InvalidResponse("missing array '\(key)'")
        }
        return value
    }

    /// A JSON number field. JSON booleans are NSNumber too (and `0`/`1` even cast to `Bool`),
    /// so they are told apart by their CoreFoundation type.
    func uint64(_ key: String) throws -> UInt64? {
        guard let raw = self[key], !(raw is NSNull) else {
            return nil
        }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = UInt64(exactly: number) else {
            throw InvalidResponse("field '\(key)' is not an unsigned integer")
        }
        return value
    }

    func requireUInt64(_ key: String) throws -> UInt64 {
        guard let value = try uint64(key) else {
            throw InvalidResponse("missing field '\(key)'")
        }
        return value
    }

    func uint32(_ key: String) throws -> UInt32? {
        guard let value = try uint64(key) else {
            return nil
        }
        guard let narrowed = UInt32(exactly: value) else {
            throw InvalidResponse("field '\(key)' exceeds 32 bits")
        }
        return narrowed
    }

    func requireUInt32(_ key: String) throws -> UInt32 {
        guard let value = try uint32(key) else {
            throw InvalidResponse("missing field '\(key)'")
        }
        return value
    }

    /// A drops amount, which rippled always sends as a decimal string.
    func drops(_ key: String) throws -> UInt64? {
        guard let raw = self[key], !(raw is NSNull) else {
            return nil
        }
        guard let string = raw as? String, let value = UInt64(string) else {
            throw InvalidResponse("field '\(key)' is not a drops string")
        }
        return value
    }

    func requireDrops(_ key: String) throws -> UInt64 {
        guard let value = try drops(key) else {
            throw InvalidResponse("missing field '\(key)'")
        }
        return value
    }
}

extension Decimal {
    /// Issued values arrive as decimal strings; `Decimal(string:)` parses `"1e9"` as nil and never traps.
    init?(xrplValue: String) {
        guard let value = Decimal(string: xrplValue, locale: Locale(identifier: "en_US_POSIX")), value.isFinite else {
            return nil
        }
        self = value
    }
}
