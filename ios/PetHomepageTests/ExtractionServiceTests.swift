// ios/PetHomepageTests/ExtractionServiceTests.swift
import XCTest
@testable import PetHomepage

/// In-test URLProtocol that returns a canned response for any request — so the
/// production URLSessionExtractionService is exercised WITHOUT any real network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data = Data()
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastSecretHeader: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastSecretHeader = request.value(forHTTPHeaderField: "x-extract-secret")
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
            StubURLProtocol.lastRequestBody = data
        } else {
            StubURLProtocol.lastRequestBody = request.httpBody
        }
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: StubURLProtocol.statusCode,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ExtractionServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.responseData = Data()
        StubURLProtocol.statusCode = 200
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.lastSecretHeader = nil
    }

    override func tearDown() {
        StubURLProtocol.responseData = Data()
        StubURLProtocol.statusCode = 200
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.lastSecretHeader = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testPostsJSONBodyWithSecretHeaderAndDecodesResults() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseData = Data("""
        {
          "ok": true,
          "results": [
            {
              "event_type": "vaccination",
              "occurred_at": "2026-03-01T10:00:00Z",
              "title": "Rabies",
              "fields": { "vaccine_name": "Rabies", "administered_at": "2026-03-01" }
            }
          ]
        }
        """.utf8)

        let service = URLSessionExtractionService(
            config: ExtractionConfig(
                endpoint: URL(string: "https://example.com/api/extract")!,
                secret: "extract-secret-123"
            ),
            session: makeSession()
        )

        let results = try await service.extract(
            fileData: Data("pdfbytes".utf8),
            mimeType: "application/pdf",
            fileName: "rabies.pdf",
            note: "from vet",
            date: "2026-03-01"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.eventType, .vaccination)
        XCTAssertEqual(StubURLProtocol.lastSecretHeader, "extract-secret-123")

        let body = StubURLProtocol.lastRequestBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["mimeType"] as? String, "application/pdf")
        XCTAssertEqual(json?["fileName"] as? String, "rabies.pdf")
        XCTAssertEqual(json?["note"] as? String, "from vet")
        XCTAssertEqual(json?["date"] as? String, "2026-03-01")
        // content is base64 of the file bytes
        XCTAssertEqual(json?["content"] as? String, Data("pdfbytes".utf8).base64EncodedString())
    }

    func testThrowsOnNon200() async {
        StubURLProtocol.statusCode = 500
        StubURLProtocol.responseData = Data("{}".utf8)
        let service = URLSessionExtractionService(
            config: ExtractionConfig(endpoint: URL(string: "https://example.com/api/extract")!, secret: "s"),
            session: makeSession()
        )
        do {
            _ = try await service.extract(fileData: Data(), mimeType: "application/pdf")
            XCTFail("expected error")
        } catch let error as ExtractionError {
            XCTAssertEqual(error, .badStatus(500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFakeReturnsCannedResultsAndRecordsInput() async throws {
        let canned = ExtractionResult.decoder // reuse decoder to build a value
        let json = Data("""
        { "event_type": "general", "occurred_at": "2026-04-01T12:00:00Z", "title": "x", "fields": { "summary": "s" } }
        """.utf8)
        let result = try canned.decode(ExtractionResult.self, from: json)
        let fake = FakeExtractionService(results: [result])

        let out = try await fake.extract(fileData: Data("z".utf8), mimeType: "image/jpeg")

        XCTAssertEqual(out, [result])
        XCTAssertEqual(fake.lastMimeType, "image/jpeg")
        XCTAssertEqual(fake.lastFileData, Data("z".utf8))
    }

    // MARK: - emptyResults

    func testThrowsEmptyResultsWhenServerReturnsEmptyArray() async {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseData = Data("""
        { "results": [] }
        """.utf8)
        let service = URLSessionExtractionService(
            config: ExtractionConfig(endpoint: URL(string: "https://example.com/api/extract")!, secret: "s"),
            session: makeSession()
        )
        do {
            _ = try await service.extract(fileData: Data("pdf".utf8), mimeType: "application/pdf")
            XCTFail("expected ExtractionError.emptyResults")
        } catch let error as ExtractionError {
            XCTAssertEqual(error, .emptyResults)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - FakeExtractionService error injection

    func testFakeThrowsCannedError() async {
        let fake = FakeExtractionService(errorToThrow: ExtractionError.emptyResults)
        do {
            _ = try await fake.extract(fileData: Data(), mimeType: "application/pdf")
            XCTFail("expected canned error to be thrown")
        } catch let error as ExtractionError {
            XCTAssertEqual(error, .emptyResults)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertNotNil(fake.lastMimeType)
    }
}
