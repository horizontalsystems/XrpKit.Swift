import XCTest
@testable import XrpKit

// The wallet-free destination lookups, through the same functions the instance methods use.
final class KitDestinationQueryTests: XCTestCase {
    private let urls = [URL(string: "https://a.example/")!]
    private var transport: StubRpcTransport!
    private var provider: RpcApiProvider!

    override func setUp() {
        super.setUp()
        transport = StubRpcTransport()
        provider = RpcApiProvider(urls: urls, transport: transport)
    }

    func testFlaggedAccountRequiresTag() async throws {
        transport.answer("account_info", .ok(Fixtures.accountInfo(flags: AccountState.lsfRequireDestTag)))

        let requiresTag = try await Kit.requiresDestinationTag(address: Fixtures.address, rpcApiProvider: provider)

        XCTAssertTrue(requiresTag)
    }

    func testUnflaggedAccountDoesNotRequireTag() async throws {
        transport.answer("account_info", .ok(Fixtures.accountInfo(flags: 0)))

        let requiresTag = try await Kit.requiresDestinationTag(address: Fixtures.address, rpcApiProvider: provider)

        XCTAssertFalse(requiresTag)
    }

    func testMissingAccountDoesNotExistAndRequiresNoTag() async throws {
        transport.answer("account_info", .rpcError(code: "actNotFound"))

        let exists = try await Kit.doesAccountExist(address: Fixtures.address, rpcApiProvider: provider)
        let requiresTag = try await Kit.requiresDestinationTag(address: Fixtures.address, rpcApiProvider: provider)

        XCTAssertFalse(exists)
        XCTAssertFalse(requiresTag)
    }

    func testFundedAccountExists() async throws {
        transport.answer("account_info", .ok(Fixtures.accountInfo()))

        let exists = try await Kit.doesAccountExist(address: Fixtures.address, rpcApiProvider: provider)

        XCTAssertTrue(exists)
    }

    // an unknown answer is not "no flag": the caller decides what a failed lookup means
    func testNodeFailureIsThrown() async {
        transport.answer("account_info", .error(URLError(.timedOut)))

        do {
            _ = try await Kit.requiresDestinationTag(address: Fixtures.address, rpcApiProvider: provider)
            XCTFail("expected an error")
        } catch {}
    }

    // only the classic address is accepted, as by the instance methods; the tag an X-address packs
    // is the caller's to resolve first
    func testXAddressIsRejectedWithoutACall() async {
        do {
            _ = try await Kit.requiresDestinationTag(address: "XVLhHMPHU98es4dbozjVtdWzVrDjtV18pX8yuPT7y4xaEHi", rpcApiProvider: provider)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AddressError, .invalidFormat)
        }
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testEmptyUrlListIsAnError() async {
        do {
            _ = try await Kit.requiresDestinationTag(address: Fixtures.address, rpcUrls: [])
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is NoEndpointAvailable)
        }
    }
}
