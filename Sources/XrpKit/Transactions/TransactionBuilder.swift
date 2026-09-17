import Foundation

/// Builds transaction dictionaries in the codec's shape and signs them.
enum TransactionBuilder {
    /// tfFullyCanonicalSig: harmless since RequireFullyCanonicalSig, still set by reference clients.
    static let tfFullyCanonicalSig: UInt32 = 0x8000_0000
    /// TrustSet flag: opt the trust line out of rippling, the default for end-user wallets.
    static let tfSetNoRipple: UInt32 = 0x0002_0000

    struct Common {
        let account: String
        let sequence: UInt32
        let feeDrops: UInt64
        let lastLedgerSequence: UInt32
        let signingPubKeyHex: String
        let memo: String?
    }

    struct Signed {
        let blob: Data
        let hash: String

        var blobHex: String {
            blob.xrpHex
        }
    }

    static func payment(common: Common, destination: String, amount: Amount, destinationTag: UInt32?, sendMax: Amount? = nil) -> [String: Any] {
        var tx = base(common: common, type: "Payment")
        tx["Destination"] = destination
        tx["Amount"] = amount
        if let destinationTag {
            tx["DestinationTag"] = destinationTag
        }
        if let sendMax {
            tx["SendMax"] = sendMax
        }
        return tx
    }

    static func trustSet(common: Common, currency: String, issuer: String, limit: Decimal) throws -> [String: Any] {
        var tx = base(common: common, type: "TrustSet")
        tx["Flags"] = tfFullyCanonicalSig | tfSetNoRipple
        tx["LimitAmount"] = try Amount.issued(value: limit, currency: CurrencyCodec.normalize(currency), issuer: issuer)
        return tx
    }

    static func accountDelete(common: Common, destination: String, destinationTag: UInt32?) -> [String: Any] {
        var tx = base(common: common, type: "AccountDelete")
        tx["Destination"] = destination
        if let destinationTag {
            tx["DestinationTag"] = destinationTag
        }
        return tx
    }

    private static func base(common: Common, type: String) -> [String: Any] {
        var tx: [String: Any] = [
            "TransactionType": type,
            "Account": common.account,
            "Sequence": common.sequence,
            "Fee": Amount.xrp(drops: common.feeDrops),
            "LastLedgerSequence": common.lastLedgerSequence,
            "Flags": tfFullyCanonicalSig,
            "SigningPubKey": common.signingPubKeyHex,
        ]
        if let text = common.memo, !text.isEmpty {
            tx["Memos"] = [memo(text: text)]
        }
        return tx
    }

    private static func memo(text: String) -> [String: Any] {
        [
            "Memo": [
                "MemoType": Data("Memo".utf8).xrpHex,
                "MemoFormat": Data("text/plain".utf8).xrpHex,
                "MemoData": Data(text.utf8).xrpHex,
            ],
        ]
    }

    /// The serialized `Memos` field must stay within 1 KB (XRPL common fields specification).
    static let maxMemosBytes = 1024

    static func memosSize(text: String) throws -> Int {
        try BinarySerializer.serialize(["Memos": [memo(text: text)]]).count
    }

    static func sign(_ tx: inout [String: Any], signer: Signer) throws -> Signed {
        let signingHash = try BinarySerializer.signingHash(tx)
        tx["TxnSignature"] = try signer.sign(digest: signingHash).xrpHex
        let blob = try BinarySerializer.serialize(tx)
        let hash = BinarySerializer.transactionHash(signedBlob: blob).xrpHex
        return Signed(blob: blob, hash: hash)
    }
}
