import Foundation
import HsToolKit

/// Builds, signs and submits transactions, recording each one locally as pending before it goes
/// out so a lost response can never turn into a second payment. Sends are serialized: concurrent
/// sends would fetch the same account sequence and one of them would fail with tefPAST_SEQ.
actor TransactionSender {
    /// Ledgers close every 3-5 s; ~20 ledgers gives a submission about a minute to be included.
    static let lastLedgerOffset: UInt32 = 20
    static let maxFeeDrops: UInt64 = 10000

    private let address: String
    private let rpcApiProvider: RpcApiProvider
    private let submitter: TransactionSubmitter
    private let storage: ITransactionStorage
    private let transactionSyncer: TransactionSyncer
    private let classifier = XrpSubmitResultClassifier()

    init(address: String, rpcApiProvider: RpcApiProvider, submitter: TransactionSubmitter, storage: ITransactionStorage, transactionSyncer: TransactionSyncer) {
        self.address = address
        self.rpcApiProvider = rpcApiProvider
        self.submitter = submitter
        self.storage = storage
        self.transactionSyncer = transactionSyncer
    }

    func estimateFeeDrops() async throws -> UInt64 {
        await Self.feeDrops(try rpcApiProvider.fee())
    }

    func sendPayment(signer: Signer, destination: String, amount: Amount, destinationTag: UInt32?, memo: String?, sendMax: Amount? = nil) async throws -> Transaction {
        try await submit(signer: signer, memo: memo) { common in
            TransactionBuilder.payment(common: common, destination: destination, amount: amount, destinationTag: destinationTag, sendMax: sendMax)
        }
    }

    func setTrustLine(signer: Signer, currency: String, issuer: String, limit: Decimal, memo: String?) async throws -> Transaction {
        try await submit(signer: signer, memo: memo) { common in
            try TransactionBuilder.trustSet(common: common, currency: currency, issuer: issuer, limit: limit)
        }
    }

    private func submit(signer: Signer, memo: String?, build: (TransactionBuilder.Common) throws -> [String: Any]) async throws -> Transaction {
        guard signer.address == address else {
            throw SendError.signerMismatch
        }
        if let memo, !memo.isEmpty, try TransactionBuilder.memosSize(text: memo) > TransactionBuilder.maxMemosBytes {
            throw SendError.memoTooLong
        }

        guard let info = try await rpcApiProvider.accountInfo(address: address) else {
            throw SendError.accountNotFound
        }
        let fee = try await rpcApiProvider.fee()
        let serverState = try await rpcApiProvider.serverState()

        let common = TransactionBuilder.Common(
            account: address,
            sequence: info.sequence,
            feeDrops: Self.feeDrops(fee),
            lastLedgerSequence: serverState.validatedLedger + Self.lastLedgerOffset,
            signingPubKeyHex: signer.publicKey.xrpHex,
            memo: memo
        )
        var tx = try build(common)
        let signed = try TransactionBuilder.sign(&tx, signer: signer)

        // the record exists before the blob leaves the device: whatever happens to the response,
        // the hash is known locally and the sync resolves it (validated, or expired past LastLedgerSequence)
        let pending = pendingRecord(tx: tx, hash: signed.hash, common: common)
        try storage.save(transactions: [pending])

        let outcome = await submitter.submit(rpc: SubmitJsonRpc(blobHex: signed.blobHex), classifier: classifier) { classifier.verdict(result: $0) }

        switch outcome {
        case .accepted, .unknown:
            transactionSyncer.publish(transactions: [pending])
            return pending
        case let .rejected(engineResult, message):
            try storage.delete(hash: signed.hash)
            throw SendError.rejected(engineResult: engineResult, message: message)
        }
    }

    private func pendingRecord(tx: [String: Any], hash: String, common: TransactionBuilder.Common) -> Transaction {
        Transaction(
            hash: hash,
            ledgerIndex: nil,
            timestamp: Int64(Date().timeIntervalSince1970),
            type: tx["TransactionType"] as? String ?? "Unknown",
            account: common.account,
            destination: tx["Destination"] as? String,
            amount: tx["Amount"] as? Amount,
            deliveredAmount: nil,
            feeDrops: common.feeDrops,
            sequence: common.sequence,
            destinationTag: tx["DestinationTag"] as? UInt32,
            sourceTag: nil,
            limitAmount: tx["LimitAmount"] as? Amount,
            result: nil,
            validated: false,
            failed: false,
            lastLedgerSequence: common.lastLedgerSequence,
            memo: common.memo
        )
    }

    /// Current open-ledger cost, never below the base fee and capped so a load spike cannot drain the account.
    static func feeDrops(_ fee: FeeInfo) -> UInt64 {
        min(max(fee.baseFeeDrops, fee.openLedgerFeeDrops), maxFeeDrops)
    }
}

public enum SendError: Error, Equatable {
    /// The kit's own account has never been funded, so it has no sequence to sign with.
    case accountNotFound
    /// The signer's key does not derive the kit's address.
    case signerMismatch
    /// rippled rejected the transaction. `engineResult` is the tec/tef/tem/ter code.
    case rejected(engineResult: String, message: String?)
    /// The serialized memo exceeds the 1 KB the ledger accepts.
    case memoTooLong
}
