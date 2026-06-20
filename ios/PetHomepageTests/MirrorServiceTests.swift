// ios/PetHomepageTests/MirrorServiceTests.swift
import XCTest
@testable import PetHomepage

/// In-test URLProtocol returning a canned response and capturing the POST body — so the
/// production URLSessionMirrorService is exercised WITHOUT any real network.
final class MirrorStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastHTTPMethod: String?
    nonisolated(unsafe) static var lastAuthorization: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MirrorStubURLProtocol.lastHTTPMethod = request.httpMethod
        MirrorStubURLProtocol.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            MirrorStubURLProtocol.lastRequestBody = data
        } else {
            MirrorStubURLProtocol.lastRequestBody = request.httpBody
        }
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: MirrorStubURLProtocol.statusCode,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class MirrorServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MirrorStubURLProtocol.statusCode = 200
        MirrorStubURLProtocol.lastRequestBody = nil
        MirrorStubURLProtocol.lastHTTPMethod = nil
        MirrorStubURLProtocol.lastAuthorization = nil
    }

    override func tearDown() {
        MirrorStubURLProtocol.statusCode = 200
        MirrorStubURLProtocol.lastRequestBody = nil
        MirrorStubURLProtocol.lastHTTPMethod = nil
        MirrorStubURLProtocol.lastAuthorization = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MirrorStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func sampleSnapshot() -> MirrorSnapshot {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return MirrorSnapshot(
            schemaVersion: 1, generatedAt: date,
            pet: PetSnapshot(id: UUID(), name: "Sandy", species: "dog",
                             breed: nil, dob: nil, adoptionDate: nil),
            medications: [], vaccinations: [], vetVisits: [],
            unlinkedRecommendations: [], healthMarkers: [], symptomEpisodes: []
        )
    }

    func testPushPostsEnvelopeWithBearerToken() async throws {
        let service = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: URL(string: "https://example.com/mirror/push")!,
                token: "tok-abc-123"
            ),
            session: makeSession()
        )

        try await service.push(sampleSnapshot())

        XCTAssertEqual(MirrorStubURLProtocol.lastHTTPMethod, "POST")
        XCTAssertEqual(MirrorStubURLProtocol.lastAuthorization, "Bearer tok-abc-123")

        let body = MirrorStubURLProtocol.lastRequestBody ?? Data()
        let envelope = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(envelope?["schema_version"] as? Int, 1)
        let snapshot = envelope?["snapshot"] as? [String: Any]
        let pet = snapshot?["pet"] as? [String: Any]
        XCTAssertEqual(pet?["name"] as? String, "Sandy")
    }

    func testPushOmitsAuthorizationWhenTokenMissing() async throws {
        let service = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: URL(string: "https://example.com/mirror/push")!,
                token: nil
            ),
            session: makeSession()
        )
        try await service.push(sampleSnapshot())
        XCTAssertNil(MirrorStubURLProtocol.lastAuthorization)
    }

    func testPushThrowsOnNon200() async {
        MirrorStubURLProtocol.statusCode = 500
        let service = URLSessionMirrorService(
            config: MirrorConfig(endpoint: URL(string: "https://example.com/mirror/push")!, token: "tok"),
            session: makeSession()
        )
        do {
            try await service.push(sampleSnapshot())
            XCTFail("expected MirrorError.badStatus")
        } catch let error as MirrorError {
            XCTAssertEqual(error, .badStatus(500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFakeRecordsPushedSnapshots() async throws {
        let fake = FakeMirrorService()
        let snapshot = sampleSnapshot()
        try await fake.push(snapshot)
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertEqual(fake.pushedSnapshots, [snapshot])
    }

    func testFakeThrowsCannedError() async {
        let fake = FakeMirrorService(errorToThrow: MirrorError.badStatus(503))
        do {
            try await fake.push(sampleSnapshot())
            XCTFail("expected canned error")
        } catch let error as MirrorError {
            XCTAssertEqual(error, .badStatus(503))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertTrue(fake.pushedSnapshots.isEmpty)
    }
}
