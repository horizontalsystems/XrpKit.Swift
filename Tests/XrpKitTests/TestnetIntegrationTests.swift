import HdWalletKit
import XCTest
@testable import XrpKit

/// Live scenario against the XRPL testnet, the same as the Android `TestnetIntegrationTest`:
/// fund a fresh account from the faucet, sync it, send a tagged payment, see it validated.
/// Skipped unless `XRPKIT_INTEGRATION=true` in the test process; CI never sets it. From the command
/// line pass it as `TEST_RUNNER_XRPKIT_INTEGRATION=true xcodebuild test ...` so xcodebuild forwards it.
final class TestnetIntegrationTests: XCTestCase {
    private static let faucetUrl = URL(string: "https://faucet.altnet.rippletest.net/accounts")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XRPKIT_INTEGRATION"] == "true", "set XRPKIT_INTEGRATION=true to run against the testnet")
    }

    func testFundSyncAndSendOnTestnet() async throws {
        let seed = try XCTUnwrap(Mnemonic.seed(mnemonic: Mnemonic.generate()))
        let signer = try Signer.instance(seed: seed)
        let address = signer.address

        // faucet: {"destination": "<address>", "xrpAmount": "..."} funds the address with test XRP
        var request = URLRequest(url: Self.faucetUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["destination": address])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let walletId = "integration-\(UUID().uuidString)"
        let kit = try Kit.instance(address: address, network: .testNet, rpcUrls: Network.testNet.rpcUrls, walletId: walletId, minLogLevel: .verbose)
        defer { try? Kit.clear(exceptFor: []) }

        // faucet payments take a few ledgers to validate
        var info: AccountInfo?
        for _ in 0 ..< 20 where info == nil {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            info = try await kit.accountInfo(address: address)
        }
        let funded = try XCTUnwrap(info, "faucet did not fund \(address)")
        XCTAssertGreaterThan(funded.balanceDrops, 0)

        let fee = try await kit.estimateFee()
        XCTAssertGreaterThan(fee, 0)

        // a second fresh account as destination; the first deposit must be at least the base reserve
        let destination = try Signer.address(seed: XCTUnwrap(Mnemonic.seed(mnemonic: Mnemonic.generate())))
        let existsBefore = try await kit.doesAccountExist(address: destination)
        XCTAssertFalse(existsBefore)

        let pending = try await kit.sendXrp(to: destination, amount: 12, destinationTag: 777, memo: "xrpkit", signer: signer)
        XCTAssertTrue(pending.isPending)
        XCTAssertEqual(pending.destinationTag, 777)

        var validated = false
        for _ in 0 ..< 20 where !validated {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let known = try await kit.rpcTx(hash: pending.hash)
            validated = known?.validated ?? false
        }
        XCTAssertTrue(validated, "payment \(pending.hash) was not validated")
        let existsAfter = try await kit.doesAccountExist(address: destination)
        XCTAssertTrue(existsAfter)
    }
}

private extension Kit {
    func rpcTx(hash: String) async throws -> TxResult? {
        try await RpcApiProvider(urls: network.rpcUrls, networkManager: .init()).tx(hash: hash)
    }
}
