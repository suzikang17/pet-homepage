// ios/PetHomepageUITests/PetSwitcherTests.swift
import XCTest

final class PetSwitcherTests: UITestCase {
    /// Home avatar -> "Add pet…" creates + activates a new pet (hero updates); avatar ->
    /// "Switch pet…" lists every pet with a checkmark on the active one; switching back to the
    /// seeded pet updates the hero again.
    func testPetSwitcherAddAndSwitch() {
        let app = launchApp()

        // The app now launches on the Schedule tab; the pet switcher lives on Home.
        app.tabBars.buttons["Home"].tap()

        let avatar = app.buttons["heroAvatarButton"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        avatar.tap()

        // confirmationDialog buttons don't reliably carry SwiftUI accessibility identifiers —
        // match their (static) labels instead. The action sheet exposes each action twice in
        // the hierarchy, so take firstMatch.
        let addPetAction = app.buttons["Add pet…"].firstMatch
        XCTAssertTrue(addPetAction.waitForExistence(timeout: 5))
        addPetAction.tap()

        let nameField = app.textFields["addPetNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Milo")
        app.buttons["sheet.save"].tap()

        // HeroHeader uppercases the subtitle string itself, so the rendered/accessible text is
        // "MILO", not "Milo".
        XCTAssertTrue(app.staticTexts["MILO"].waitForExistence(timeout: 5))

        avatar.tap()
        let switchPetAction = app.buttons["Switch pet…"].firstMatch
        XCTAssertTrue(switchPetAction.waitForExistence(timeout: 5))
        switchPetAction.tap()

        let sandyRow = app.buttons["petSwitcherRow.Sandy"]
        let miloRow = app.buttons["petSwitcherRow.Milo"]
        XCTAssertTrue(sandyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(miloRow.waitForExistence(timeout: 5))
        // SwiftUI flattens the row Button's children, so the checkmark is surfaced through the
        // row's accessibility value (see PetSwitcherView).
        XCTAssertEqual(miloRow.value as? String, "active",
                       "Milo is the active pet, so its row should carry the checkmark")
        XCTAssertNotEqual(sandyRow.value as? String, "active")

        // SwiftUI List-row buttons inside a detented sheet can swallow the first synthesized
        // tap (the sheet stays up and the action never fires) — retry by coordinate, then via
        // the row's child text, before failing.
        sandyRow.tap()
        let switcherBar = app.navigationBars["Switch pet"]
        if !app.staticTexts["SANDY"].waitForExistence(timeout: 3), switcherBar.exists {
            sandyRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !app.staticTexts["SANDY"].waitForExistence(timeout: 3), switcherBar.exists {
            app.staticTexts["Sandy"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["SANDY"].waitForExistence(timeout: 5),
                      "Hero should show SANDY after switching back")
    }
}
