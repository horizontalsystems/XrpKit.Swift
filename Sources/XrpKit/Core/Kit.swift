import Combine
import Foundation
import HsToolKit

/// Public facade. Instantiate via `Kit.instance(address:network:rpcUrls:walletId:)`; the kit never
/// sees a seed — a `Signer` is passed into each send.
public class Kit {
    /// Network defaults since December 2024, used until the first `server_state` response.
    public static let defaultBaseReserveDrops: UInt64 = 1_000_000
    public static let defaultOwnerReserveDrops: UInt64 = 200_000
    public static let defaultTrustLimit = Decimal(string: "1000000000000000")!
    public static let syncInterval: TimeInterval = 10

    public let address: String
    public let network: Network

    private let syncManager: SyncManager
    private let transactionSyncer: TransactionSyncer
    private let transactionSender: TransactionSender
    private let rpcApiProvider: RpcApiProvider
    private let transactionStorage: ITransactionStorage

    private var started = false

    init(address: String, network: Network, syncManager: SyncManager, transactionSyncer: TransactionSyncer, transactionSender: TransactionSender, rpcApiProvider: RpcApiProvider, transactionStorage: ITransactionStorage) {
        self.address = address
        self.network = network
        self.syncManager = syncManager
        self.transactionSyncer = transactionSyncer
        self.transactionSender = transactionSender
        self.rpcApiProvider = rpcApiProvider
        self.transactionStorage = transactionStorage
    }

    // MARK: - Publishers

    public var syncStatePublisher: AnyPublisher<SyncState, Never> {
        syncManager.$syncState
    }

    public var transactionsSyncStatePublisher: AnyPublisher<SyncState, Never> {
        transactionSyncer.$syncState
    }

    public var ledgerStatePublisher: AnyPublisher<LedgerState?, Never> {
        syncManager.$ledgerState
    }

    public var accountStatePublisher: AnyPublisher<AccountState, Never> {
        syncManager.$accountState
    }

    /// XRP balance, emitted when it changes.
    public var balancePublisher: AnyPublisher<Decimal, Never> {
        syncManager.$accountState.map(\.balance.decimalValue).removeDuplicates().eraseToAnyPublisher()
    }

    public var trustLinesPublisher: AnyPublisher<[TrustLine], Never> {
        syncManager.$trustLines
    }

