import XCTest
@testable import XrpKit

final class RpcApiProviderTests: XCTestCase {
    private let urls = [URL(string: "https://a.example/")!, URL(string: "https://b.example/")!, URL(string: "https://c.example/")!]
    private var transport: StubRpcTransport!
    private var provider: RpcApiProvider!

    override func setUp() {
        super.setUp()
        transport = StubRpcTransport()
        provider = RpcApiProvider(urls: urls, transport: transport)
    }

    func testTransportFailureMovesToNextEndpointAndKeepsIt() async throws {
        transport.answer(url: urls[0], "server_state", .error(URLError(.timedOut)))
        transport.answer(url: urls[1], "server_state", .ok(Fixtures.serverState(validated: 42)))

        let state = try await provider.serverState()

        XCTAssertEqual(state.validatedLedger, 42)
        XCTAssertEqual(transport.calls.map(\.url), [urls[0], urls[1]])
        XCTAssertEqual(provider.preferredIndex, 1)

        _ = try await provider.serverState()
        XCTAssertEqual(transport.calls.last?.url, urls[1])
    }

    func testRpcErrorIsThrownWithoutFailover() async {
        transport.answer("account_info", .rpcError(code: "actMalformed", message: "Account malformed."))

        do {
            _ = try await provider.fetch(rpc: AccountInfoJsonRpc(address: "rXXX"))
            XCTFail("expected RpcError")
        } catch let error as RpcError {
            XCTAssertEqual(error.code, "actMalformed")
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(transport.calls.count, 1)
    }

    func testActNotFoundMapsToNil() async throws {
        transport.answer("account_info", .rpcError(code: "actNotFound"))
        let info = try await provider.accountInfo(address: Fixtures.address)
        XCTAssertNil(info)
    }

    func testLoadWarningShiftsPreferredIndex() async throws {
        transport.answer(url: urls[0], "server_state", .ok(Fixtures.serverState().merging(["warning": "load"]) { $1 }))
        transport.answer(url: urls[1], "server_state", .ok(Fixtures.serverState()))

        _ = try await provider.serverState()
        XCTAssertEqual(provider.preferredIndex, 1)

        _ = try await provider.serverState()
        XCTAssertEqual(transport.calls.last?.url, urls[1])
    }

    func testAllEndpointsFailingThrowsNoEndpointAvailable() async {
        for url in urls {
            transport.answer(url: url, "fee", .error(URLError(.cannotConnectToHost)))
        }

        do {
            _ = try await provider.fee()
            XCTFail("expected NoEndpointAvailable")
        } catch let error as NoEndpointAvailable {
            XCTAssertTrue(error.underlying is URLError)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(transport.calls.count, urls.count)
    }

    func testDnsFailureGetsASecondPass() async {
        for url in urls {
            transport.answer(url: url, "fee", .error(URLError(.cannotFindHost)))
        }

        _ = try? await provider.fee()
        XCTAssertEqual(transport.calls.count, urls.count * 2)
    }

    func testHostileNumbersAreInvalidResponseNotTrap() async {
        let cases: [(String, RpcJson)] = [
            ("Balance not a drops string", ["account_data": ["Account": Fixtures.address, "Balance": 12, "Sequence": 1, "OwnerCount": 0]]),
            ("Balance huge", ["account_data": ["Account": Fixtures.address, "Balance": "99999999999999999999999", "Sequence": 1, "OwnerCount": 0]]),
            ("Sequence above 32 bits", ["account_data": ["Account": Fixtures.address, "Balance": "1", "Sequence": 4_294_967_296, "OwnerCount": 0]]),
            ("Sequence negative", ["account_data": ["Account": Fixtures.address, "Balance": "1", "Sequence": -1, "OwnerCount": 0]]),
            ("Sequence fractional", ["account_data": ["Account": Fixtures.address, "Balance": "1", "Sequence": 1.5, "OwnerCount": 0]]),
            // the reserve is `base + inc * ownerCount`: unbounded inputs trap, and the value would
            // already be in the database, so the crash would repeat on every launch
            ("OwnerCount absurd", ["account_data": ["Account": Fixtures.address, "Balance": "1", "Sequence": 1, "OwnerCount": 4_000_000_000]]),
            ("missing account_data", ["validated": true]),
        ]

        for (name, result) in cases {
            transport.answer("account_info", .ok(result))
            do {
                _ = try await provider.accountInfo(address: Fixtures.address)
                XCTFail("\(name): expected failure")
            } catch let error as NoEndpointAvailable {
                XCTAssertTrue(error.underlying is InvalidResponse, name)
            } catch {
                XCTFail("\(name): unexpected \(error)")
            }
        }

        transport.answer("server_state", .ok(["state": ["validated_ledger": ["seq": 10, "reserve_base": -1, "reserve_inc": 0]]]))
        let state = try? await provider.serverState()
        XCTAssertNil(state)

        transport.answer("server_state", .ok(["state": ["server_state": "full", "validated_ledger": ["seq": 10, "reserve_base": UInt64.max, "reserve_inc": 200_000]]]))
        let hugeReserve = try? await provider.serverState()
        XCTAssertNil(hugeReserve)

        transport.answer("fee", .ok(["drops": ["base_fee": "1e9", "open_ledger_fee": "10", "minimum_fee": "10", "median_fee": "10"]]))
        let fee = try? await provider.fee()
        XCTAssertNil(fee)
    }

    func testAccountLinesPagingIsCapped() async {
        transport.answer("account_lines", .ok(["lines": [["currency": "USD", "account": Fixtures.issuer, "balance": "1", "limit": "10"]], "marker": "again"]))

        do {
            _ = try await provider.accountLines(address: Fixtures.address)
            XCTFail("expected InvalidResponse")
        } catch is InvalidResponse {
            XCTAssertEqual(transport.calls(method: "account_lines").count, RpcApiProvider.maxPages)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAccountLinesFollowsMarkerAndMapsFlags() async throws {
        transport.answer(
            "account_lines",
            .ok(["lines": [["currency": "USD", "account": Fixtures.issuer, "balance": "1", "limit": "10", "freeze_peer": true]], "marker": ["ledger": 1, "seq": 2]]),
            .ok(["lines": [["currency": "EUR", "account": Fixtures.issuer, "balance": "2", "limit": "20", "freeze": true, "no_ripple": true]]])
        )

        let lines = try await provider.accountLines(address: Fixtures.address)

        XCTAssertEqual(lines.map(\.currency), ["USD", "EUR"])
        XCTAssertTrue(lines[0].frozenByPeer)
        XCTAssertFalse(lines[0].frozen)
        XCTAssertTrue(lines[1].frozen)
        XCTAssertTrue(lines[1].noRipple)
        let secondCall = transport.calls(method: "account_lines")[1]
        XCTAssertNotNil(secondCall.params["marker"])
    }
}
