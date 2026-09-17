import Foundation

/// Builds local `Transaction` records from rippled transaction JSON.
enum TransactionConverter {
    /// Seconds between the Unix epoch and the Ripple epoch (2000-01-01T00:00:00Z).
    static let rippleEpochOffset: Int64 = 946_684_800
    static let tfPartialPayment: UInt32 = 0x0002_0000

    static func transaction(accountTx raw: RawTransaction) throws -> Transaction {
        try convert(hash: raw.hash, tx: raw.tx, meta: raw.meta, validated: raw.validated, ledgerIndex: raw.ledgerIndex, date: raw.date)
    }

    static func transaction(txResult result: TxResult) throws -> Transaction {
        try convert(hash: result.hash, tx: result.tx, meta: result.meta, validated: result.validated, ledgerIndex: result.ledgerIndex, date: result.date)
    }

    private static func convert(hash: String, tx: RpcJson, meta: RpcJson?, validated: Bool, ledgerIndex: UInt32?, date: UInt64?) throws -> Transaction {
        let result = meta?.string("TransactionResult")
        let type = tx.string("TransactionType") ?? "Unknown"
        let amount = amount(of: tx["Amount"] ?? tx["DeliverMax"])

        // what the destination actually received; "unavailable" only for ledgers before 2014-01-20
        let delivered: Amount?
        if let element = meta?["delivered_amount"] {
            delivered = (element as? String) == "unavailable" ? nil : self.amount(of: element)
        } else if result == "tesSUCCESS", type == "Payment", !isPartialPayment(tx) {
            delivered = amount
        } else {
            delivered = nil
        }

        let timestamp = date.map { Int64($0) + rippleEpochOffset } ?? Int64(Date().timeIntervalSince1970)

        return Transaction(
            hash: hash,
            ledgerIndex: ledgerIndex,
            timestamp: timestamp,
            type: type,
            account: try tx.requireString("Account"),
            destination: tx.string("Destination"),
            amount: amount,
            deliveredAmount: delivered,
            feeDrops: tx.string("Fee").flatMap { UInt64($0) } ?? 0,
            sequence: (try? tx.uint32("Sequence")) ?? 0,
            destinationTag: try? tx.uint32("DestinationTag"),
            sourceTag: try? tx.uint32("SourceTag"),
            limitAmount: self.amount(of: tx["LimitAmount"]),
            result: result,
            validated: validated,
            failed: validated && result != "tesSUCCESS",
            lastLedgerSequence: try? tx.uint32("LastLedgerSequence"),
            memo: memo(of: tx)
        )
    }

    private static func isPartialPayment(_ tx: RpcJson) -> Bool {
        ((try? tx.uint32("Flags")) ?? 0) & tfPartialPayment != 0
    }

    /// A drops string or a value/currency/issuer object; anything malformed is treated as absent.
    static func amount(of element: Any?) -> Amount? {
        guard let element, !(element is NSNull) else {
            return nil
        }
        if let drops = element as? String {
            return try? AmountCodec.fromDropsString(drops)
        }
        guard let object = element as? RpcJson,
              let value = object.string("value"), let currency = object.string("currency"), let issuer = object.string("issuer")
        else {
            return nil
        }
        return try? AmountCodec.issued(value: value, currency: currency, issuer: issuer)
    }

    /// First memo decoded as text when its bytes are valid UTF-8 without control characters, else nil.
    static func memo(of tx: RpcJson) -> String? {
        guard let memos = tx.array("Memos"),
              let first = memos.first as? RpcJson, let memo = first.object("Memo"),
              let dataHex = memo.string("MemoData"), let data = dataHex.xrpHexData,
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let hasControlCharacters = text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control && scalar != "\n" && scalar != "\t"
        }
        return hasControlCharacters ? nil : text
    }
}
