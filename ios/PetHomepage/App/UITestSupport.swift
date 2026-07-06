// ios/PetHomepage/App/UITestSupport.swift
import CoreData
import UIKit

/// Deterministic launch seams for XCUITest runs, gated entirely behind `--uitest` /
/// `--uitest-stub-camera` launch arguments so ordinary launches are byte-for-byte unchanged.
/// See `PetHomepageUITests` for the tests that rely on these.
enum UITestSupport {
    /// In-memory Core Data store, no CloudKit, deterministic seed data, no notification prompt.
    static let isUITest = ProcessInfo.processInfo.arguments.contains("--uitest")
    /// The camera pseudo-tab stages a generated photo instead of presenting the real
    /// camera/library picker, landing straight on the review-and-tag sheet.
    static let stubCamera = ProcessInfo.processInfo.arguments.contains("--uitest-stub-camera")

    /// Seeds a deterministic pet ("Sandy") + one active medication ("Apoquel") so UI tests have
    /// something to look at with zero manual setup. Runs once, synchronously, against the
    /// in-memory store right after it's created — before any view reads from it. Idempotent
    /// no-op if a pet already exists (defensive; every `--uitest` launch starts from a fresh
    /// `/dev/null` store, so this always creates fresh data in practice).
    static func seed(context: NSManagedObjectContext) {
        let petStore = PetStore(context: context)
        guard (try? petStore.currentPet()) == nil else { return }

        guard let pet = try? petStore.createPet(name: "Sandy", species: "dog") else { return }
        petStore.setActivePet(pet)

        let medicationStore = MedicationStore(context: context, petStore: petStore)
        let now = Date()
        _ = try? medicationStore.create(
            drugName: "Apoquel",
            dosage: "16mg",
            frequency: "daily",
            scheduleTime: now,
            startedAt: now,
            endedAt: nil,
            refillDueAt: nil
        )
        // Activity-type defaults are seeded by ContentView's existing `.task` (it runs on every
        // launch, idempotently) — no need to duplicate that here.
    }

    /// A 400x300 solid-violet JPEG standing in for a camera capture.
    static func stubPhotoJPEG() -> Data? {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let violet = UIColor(red: 0.42, green: 0.30, blue: 0.95, alpha: 1.0)
        let image = renderer.image { _ in
            violet.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}
