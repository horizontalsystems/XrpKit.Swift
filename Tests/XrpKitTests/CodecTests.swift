import XCTest
@testable import XrpKit

final class CodecTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    /// Every field of a fixture transaction is in the codec's table and its type is one the codec builds.
    private func isSupported(_ json: [String: Any]) -> Bool {
        json.allSatisfy { key, value in
            if key == "hash" {
                return true
            }
            guard FieldDefinitions.contains(name: key) else {
                return false
            }
            if key == "TransactionType", let name = value as? String {
                return TransactionType.isSupported(name: name)
            }
            return true
        }
    }

    func testSigningDataEncoding() throws {
        // xrpl.js ripple-binary-codec signing-data-encoding.test.ts
        let tx: [String: Any] = [
            "Account": "r9LqNeG6qHxjeUocjvVki2XR35weJ9mZgQ",
            "Amount": "1000",
            "Destination": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
            "Fee": "10",
            "Flags": 2_147_483_648,
            "Sequence": 1,
            "TransactionType": "Payment",
            "TxnSignature": "30440220718D264EF05CAED7C781FF6DE298DCAC68D002562C9BF3A07C1E721B420C0DAB02203A5A4779EF4D2CCC7BC3EF886676D803A9981B928D3B8ACA483B80ECA3CD7B9B",
            "SigningPubKey": "ED5F5AC8B98974A3CA843326D9B88CEBD0560177B973EE0B149F782CFAA06DC66A",
        ]
        let expected = "120000" + "2280000000" + "2400000001" + "6140000000000003E8" + "68400000000000000A" +
            "7321ED5F5AC8B98974A3CA843326D9B88CEBD0560177B973EE0B149F782CFAA06DC66A" +
            "81145B812C9D57731E27A2DA8B1830195F88EF32A3B6" +
            "8314B5F762798A53D543A014CAF8B297CFF8F2F937E8"
        XCTAssertEqual(try BinarySerializer.serialize(tx, forSigning: true).xrpHex, expected)
        // the full serialization includes the signature between SigningPubKey and Account
        XCTAssertTrue(try BinarySerializer.serialize(tx).xrpHex.contains("7446" + "30440220718D264E"))
    }

    func testCodecFixtureTransactions() throws {
        let transactions = try XCTUnwrap(try fixture("codec-fixtures")["transactions"] as? [[String: Any]])
        var checked = 0
        for transaction in transactions {
            let json = try XCTUnwrap(transaction["json"] as? [String: Any])
            guard isSupported(json) else {
                continue
            }
            let expected = try XCTUnwrap(transaction["binary"] as? String)
            XCTAssertEqual(try BinarySerializer.serialize(json).xrpHex, expected, json["TransactionType"] as? String ?? "")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no fixtures checked")
    }

    func testDataDrivenWholeObjects() throws {
        let objects = try XCTUnwrap(try fixture("data-driven-tests")["whole_objects"] as? [[String: Any]])
        var checked = 0
        for object in objects {
            let txJson = try XCTUnwrap(object["tx_json"] as? [String: Any])
            guard isSupported(txJson) else {
                continue
            }
            let expected = try XCTUnwrap(object["blob_with_no_signing"] as? String)
            XCTAssertEqual(try BinarySerializer.serialize(txJson).xrpHex, expected)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no whole objects checked")
    }

    func testDataDrivenAmountValues() throws {
        let tests = try XCTUnwrap(try fixture("data-driven-tests")["values_tests"] as? [[String: Any]])
        var checked = 0
        for test in tests {
            guard test["type"] as? String == "Amount" else {
                continue
            }

            let amount: Amount
            if let drops = test["test_json"] as? String {
                // negative or oversized drops strings are not representable at all; the JSON layer rejects them
                guard let parsed = UInt64(drops) else {
                    continue
                }
                amount = .xrp(drops: parsed)
            } else if let object = test["test_json"] as? [String: Any] {
                // Multi-Purpose Token amounts are not supported by this codec
                guard object["mpt_issuance_id"] == nil,
                      let value = object["value"] as? String, let currency = object["currency"] as? String, let issuer = object["issuer"] as? String,
                      let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
                else {
                    continue
                }
                amount = .issued(value: decimal, currency: currency, issuer: issuer)
            } else {
                continue
            }

            if test["error"] != nil {
                XCTAssertThrowsError(try AmountCodec.encode(amount), "expected error for \(test["test_json"] ?? "")")
            } else {
                XCTAssertEqual(try AmountCodec.encode(amount).xrpHex, test["expected_hex"] as? String, "\(test["test_json"] ?? "")")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20)
    }

    func testFieldHeaders() throws {
        let tests = try XCTUnwrap(try fixture("data-driven-tests")["fields_tests"] as? [[String: Any]])
        var checked = 0
        for test in tests {
            let name = try XCTUnwrap(test["name"] as? String)
            guard FieldDefinitions.contains(name: name) else {
                continue
            }
            XCTAssertEqual(try FieldDefinitions.field(name: name).header().xrpHex, test["expected_hex"] as? String, name)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 20)
    }

    func testCurrencyCodes() throws {
        XCTAssertEqual(try CurrencyCodec.fromBytes(Data(count: 20)), "XRP")
        XCTAssertEqual(try CurrencyCodec.fromBytes(CurrencyCodec.toBytes("USD")), "USD")
        let rlusd = "524C555344000000000000000000000000000000"
        XCTAssertEqual(try CurrencyCodec.fromBytes(CurrencyCodec.toBytes(rlusd)), rlusd)
        XCTAssertEqual(CurrencyCodec.displayCode(rlusd), "RLUSD")
        XCTAssertEqual(CurrencyCodec.displayCode("USD"), "USD")
        XCTAssertEqual(try CurrencyCodec.normalize(rlusd.lowercased()), rlusd)
        XCTAssertTrue(CurrencyCodec.isValid("EUR"))
        XCTAssertFalse(CurrencyCodec.isValid("XRP"))
        XCTAssertFalse(CurrencyCodec.isValid("EURO"))
        XCTAssertThrowsError(try CurrencyCodec.normalize("EURO"))
    }

    func testVariableLengthPrefix() throws {
        XCTAssertEqual(try BinarySerializer.encodeLength(0).xrpHex, "00")
        XCTAssertEqual(try BinarySerializer.encodeLength(192).xrpHex, "C0")
        XCTAssertEqual(try BinarySerializer.encodeLength(193).xrpHex, "C100")
        XCTAssertEqual(try BinarySerializer.encodeLength(12480).xrpHex, "F0FF")
        XCTAssertEqual(try BinarySerializer.encodeLength(12481).xrpHex, "F10000")
        XCTAssertThrowsError(try BinarySerializer.encodeLength(918_745))
    }

    func testMemosSerializeAsArrayOfObjects() throws {
        let tx: [String: Any] = [
            "TransactionType": "Payment",
            "Account": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
            "Destination": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
            "Amount": "1",
            "Fee": "10",
            "Sequence": 1,
            "SigningPubKey": "",
            "Memos": [["Memo": ["MemoType": "4D656D6F", "MemoData": "6869"]]],
        ]
        let hex = try BinarySerializer.serialize(tx).xrpHex
        // AccountID fields (type 8) precede the STArray (type 15):
        // Account (81) Destination (83) Memos (F9) Memo (EA) MemoType (7C) MemoData (7D) end object (E1) end array (F1)
        XCTAssertTrue(hex.hasSuffix("8114B5F762798A53D543A014CAF8B297CFF8F2F937E8" + "8314B5F762798A53D543A014CAF8B297CFF8F2F937E8" + "F9EA7C044D656D6F7D026869E1F1"), hex)
    }

    func testFieldOrderIsCanonicalRegardlessOfInsertionOrder() throws {
        let ordered: [String: Any] = [
            "TransactionType": "TrustSet", "Account": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", "Sequence": 7, "Fee": "12", "Flags": 2_147_614_720,
            "LimitAmount": ["value": "1000000", "currency": "USD", "issuer": "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"],
        ]
        let scrambled: [String: Any] = [
            "LimitAmount": ["issuer": "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De", "currency": "USD", "value": "1000000"],
            "Flags": 2_147_614_720, "Fee": "12", "Sequence": 7, "Account": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", "TransactionType": "TrustSet",
        ]
        let hex = try BinarySerializer.serialize(ordered).xrpHex
        XCTAssertEqual(try BinarySerializer.serialize(scrambled).xrpHex, hex)
        // TrustSet type 0x0014, tfFullyCanonicalSig | tfSetNoRipple
        XCTAssertTrue(hex.hasPrefix("120014" + "2280020000"), hex)
    }

    func testIntegersAreRejectedNotTruncated() throws {
        var tx: [String: Any] = ["TransactionType": "Payment", "Account": "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh", "Sequence": 1, "Fee": "10"]

        tx["DestinationTag"] = 4_294_967_295
        XCTAssertNoThrow(try BinarySerializer.serialize(tx))

        tx["DestinationTag"] = 4_294_967_296
        XCTAssertThrowsError(try BinarySerializer.serialize(tx))

        tx["DestinationTag"] = -1
        XCTAssertThrowsError(try BinarySerializer.serialize(tx))

        tx["DestinationTag"] = nil
        tx["Unknown"] = 1
        XCTAssertThrowsError(try BinarySerializer.serialize(tx))
    }

    func testIssuedAmountPrecisionIsRejectedNotRounded() throws {
        let issuer = "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De"
        XCTAssertThrowsError(try AmountCodec.encode(.issued(value: Decimal(string: "1.1111111111111111")!, currency: "USD", issuer: issuer)))
        // 1e81 normalizes to 1e15 × 10^66 and is representable; the ledger maximum is 9999999999999999 × 10^80
        XCTAssertNoThrow(try AmountCodec.encode(.issued(value: Decimal(sign: .plus, exponent: 81, significand: 1), currency: "USD", issuer: issuer)))
        XCTAssertThrowsError(try AmountCodec.encode(.issued(value: Decimal(sign: .plus, exponent: 97, significand: 1), currency: "USD", issuer: issuer)))
        XCTAssertThrowsError(try AmountCodec.encode(.issued(value: Decimal(sign: .plus, exponent: -112, significand: 1), currency: "USD", issuer: issuer)))
        XCTAssertNoThrow(try AmountCodec.encode(.issued(value: Decimal(string: "1111111111111111")!, currency: "USD", issuer: issuer)))
        XCTAssertEqual(try AmountCodec.encode(.issued(value: 0, currency: "USD", issuer: issuer)).xrpHex.prefix(16), "8000000000000000")
        XCTAssertThrowsError(try AmountCodec.encode(.xrp(drops: 100_000_000_000_000_000)))
    }
}
