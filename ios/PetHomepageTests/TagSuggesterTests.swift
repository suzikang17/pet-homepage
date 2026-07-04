// ios/PetHomepageTests/TagSuggesterTests.swift
import XCTest
import CoreData
import UIKit
@testable import PetHomepage

final class TagSuggesterTests: XCTestCase {

    // MARK: - Pure matcher

    func testMatchesProductPackagingAgainstMedicationName() {
        let index = TagSuggester.bestMatch(
            ocrText: "HEARTGARD® PLUS (ivermectin) Chewables",
            candidateNames: ["Apoquel", "Heartgard", "Bath"]
        )
        XCTAssertEqual(index, 1)
    }

    func testDoesNotMatchSubstringInsideALongerWord() {
        let index = TagSuggester.bestMatch(
            ocrText: "bathroom cleaner supplies",
            candidateNames: ["Bath"]
        )
        XCTAssertNil(index)
    }

    func testMatchesMultiWordCandidateAfterNormalization() {
        let index = TagSuggester.bestMatch(
            ocrText: "K9 FLEA AND TICK COLLAR",
            candidateNames: ["Flea & tick", "Deworming"]
        )
        XCTAssertEqual(index, 0)
    }

    func testNoMatchReturnsNil() {
        let index = TagSuggester.bestMatch(
            ocrText: "completely unrelated text here",
            candidateNames: ["Apoquel", "Heartgard"]
        )
        XCTAssertNil(index)
    }

    func testEmptyCandidatesReturnsNil() {
        let index = TagSuggester.bestMatch(ocrText: "Heartgard Plus", candidateNames: [])
        XCTAssertNil(index)
    }

    func testCaseAndDiacriticInsensitive() {
        let index = TagSuggester.bestMatch(
            ocrText: "HÉARTGARD plus chewables",
            candidateNames: ["heartgard"]
        )
        XCTAssertEqual(index, 0)
    }

    // MARK: - End-to-end (real Vision OCR in the simulator)

    func testSuggestOCRsRenderedTextAndMatches() async throws {
        let photo = try XCTUnwrap(Self.renderPhoto(text: "HEARTGARD PLUS"))
        let index = await TagSuggester.suggest(photo: photo, candidateNames: ["Apoquel", "Heartgard"])
        XCTAssertEqual(index, 1, "Vision OCR should read the rendered label and match it to Heartgard")
    }

    /// Renders `text` as large black text on a white background and JPEG-encodes it, so Vision has
    /// an easy, high-contrast target to OCR.
    static func renderPhoto(text: String, size: CGSize = CGSize(width: 800, height: 400)) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 96),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            let textRect = CGRect(x: 20, y: size.height / 2 - 60, width: size.width - 40, height: 120)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.95)
    }
}

// MARK: - VM integration

@MainActor
final class TagSuggesterViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var activityStore: ActivityStore!
    private var medicationStore: MedicationStore!
    private var logStore: LogStore!
    private var fake: FakeNotificationScheduler!
    private var sched: DueReminderScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        activityStore = ActivityStore(context: context, petStore: petStore)
        medicationStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        sched = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian), hour: 9, minute: 0)
    }

    private func makeModel(photo: Data) -> CaptureReviewViewModel {
        CaptureReviewViewModel(
            photo: photo,
            logStore: logStore,
            activityStore: activityStore,
            medicationStore: medicationStore,
            dueScheduler: sched
        )
    }

    func testRunSuggestionPreSelectsMatchingMedicationChip() async throws {
        let med = try medicationStore.create(
            drugName: "Heartgard",
            dosage: "1 chew",
            frequency: "Monthly",
            scheduleTime: Date(),
            startedAt: Date(timeIntervalSinceNow: -1000),
            endedAt: nil,
            refillDueAt: nil
        )
        let photo = try XCTUnwrap(TagSuggesterTests.renderPhoto(text: "HEARTGARD PLUS"))
        let vm = makeModel(photo: photo)

        await vm.runSuggestion()

        XCTAssertEqual(vm.tag, .medication(med))
        XCTAssertEqual(vm.suggestedTag, .medication(med))
    }

    func testRunSuggestionDoesNotOverrideAUserPickedTag() async throws {
        _ = try medicationStore.create(
            drugName: "Heartgard",
            dosage: "1 chew",
            frequency: "Monthly",
            scheduleTime: Date(),
            startedAt: Date(timeIntervalSinceNow: -1000),
            endedAt: nil,
            refillDueAt: nil
        )
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let photo = try XCTUnwrap(TagSuggesterTests.renderPhoto(text: "HEARTGARD PLUS"))
        let vm = makeModel(photo: photo)

        vm.pick(.activity(type))
        await vm.runSuggestion()

        XCTAssertEqual(vm.tag, .activity(type))
    }
}
