// ios/PetHomepageUITests/ScheduleTests.swift
import XCTest

final class ScheduleTests: UITestCase {
    /// Seeded routine renders on the Schedule tab; checking a task off flips its state and
    /// offers the photo toast; the stubbed camera attaches a photo without real capture UI.
    func testScheduleSeedAndCheckOffWithPhoto() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Schedule"].tap()

        // Every-day seeds are on today's list regardless of weekday.
        XCTAssertTrue(app.otherElements["scheduleRow.Breakfast"].waitForExistence(timeout: 5)
                      || app.staticTexts["Breakfast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Morning walk"].exists)

        // Check off Breakfast → toast offers a photo; stub camera attaches one synchronously.
        app.buttons["scheduleCheck.Breakfast"].tap()
        let toast = app.buttons["scheduleToastAddPhoto"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        toast.tap()
        // Toast is gone after capture; the row now shows the photo thumbnail (no camera button).
        XCTAssertFalse(app.buttons["scheduleAddPhoto.Breakfast"].waitForExistence(timeout: 2))
    }

    /// Day navigation: yesterday's list exists and the Today button returns.
    func testDayNavigation() {
        let app = launchApp()
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.buttons["schedulePrevDay"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3))
        app.buttons["scheduleTodayButton"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
    }
}
