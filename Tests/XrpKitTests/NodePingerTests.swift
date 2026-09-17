import XCTest
@testable import XrpKit

final class NodePingerTests: XCTestCase {
    private let url = URL(string: "https://xrplcluster.com/")!

    private func response(state: String = "full", seq: Any = 90_000_000, networkId: Any? = nil, status: String = "success") -> Any {
        var state: RpcJson = ["server_state": state, "validated_ledger": ["seq": seq, "reserve_base": 1_000_000, "reserve_inc": 200_000]]
        if let networkId {
            state["network_id"] = networkId
        }
        return ["result": ["state": state, "status": status]]
    }

    func testFullyStateOnExpectedNetworkIsValid() {
        let result = NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(networkId: 0), network: .mainNet)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.height, 90_000_000)
        XCTAssertEqual(result.responseTime, 0.1)
    }

    func testMissingNetworkIdIsAccepted() {
        XCTAssertTrue(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(), network: .mainNet).isValid)
    }

    func testOtherNetworkIsInvalid() {
        XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(networkId: 1), network: .mainNet).isValid)
        XCTAssertTrue(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(networkId: 1), network: .testNet).isValid)
    }

    func testNotSyncedStateIsInvalid() {
        for state in ["connected", "syncing", "tracking", "disconnected"] {
            XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(state: state), network: .mainNet).isValid, state)
        }
        XCTAssertTrue(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(state: "proposing"), network: .mainNet).isValid)
    }

    func testMalformedResponsesAreInvalidWithoutTrap() {
        XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: ["result": ["status": "error", "error": "noNetwork"]], network: .mainNet).isValid)
        XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: ["unexpected": true], network: .mainNet).isValid)
        XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(seq: "not a number"), network: .mainNet).isValid)
        XCTAssertFalse(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(seq: -5), network: .mainNet).isValid)
        XCTAssertEqual(NodePinger.result(url: url, responseTime: 0.1, jsonObject: response(seq: 0), network: .mainNet).height, 0)
    }
}
