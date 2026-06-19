// ios/PetHomepageTests/NotificationAuthorizationTests.swift
import XCTest
@testable import PetHomepage

final class NotificationAuthorizationTests: XCTestCase {
    func testBootstrapRequestsAuthorizationAndReturnsGrant() async {
        let fake = FakeNotificationScheduler()
        fake.authorizationResult = true

        let granted = await NotificationBootstrap.requestAuthorizationIfNeeded(using: fake)

        XCTAssertTrue(granted)
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }

    func testBootstrapReturnsFalseWhenDenied() async {
        let fake = FakeNotificationScheduler()
        fake.authorizationResult = false

        let granted = await NotificationBootstrap.requestAuthorizationIfNeeded(using: fake)

        XCTAssertFalse(granted)
        XCTAssertEqual(fake.authorizationRequestCount, 1)
    }
}
