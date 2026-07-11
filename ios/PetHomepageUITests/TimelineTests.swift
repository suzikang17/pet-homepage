// ios/PetHomepageUITests/TimelineTests.swift
import XCTest

final class TimelineTests: UITestCase {
    /// After a capture save, Photos mode shows at least one photo cell; Stream mode shows the
    /// same record back as a list row.
    func testTimelineStreamPhotosToggle() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()
        let save = app.buttons["sheet.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["Timeline"].tap()
        let toggle = app.segmentedControls["timelineViewModePicker"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        toggle.buttons["Photos"].tap()
        XCTAssertTrue(app.images["timelinePhotoCell"].waitForExistence(timeout: 5))

        toggle.buttons["Stream"].tap()
        XCTAssertTrue(app.staticTexts["Diary entry"].waitForExistence(timeout: 5))
    }

    /// Tapping a gallery cell opens the full-screen pager (counter + chrome); the close button
    /// returns to the grid.
    func testPhotoCellOpensFullScreenViewer() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()
        let save = app.buttons["sheet.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["Timeline"].tap()
        let toggle = app.segmentedControls["timelineViewModePicker"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.buttons["Photos"].tap()

        let cell = app.images["timelinePhotoCell"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 5))
        let close = app.buttons["photoPagerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.images["timelinePhotoCell"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The Timeline "+" menu offers every quick-add record type but omits "Scan a record" —
    /// extraction is unconfigured under `--uitest`.
    func testPlusMenuEntries() {
        let app = launchApp()
        app.tabBars.buttons["Timeline"].tap()

        let addButton = app.buttons["timelineAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        for label in ["Note", "Activity", "Medication", "Symptom", "Health record"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "\(label) missing from + menu")
        }
        XCTAssertFalse(app.buttons["Scan a record"].exists,
                       "Scan a record should be absent — extraction isn't configured under --uitest")
    }
}
