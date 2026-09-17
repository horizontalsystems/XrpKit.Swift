import XCTest
@testable import XrpKit

final class TransactionBuilderTests: XCTestCase {
    private let common = TransactionBuilder.Common(
        account: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
        sequence: 7,
        feeDrops: 12,
        lastLedgerSequence: 1020,
        signingPubKeyHex: "030D58EB48B4420B1F7B9DF55087E0E29FEF0E8468F9A6825B01CA2C361042D435",
        memo: nil
    )

    private func signer() throws -> Signer {
        try Signer(privateKey: XCTUnwrap("D78B9735C3F26501C7337B8A5727FD53A6EFDBC6AA55984F098488561F985E23".xrpHexData))
    }

    func testPaymentCarriesCanonicalFlagTagAndNoPartialPayment() throws {
        let tx = TransactionBuilder.payment(common: common, destination: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", amount: .xrp(drops: 1_000_000), destinationTag: 0)
        let hex = try BinarySerializer.serialize(tx).xrpHex

        // TransactionType Payment, Flags = tfFullyCanonicalSig only, Sequence, DestinationTag = 0 (present), LastLedgerSequence
        XCTAssertTrue(hex.hasPrefix("120000" + "2280000000" + "2400000007" + "2E00000000" + "201B000003FC"), hex)
        XCTAssertNil(tx["SendMax"])
        XCTAssertNil(tx["Memos"])
    }

    func testTrustSetCarriesNoRippleFlagAndLimit() throws {
        let tx = try TransactionBuilder.trustSet(common: common, currency: "usd".count == 3 ? "USD" : "", issuer: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", limit: Kit.defaultTrustLimit)
        let hex = try BinarySerializer.serialize(tx).xrpHex
        XCTAssertTrue(hex.hasPrefix("120014" + "2280020000"), hex)
        XCTAssertEqual(tx["LimitAmount"] as? Amount, .issued(value: Kit.defaultTrustLimit, currency: "USD", issuer: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"))
    }

    func testMemoIsTextPlainAndBounded() throws {
        let withMemo = TransactionBuilder.Common(account: common.account, sequence: 7, feeDrops: 12, lastLedgerSequence: 1020, signingPubKeyHex: common.signingPubKeyHex, memo: "hi")
        let tx = TransactionBuilder.payment(common: withMemo, destination: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", amount: .xrp(drops: 1), destinationTag: nil)
        let memos = try XCTUnwrap(tx["Memos"] as? [[String: Any]])
        let memo = try XCTUnwrap(memos.first?["Memo"] as? [String: String])
        XCTAssertEqual(memo["MemoType"], Data("Memo".utf8).xrpHex)
        XCTAssertEqual(memo["MemoFormat"], Data("text/plain".utf8).xrpHex)
        XCTAssertEqual(memo["MemoData"], "6869")

        XCTAssertLessThanOrEqual(try TransactionBuilder.memosSize(text: String(repeating: "a", count: 900)), TransactionBuilder.maxMemosBytes)
        XCTAssertGreaterThan(try TransactionBuilder.memosSize(text: String(repeating: "a", count: 1100)), TransactionBuilder.maxMemosBytes)
    }

    func testSigningProducesDeterministicBlobAndHash() throws {
        var tx = TransactionBuilder.payment(common: common, destination: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", amount: .xrp(drops: 1_000_000), destinationTag: nil)
        let signed = try TransactionBuilder.sign(&tx, signer: signer())

        XCTAssertEqual(signed.hash.count, 64)
        XCTAssertNotNil(tx["TxnSignature"])
        XCTAssertTrue(signed.blobHex.contains("7446" + "30") || signed.blobHex.contains("7447" + "30") || signed.blobHex.contains("7448" + "30"), "DER signature is VL-encoded under TxnSignature")

        var again = TransactionBuilder.payment(common: common, destination: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", amount: .xrp(drops: 1_000_000), destinationTag: nil)
        XCTAssertEqual(try TransactionBuilder.sign(&again, signer: signer()).hash, signed.hash)

        // the signing hash excludes the signature; the transaction hash covers the whole blob
        XCTAssertEqual(BinarySerializer.transactionHash(signedBlob: signed.blob).xrpHex, signed.hash)
    }
}
