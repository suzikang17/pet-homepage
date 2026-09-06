// ios/PetHomepageUITests/GalleryAndLogTests.swift
import XCTest

/// The two halves of the old Timeline tab, now separate: the Gallery tab (photos only) and the
/// Schedule tab's Log subtab (the record stream). The Stream/Photos segmented picker these tests
/// used to drive no longer exists — that split was the thing being undone.
final class GalleryAndLogTests: UITestCase {
    /// After a capture save the photo appears in the Gallery, and the same record appears as a
    /// row in the Log. One capture, two surfaces, no toggle between them.
    func testCapturedRecordAppearsInBothGalleryAndLog() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        openCapture()
        let save = app.buttons["sheet.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["Gallery"].tap()
        XCTAssertTrue(app.images["timelinePhotoCell"].waitForExistence(timeout: 5))

        openLog()
        XCTAssertTrue(app.staticTexts["Diary entry"].waitForExistence(timeout: 5))
    }

    /// Tapping a gallery cell opens the full-screen pager (counter + chrome); the close button
    /// returns to the grid.
    func testPhotoCellOpensFullScreenViewer() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        openCapture()
        let save = app.buttons["sheet.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["Gallery"].tap()
        let cell = app.images["timelinePhotoCell"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 5))
        let close = app.buttons["photoPagerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.images["timelinePhotoCell"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The Schedule "+" is one merged menu: the routine one-off task AND every record type that
    /// used to live on the Timeline's floating button. "Scan a record" is omitted because
    /// extraction is unconfigured under `--uitest`.
    func testMergedPlusMenuEntries() {
        let app = launchApp()
        app.tabBars.buttons["Schedule"].tap()

        let addButton = app.buttons["heroAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        for label in ["New one-off task", "Note", "Activity", "Medication", "Symptom",
                      "Health record"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5),
                          "\(label) missing from + menu")
        }
        XCTAssertFalse(app.buttons["Scan a record"].exists,
                       "Scan a record should be absent — extraction isn't configured under --uitest")
    }

    /// All three subtabs exist and each keeps the "+". The menu's CONTENTS are asserted once
    /// above — opening and dismissing a SwiftUI menu three times over is flaky for no extra
    /// signal, and the "+" is built once for the whole header regardless of subtab.
    func testEverySubtabExistsAndKeepsTheAddButton() {
        let app = launchApp()
        app.tabBars.buttons["Schedule"].tap()
        let picker = app.segmentedControls["scheduleTabPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        for subtab in ["Log", "Today", "Upcoming"] {
            XCTAssertTrue(picker.buttons[subtab].waitForExistence(timeout: 5),
                          "\(subtab) subtab missing")
            picker.buttons[subtab].tap()
            XCTAssertTrue(app.buttons["heroAddButton"].waitForExistence(timeout: 5),
                          "+ missing on \(subtab)")
        }
    }
}
