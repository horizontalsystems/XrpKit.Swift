import Foundation
import GRDB

/// A transaction touching the kit's account, as stored locally. Amounts are already resolved:
/// `deliveredAmount` is what the destination actually received (from `meta.delivered_amount`),
/// which for partial payments is less than `amount`.
public class Transaction: Record {
    public static let expiredResult = "expired"

    public let hash: String
    /// Ledger the transaction was included in; nil while pending.
    public let ledgerIndex: UInt32?
    /// Unix seconds. For pending transactions this is the submission time.
    public let timestamp: Int64
    /// rippled transaction type, e.g. Payment, TrustSet, AccountDelete, OfferCreate.
    public let type: String
    public let account: String
    public let destination: String?
    public let amount: Amount?
    public let deliveredAmount: Amount?
    public let feeDrops: UInt64
    public let sequence: UInt32
    public let destinationTag: UInt32?
    public let sourceTag: UInt32?
    /// For TrustSet: the trust line being changed.
    public let limitAmount: Amount?
    /// Engine result, e.g. tesSUCCESS or tecPATH_DRY; nil while pending.
    public let result: String?
    /// In a validated ledger.
    public let validated: Bool
    /// Validated with a failure result, or expired unvalidated past `lastLedgerSequence`.
    public let failed: Bool
    public let lastLedgerSequence: UInt32?
    /// First memo's data decoded as UTF-8 when it is text, else nil.
    public let memo: String?

    init(
        hash: String, ledgerIndex: UInt32?, timestamp: Int64, type: String, account: String, destination: String?,
        amount: Amount?, deliveredAmount: Amount?, feeDrops: UInt64, sequence: UInt32, destinationTag: UInt32?, sourceTag: UInt32?,
        limitAmount: Amount?, result: String?, validated: Bool, failed: Bool, lastLedgerSequence: UInt32?, memo: String?
    ) {
        self.hash = hash
        self.ledgerIndex = ledgerIndex
        self.timestamp = timestamp
        self.type = type
        self.account = account
        self.destination = destination
        self.amount = amount
        self.deliveredAmount = deliveredAmount
        self.feeDrops = feeDrops
        self.sequence = sequence
        self.destinationTag = destinationTag
        self.sourceTag = sourceTag
        self.limitAmount = limitAmount
        self.result = result
        self.validated = validated
        self.failed = failed
        self.lastLedgerSequence = lastLedgerSequence
        self.memo = memo
        super.init()
    }

    public var isPending: Bool {
        !validated && !failed
    }

    public var isSuccess: Bool {
        validated && result == "tesSUCCESS"
    }

    public func isIncoming(ownAddress: String) -> Bool {
        destination == ownAddress && account != ownAddress
    }

    public func isOutgoing(ownAddress: String) -> Bool {
        account == ownAddress
    }

    func expired() -> Transaction {
        Transaction(
            hash: hash, ledgerIndex: ledgerIndex, timestamp: timestamp, type: type, account: account, destination: destination,
            amount: amount, deliveredAmount: deliveredAmount, feeDrops: feeDrops, sequence: sequence, destinationTag: destinationTag, sourceTag: sourceTag,
            limitAmount: limitAmount, result: result ?? Self.expiredResult, validated: validated, failed: true, lastLedgerSequence: lastLedgerSequence, memo: memo
        )
    }

    // MARK: - Record

    override public class var databaseTableName: String {
        "transactions"
    }

    enum Columns: String, ColumnExpression {
        case hash, ledgerIndex, timestamp, type, account, destination
        case amountValue, amountCurrency, amountIssuer
        case deliveredValue, deliveredCurrency, deliveredIssuer
        case feeDrops, sequence, destinationTag, sourceTag
        case limitValue, limitCurrency, limitIssuer
        case result, validated, failed, lastLedgerSequence, memo
    }

    public required init(row: Row) throws {
        hash = row[Columns.hash]
        ledgerIndex = row[Columns.ledgerIndex]
        timestamp = row[Columns.timestamp]
        type = row[Columns.type]
        account = row[Columns.account]
        destination = row[Columns.destination]
        amount = Amount(value: row[Columns.amountValue], currency: row[Columns.amountCurrency], issuer: row[Columns.amountIssuer])
        deliveredAmount = Amount(value: row[Columns.deliveredValue], currency: row[Columns.deliveredCurrency], issuer: row[Columns.deliveredIssuer])
        feeDrops = UInt64(bitPattern: row[Columns.feeDrops] as Int64)
        sequence = row[Columns.sequence]
        destinationTag = row[Columns.destinationTag]
        sourceTag = row[Columns.sourceTag]
        limitAmount = Amount(value: row[Columns.limitValue], currency: row[Columns.limitCurrency], issuer: row[Columns.limitIssuer])
        result = row[Columns.result]
        validated = row[Columns.validated]
        failed = row[Columns.failed]
        lastLedgerSequence = row[Columns.lastLedgerSequence]
        memo = row[Columns.memo]
        try super.init(row: row)
    }

    override public func encode(to container: inout PersistenceContainer) throws {
        container[Columns.hash] = hash
        container[Columns.ledgerIndex] = ledgerIndex
        container[Columns.timestamp] = timestamp
        container[Columns.type] = type
        container[Columns.account] = account
        container[Columns.destination] = destination
        container[Columns.amountValue] = amount?.storedValue
        container[Columns.amountCurrency] = amount?.currency
        container[Columns.amountIssuer] = amount?.issuer
        container[Columns.deliveredValue] = deliveredAmount?.storedValue
        container[Columns.deliveredCurrency] = deliveredAmount?.currency
        container[Columns.deliveredIssuer] = deliveredAmount?.issuer
        container[Columns.feeDrops] = Int64(bitPattern: feeDrops)
        container[Columns.sequence] = sequence
        container[Columns.destinationTag] = destinationTag
        container[Columns.sourceTag] = sourceTag
        container[Columns.limitValue] = limitAmount?.storedValue
        container[Columns.limitCurrency] = limitAmount?.currency
        container[Columns.limitIssuer] = limitAmount?.issuer
        container[Columns.result] = result
        container[Columns.validated] = validated
        container[Columns.failed] = failed
        container[Columns.lastLedgerSequence] = lastLedgerSequence
        container[Columns.memo] = memo
    }
}

extension Amount {
    /// Column form: drops for XRP, the decimal string for an issued value.
    var storedValue: String {
        switch self {
        case let .xrp(drops): return String(drops)
        case let .issued(value, _, _): return value.xrplString
        }
    }

    init?(value: String?, currency: String?, issuer: String?) {
        guard let value, let currency else {
            return nil
        }
        if currency == CurrencyCodec.xrp, issuer == nil {
            guard let drops = UInt64(value) else {
                return nil
            }
            self = .xrp(drops: drops)
        } else if let issuer, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) {
            self = .issued(value: decimal, currency: currency, issuer: issuer)
        } else {
            return nil
        }
    }
}

extension Decimal {
    /// Plain decimal notation with a dot, as rippled writes issued values.
    var xrplString: String {
        NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }
}
