// ios/PetHomepageUITests/CaptureFlowTests.swift
import XCTest

/// Covers the capture -> review-and-tag sheet flow: the presentation-layer surface that unit
/// tests can't reach (camera cover collapsing, sheet-handoff races, etc).
final class CaptureFlowTests: UITestCase {
    /// Tapping Capture with the stub camera lands on the review sheet; saving with the default
    /// "Note only" tag creates a diary entry, visible under Timeline's Diary filter.
    func testCaptureNoteOnlySave() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()

        let save = app.buttons["sheet.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["Timeline"].tap()
        tapChip(app.buttons["timelineChip.Diary"], in: app.scrollViews["timelineChipsStrip"])
        XCTAssertTrue(app.staticTexts["Diary entry"].waitForExistence(timeout: 5))
    }

    /// Tagging the capture with an activity chip ("Bath") logs an activity occurrence instead of
    /// a diary entry.
    func testCaptureTagActivity() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()

        let bathChip = app.buttons["Bath"]
        XCTAssertTrue(bathChip.waitForExistence(timeout: 5))
        bathChip.tap()
        app.buttons["sheet.save"].tap()

        app.tabBars.buttons["Timeline"].tap()
        tapChip(app.buttons["timelineChip.Activities"], in: app.scrollViews["timelineChipsStrip"])
        XCTAssertTrue(app.staticTexts["Bath"].waitForExistence(timeout: 5))
    }

    /// The marker chip's value field gates Save: empty/non-numeric keeps it disabled, a valid
    /// number enables it, and the saved reading shows up under Timeline's Health filter.
    func testCaptureMarkerValidation() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()

        let markerChip = app.buttons["captureMarkerChip"]
        XCTAssertTrue(markerChip.waitForExistence(timeout: 5))
        markerChip.tap()

        let weightItem = app.buttons["Weight"]
        XCTAssertTrue(weightItem.waitForExistence(timeout: 5))
        weightItem.tap()

        let valueField = app.textFields["markerValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        let save = app.buttons["sheet.save"]
        XCTAssertFalse(save.isEnabled, "Save should be disabled with no marker value")

        valueField.tap()
        valueField.typeText("12.4")
        XCTAssertTrue(save.isEnabled, "Save should enable once a numeric value is entered")
        save.tap()

        app.tabBars.buttons["Timeline"].tap()
        let healthChip = app.buttons["timelineChip.Health"]
        XCTAssertTrue(healthChip.waitForExistence(timeout: 5))
        healthChip.tap()
        XCTAssertTrue(app.staticTexts["Weight: 12.4 lb"].waitForExistence(timeout: 5))
    }

    /// A "Vaccine" records chip hands off: the review sheet closes and the Vaccine editor
    /// appears with the captured photo already staged as a pending photo.
    func testCaptureVaccineHandoff() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Capture"].tap()

        let vaccineChip = app.buttons["Vaccine"]
        XCTAssertTrue(vaccineChip.waitForExistence(timeout: 5))
        vaccineChip.tap()

        // "Lot number" only exists in the Vaccine editor — waiting on it proves the review sheet
        // dismissed and the handoff editor actually presented (the staged-sheet race under test).
        XCTAssertTrue(app.textFields["Lot number"].waitForExistence(timeout: 10),
                      "Vaccine editor should appear after the review sheet hands off")
        XCTAssertTrue(app.staticTexts["Vaccine"].exists, "Vaccine editor title should be visible")
        XCTAssertTrue(app.images["pendingPhotoThumb"].waitForExistence(timeout: 5),
                      "The staged capture photo should show as a pending photo in the editor")
    }
}