    /// Emits every batch of new or updated transactions found by a sync, and each pending one at submit time.
    public var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        transactionSyncer.transactionsPublisher
    }

    /// Changed transactions matching the query; empty batches are suppressed.
    public func transactionsPublisher(tagQuery: TagQuery) -> AnyPublisher<[Transaction], Never> {
        let ownAddress = address
        return transactionSyncer.transactionsPublisher
            .map { transactions in transactions.filter { tagQuery.matches($0, ownAddress: ownAddress) } }
            .filter { !$0.isEmpty }
            .eraseToAnyPublisher()
    }

    public func tokenBalancePublisher(currency: String, issuer: String) -> AnyPublisher<Decimal?, Never> {
        syncManager.$trustLines
            .map { lines in lines.first { $0.currency == currency && $0.issuer == issuer }?.balance }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - State

    public var syncState: SyncState {
        syncManager.syncState
    }

    public var transactionsSyncState: SyncState {
        transactionSyncer.syncState
    }

    public var ledgerState: LedgerState? {
        syncManager.ledgerState
    }

    public var lastLedgerIndex: UInt32 {
        syncManager.ledgerState?.validatedLedger ?? 0
    }

    public var accountState: AccountState {
        syncManager.accountState
    }

    /// True once the account has received its first payment of at least the base reserve.
    public var isAccountActivated: Bool {
        accountState.exists
    }

    public var balance: Decimal {
        accountState.balance.decimalValue
    }

    public var trustLines: [TrustLine] {
        syncManager.trustLines
    }

    /// Base reserve in XRP as reported by the network, or the current default before the first sync.
    public var baseReserve: Decimal {
        Amount.xrp(drops: ledgerState?.reserveBaseDrops ?? Self.defaultBaseReserveDrops).decimalValue
    }

    public var ownerReserve: Decimal {
        Amount.xrp(drops: ledgerState?.reserveIncDrops ?? Self.defaultOwnerReserveDrops).decimalValue
    }

    /// XRP locked by the reserve: base reserve plus one increment per owned object (trust lines,
    /// offers, escrows). Zero for an account that does not exist yet.
    public var minimumBalance: Decimal {
        Self.minimumBalance(accountState: accountState, ledgerState: ledgerState)
    }

    public var minimumBalancePublisher: AnyPublisher<Decimal, Never> {
        Publishers.CombineLatest(syncManager.$accountState, syncManager.$ledgerState)
            .map { Self.minimumBalance(accountState: $0, ledgerState: $1) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Spendable XRP: balance minus the reserve. Never negative.
    public var availableBalance: Decimal {
        max(0, balance - minimumBalance)
    }

    public static func minimumBalance(accountState: AccountState, ledgerState: LedgerState?) -> Decimal {
        guard accountState.exists else {
            return 0
        }
        let base = ledgerState?.reserveBaseDrops ?? defaultBaseReserveDrops
        let increment = ledgerState?.reserveIncDrops ?? defaultOwnerReserveDrops
        return Amount.xrp(drops: base + increment * UInt64(accountState.ownerCount)).decimalValue
    }

    public func tokenBalance(currency: String, issuer: String) -> Decimal? {
        trustLines.first { $0.currency == currency && $0.issuer == issuer }?.balance
    }

    public func transactions(tagQuery: TagQuery = TagQuery(), fromHash: String? = nil, limit: Int? = nil) -> [Transaction] {
        transactionStorage.transactions(tagQuery: tagQuery, fromHash: fromHash, limit: limit)
    }

    public func allTransactions() -> [Transaction] {
        transactionStorage.allTransactions()
    }

    public func transaction(hash: String) -> Transaction? {
        transactionStorage.transaction(hash: hash)
    }

    public func pendingTransactions() -> [Transaction] {
        transactionStorage.pendingTransactions()
    }

    public func statusInfo() -> [(String, Any)] {
        [
            ("Started", started),
            ("Address", address),
            ("Network", network.rawValue),
            ("RPC", rpcApiProvider.source),
            ("Validated Ledger", lastLedgerIndex),
            ("Sync State", syncState.description),
            ("Transactions Sync State", transactionsSyncState.description),
            ("Account Activated", isAccountActivated),
            ("Balance", balance.xrplString),
            ("Reserve", minimumBalance.xrplString),
            ("Trust Lines", trustLines.count),
            ("Pending Transactions", pendingTransactions().count),
        ]
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        syncManager.start()
    }

    public func stop() {
        started = false
        syncManager.stop()
    }

    public func pause() {
        syncManager.pause()
    }

    public func resume() {
        syncManager.resume()
    }

    public func refresh() {
        syncManager.refresh()
    }

    // MARK: - Network queries

    /// Current transaction cost in XRP, from the `fee` command.
    public func estimateFee() async throws -> Decimal {
        await Amount.xrp(drops: try transactionSender.estimateFeeDrops()).decimalValue
    }

    /// Account details for any classic address, or nil when the account has never been funded.
    public func accountInfo(address: String) async throws -> AccountInfo? {
        try await rpcApiProvider.accountInfo(address: AccountId.fromAddress(address).address)
    }

    public func doesAccountExist(address: String) async throws -> Bool {
        try await accountInfo(address: address) != nil
    }

    /// True when the destination has the RequireDestTag flag: an untagged payment would fail.
    public func requiresDestinationTag(address: String) async throws -> Bool {
        try await accountInfo(address: address)?.requiresDestinationTag ?? false
    }

    /// Whether `address` holds a trust line for the token (any limit or balance).
    public func isTrustLineSet(currency: String, issuer: String, address: String? = nil) async throws -> Bool {
        let normalized = try CurrencyCodec.normalize(currency)
        let classic = try AccountId.fromAddress(address ?? self.address).address
        return try await rpcApiProvider.accountLines(address: classic).contains { $0.currency == normalized && $0.issuer == issuer }
    }

    // MARK: - Sending

    /// Sends XRP. A payment to an unfunded address must be at least the base reserve, or the
    /// network rejects it with tecNO_DST_INSUF_XRP. Returns the pending transaction; its hash is
    /// final and the record is updated by later syncs.
    public func sendXrp(to destination: String, amount: Decimal, destinationTag: UInt32? = nil, memo: String? = nil, signer: Signer) async throws -> Transaction {
        let (classic, tag) = try Self.resolveDestination(address: destination, tag: destinationTag, network: network)
        let drops = try Self.drops(xrp: amount)
        let transaction = try await transactionSender.sendPayment(signer: signer, destination: classic, amount: .xrp(drops: drops), destinationTag: tag, memo: memo)
        await syncAfterSend()
        return transaction
    }

    /// Sends an issued token over the trust line. SendMax equals the amount so an issuer transfer
    /// fee surfaces as a failure rather than a silent shortfall.
    public func sendToken(currency: String, issuer: String, to destination: String, amount: Decimal, destinationTag: UInt32? = nil, memo: String? = nil, signer: Signer) async throws -> Transaction {
        let (classic, tag) = try Self.resolveDestination(address: destination, tag: destinationTag, network: network)
        let issued = try Amount.issued(value: amount, currency: CurrencyCodec.normalize(currency), issuer: issuer)
        let transaction = try await transactionSender.sendPayment(signer: signer, destination: classic, amount: issued, destinationTag: tag, memo: memo, sendMax: issued)
        await syncAfterSend()
        return transaction
    }

    /// Creates or updates a trust line. Costs one owner reserve increment while the line exists.
    public func setTrustLine(currency: String, issuer: String, limit: Decimal = Kit.defaultTrustLimit, memo: String? = nil, signer: Signer) async throws -> Transaction {
        let transaction = try await transactionSender.setTrustLine(signer: signer, currency: currency, issuer: issuer, limit: limit, memo: memo)
        await syncAfterSend()
        return transaction
    }

    private func syncAfterSend() async {
        // the send already succeeded; if this cycle fails the next timer tick picks the state up
        await syncManager.syncNow()
    }

    /// Whole drops only: XRP has six decimals, anything finer is not representable on the ledger.
    static func drops(xrp: Decimal) throws -> UInt64 {
        var drops = xrp * Amount.dropsPerXrp
        var rounded = Decimal()
        NSDecimalRound(&rounded, &drops, 0, .plain)
        guard drops >= 0, drops == rounded, let value = UInt64(exactly: NSDecimalNumber(decimal: drops)) else {
            throw CodecError.invalidAmount(xrp.xrplString)
        }
        return value
    }
}

// MARK: - Addresses and currencies

public extension Kit {
    /// Throws `AddressError.invalidFormat` for anything that is not a classic r-address or an X-address.
    static func validate(address: String) throws {
        if XAddress.isXAddress(address) {
            _ = try XAddress.decode(address)
        } else {
            _ = try AccountId.fromAddress(address)
        }
    }

    static func isValid(address: String) -> Bool {
        (try? validate(address: address)) != nil
    }

    /// Classic address, tag and network packed in an X-address, or nil when `address` is not one.
    static func decode(xAddress: String) -> XAddress.Decoded? {
        guard XAddress.isXAddress(xAddress) else {
            return nil
        }
        return try? XAddress.decode(xAddress)
    }

    /// The classic address and tag a payment goes to. An X-address must belong to the kit's
    /// network, a typed tag must not contradict the tag packed in it, and an explicit tag of 0
    /// packed in it is a real tag; a tagless X-address keeps the typed tag.
    static func resolveDestination(address: String, tag: UInt32?, network: Network) throws -> (classic: String, tag: UInt32?) {
        if XAddress.isXAddress(address) {
            let decoded = try XAddress.decode(address)
            guard decoded.isTestNet == !network.isMainNet else {
                throw AddressError.networkMismatch
            }
            if let tag, let packed = decoded.tag, tag != packed {
                throw AddressError.tagConflict
            }
            return (decoded.classicAddress, decoded.tag ?? tag)
        }
        return (try AccountId.fromAddress(address).address, tag)
    }

    /// A 3-character standard code or the 40-hex ledger form (Android `XrpKit.isValidCurrencyCode`).
    static func isValidCurrencyCode(_ code: String) -> Bool {
        CurrencyCodec.isValid(code)
    }

    /// Display form of a currency code: hex codes that spell printable text are decoded (RLUSD, USDC).
    static func displayCurrencyCode(_ code: String) -> String {
        CurrencyCodec.displayCode(code)
    }
}

// MARK: - Instances

public extension Kit {
    static func instance(address: String, network: Network, rpcUrls: [URL], walletId: String, minLogLevel: Logger.Level = .error) throws -> Kit {
        let classic = try AccountId.fromAddress(address).address
        let logger = Logger(minLogLevel: minLogLevel)

        // deliberately unlogged, unlike SolanaKit and TronKit: `NetworkManager` prints the whole
        // request body when a call fails, and for `submit` that body is the signed `tx_blob`
        // (a signed blob, a signature or a key never goes to a log). The provider and the submitter log
        // every failure themselves, with the method, the host and the error but no parameters.
        let networkManager = NetworkManager()
        let rpcApiProvider = RpcApiProvider(urls: rpcUrls, networkManager: networkManager, logger: logger)

        let dbPool = try KitDatabase.pool(network: network, walletId: walletId)
        let mainStorage = try MainStorage(dbPool: dbPool)
        let transactionStorage = try TransactionStorage(dbPool: dbPool, address: classic)

        let transactionSyncer = TransactionSyncer(address: classic, rpcApiProvider: rpcApiProvider, mainStorage: mainStorage, transactionStorage: transactionStorage)
        let apiSyncer = ApiSyncer(connectionManager: ReachabilityManager(), syncInterval: syncInterval)
        let syncManager = SyncManager(address: classic, apiSyncer: apiSyncer, rpcApiProvider: rpcApiProvider, transactionSyncer: transactionSyncer, storage: mainStorage)
        let submitter = TransactionSubmitter(rpcApiProvider: rpcApiProvider, logger: logger)
        let transactionSender = TransactionSender(address: classic, rpcApiProvider: rpcApiProvider, submitter: submitter, storage: transactionStorage, transactionSyncer: transactionSyncer)

        return Kit(address: classic, network: network, syncManager: syncManager, transactionSyncer: transactionSyncer, transactionSender: transactionSender, rpcApiProvider: rpcApiProvider, transactionStorage: transactionStorage)
    }

    /// Removes the databases of every wallet not listed, for both networks.
    static func clear(exceptFor walletIds: [String]) throws {
        try KitDatabase.clear(exceptFor: walletIds)
    }
}
