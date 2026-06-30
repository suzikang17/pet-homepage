import XCTest
@testable import PetHomepage

final class ActivityCategoryTests: XCTestCase {
    func testDisplayNamesAreTitleCased() {
        XCTAssertEqual(ActivityCategory.care.displayName, "Care")
        XCTAssertEqual(ActivityCategory.feeding.displayName, "Feeding")
        XCTAssertEqual(ActivityCategory.other.displayName, "Other")
    }

    func testUnknownRawValueFallsBackToOther() {
        XCTAssertEqual(ActivityCategory(rawValueOrOther: "care"), .care)
        XCTAssertEqual(ActivityCategory(rawValueOrOther: "nonsense"), .other)
    }

    func testAllCasesHaveASymbol() {
        for category in ActivityCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty)
        }
    }
}
