// ios/PetHomepageUITests/TabBarTests.swift
import XCTest

final class TabBarTests: UITestCase {
    /// The four tabs exist. (Capture lives in the Timeline + menu now, not the tab bar.)
    func testTabBarLayout() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for label in ["Home", "Timeline", "Schedule", "Care Team"] {
            XCTAssertTrue(tabBar.buttons[label].waitForExistence(timeout: 5), "\(label) tab missing")
        }
        XCTAssertFalse(tabBar.buttons["Capture"].exists, "Capture pseudo-tab should be gone")
    }
}
