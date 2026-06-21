// ios/PetHomepageTests/PairDeviceViewModelTests.swift
import XCTest
@testable import PetHomepage

/// A PairingService that returns a canned result or throws — no network.
private final class FakePairingService: PairingService {
    var result: PairResult?
    var error: Error?
    private(set) var lastCode: String?
    private(set) var lastEndpoint: URL?

    func pair(code: String, endpoint: URL) async throws -> PairResult {
        lastCode = code
        lastEndpoint = endpoint
        if let error { throw error }
        return result ?? PairResult(token: "tok", pushEndpoint: "https://x/mirror/push")
    }
}

final class PairDeviceViewModelTests: XCTestCase {
    func testManualClaimSuccessAppliesPairingAndMarksPaired() async {
        let service = FakePairingService()
        service.result = PairResult(token: "abc-123", pushEndpoint: "https://deploy.convex.site/mirror/push")
        var applied: (token: String, endpoint: String)?
        let model = PairDeviceViewModel(service: service) { applied = ($0, $1) }

        model.manualCode = "k7p2 9qx4"
        await model.claimManual()

        XCTAssertEqual(model.state, .paired)
        XCTAssertEqual(applied?.token, "abc-123")
        XCTAssertEqual(applied?.endpoint, "https://deploy.convex.site/mirror/push")
        // Manual entry uses the build-time default endpoint.
        XCTAssertEqual(service.lastEndpoint, PairingDefaults.pairEndpoint)
        XCTAssertEqual(service.lastCode, "k7p2 9qx4")
    }

    func testEmptyManualCodeDoesNothing() async {
        let service = FakePairingService()
        let model = PairDeviceViewModel(service: service) { _, _ in }
        model.manualCode = "   "
        await model.claimManual()
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(service.lastCode)
    }

    func testInvalidCodeSurfacesFriendlyError() async {
        let service = FakePairingService()
        service.error = PairingError.badStatus(401)
        var applied = false
        let model = PairDeviceViewModel(service: service) { _, _ in applied = true }

        model.manualCode = "BADCODE1"
        await model.claimManual()

        XCTAssertFalse(applied)
        guard case .failed(let message) = model.state else {
            return XCTFail("expected failed state, got \(model.state)")
        }
        XCTAssertTrue(message.contains("invalid or expired"))
    }

    func testScannedQRParsesCodeAndEndpoint() async {
        let service = FakePairingService()
        let model = PairDeviceViewModel(service: service) { _, _ in }

        await model.claimScanned(#"{"e":"https://deploy.convex.site","c":"K7P29QX4"}"#)

        XCTAssertEqual(service.lastCode, "K7P29QX4")
        XCTAssertEqual(service.lastEndpoint, URL(string: "https://deploy.convex.site/mirror/pair"))
    }

    func testBareQRPayloadTreatedAsCodeWithDefaultEndpoint() {
        let parsed = PairDeviceViewModel.parseQR("PLAINCODE")
        XCTAssertEqual(parsed.code, "PLAINCODE")
        XCTAssertEqual(parsed.endpoint, PairingDefaults.pairEndpoint)
    }
}
