import Foundation

extension Data {
    /// Upper-case hex, the form rippled uses in JSON.
    var xrpHex: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

extension String {
    /// Strict hex decoding: even length, hex digits only; `nil` otherwise.
    var xrpHexData: Data? {
        guard count % 2 == 0 else {
            return nil
        }

        var data = Data(capacity: count / 2)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: 2)
            guard let byte = UInt8(self[index ..< next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        return data
    }

    var isXrpHex: Bool {
        !isEmpty && allSatisfy(\.isHexDigit)
    }
}
