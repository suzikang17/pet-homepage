// ios/PetHomepageUITests/TabBarTests.swift
import XCTest

final class TabBarTests: UITestCase {
    /// The four real tabs exist. (Capture is a pseudo-tab — selecting it always snaps back to
    /// the prior tab and opens the camera flow instead — but its tab bar button still exists.)
    func testTabBarLayout() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for label in ["Home", "Timeline", "Capture", "Care Team"] {
            XCTAssertTrue(tabBar.buttons[label].waitForExistence(timeout: 5), "\(label) tab missing")
        }
    }
}
