// ios/PetHomepageUITests/UITestCase.swift
import XCTest

/// Shared base for every UI test: each test launches its own fresh app process against the
/// in-memory store (`--uitest`), so tests never depend on execution order or leftover state from
/// another test.
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches the app with `--uitest` (in-memory store, deterministic "Sandy" + "Apoquel"
    /// seed, no notification prompt) plus any extra launch arguments, e.g.
    /// `--uitest-stub-camera` to stage a generated photo instead of the real camera/library
    /// picker.
    @discardableResult
    func launchApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"] + extra
        app.launch()
        self.app = app
        return app
    }

    /// Opens the capture flow via its home: the Timeline tab's + menu → "Take photo".
    /// (The former Capture pseudo-tab was removed.)
    func openCapture() {
        app.tabBars.buttons["Timeline"].tap()
        let add = app.buttons["timelineAddButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "timeline add button missing")
        add.tap()
        let takePhoto = app.buttons["Take photo"]
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 5), "Take photo menu entry missing")
        takePhoto.tap()
    }

    /// Taps a chip inside a horizontal chip strip, swiping the strip left first when the chip is
    /// currently off-screen (trailing chips like Diary/Activities aren't tappable until the
    /// strip scrolls). Uses frame math, not `isHittable` — hittability queries throw
    /// "activation point invalid" for off-screen elements instead of returning false.
    func tapChip(_ chip: XCUIElement, in strip: XCUIElement) {
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "chip not found")
        let window = app.windows.firstMatch.frame
        var swipes = 0
        while swipes < 4 {
            let frame = chip.frame
            if frame.minX >= window.minX && frame.maxX <= window.maxX { break }
            strip.swipeLeft()
            swipes += 1
        }
        chip.tap()
    }
}
