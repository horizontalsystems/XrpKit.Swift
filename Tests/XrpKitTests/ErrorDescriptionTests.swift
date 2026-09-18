import XCTest
@testable import XrpKit

final class ErrorDescriptionTests: XCTestCase {
    func testRejectedCarriesEngineResultAndMessage() {
        let error = SendError.rejected(engineResult: "temREDUNDANT", message: "The transaction is redundant.")
        XCTAssertEqual(error.localizedDescription, "temREDUNDANT: The transaction is redundant.")
        XCTAssertEqual(SendError.rejected(engineResult: "tecPATH_DRY", message: nil).localizedDescription, "tecPATH_DRY")
    }

    func testOtherSendErrorsAreReadable() {
        XCTAssertEqual(SendError.accountNotFound.localizedDescription, "Account is not activated")
        XCTAssertEqual(SendError.signerMismatch.localizedDescription, "Signer does not match the kit address")
        XCTAssertFalse(SendError.memoTooLong.localizedDescription.contains("memoTooLong"))
    }

    func testRpcErrorCarriesCode() {
        XCTAssertEqual(RpcError(code: "actNotFound", message: "Account not found.").localizedDescription, "actNotFound: Account not found.")
        XCTAssertEqual(RpcError(code: "actNotFound", message: nil).localizedDescription, "actNotFound")
        XCTAssertEqual(NoEndpointAvailable(underlying: nil).localizedDescription, "No endpoint available")
    }
}
