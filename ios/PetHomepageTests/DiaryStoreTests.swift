// ios/PetHomepageTests/DiaryStoreTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class DiaryStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: DiaryStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        store = DiaryStore(context: context, petStore: petStore)
    }

    private func allPhotos() throws -> [Photo] {
        let request = Photo.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    private func makeMedication() throws -> Medication {
        let medStore = MedicationStore(context: context, petStore: petStore)
        return try medStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                   scheduleTime: Date(), startedAt: Date(), endedAt: nil, refillDueAt: nil)
    }

    func testMedicationPhotoIsAttachedAndPetScoped() throws {
        let med = try makeMedication()
        try store.addPhoto(toMedication: med, imageData: Data([0x1]))

        XCTAssertEqual(med.photoArray.count, 1)
        XCTAssertEqual(try allPhotos().count, 1, "record photos are attached to the pet")
        XCTAssertEqual(try allPhotos().first?.medication, med)
        XCTAssertNotNil(try allPhotos().first?.pet)
    }

    func testDeletePhotoRemovesIt() throws {
        let med = try makeMedication()
        let photo = try store.addPhoto(toMedication: med, imageData: Data([0x9]))
        XCTAssertEqual(try allPhotos().count, 1)

        try store.deletePhoto(photo)

        XCTAssertTrue(try allPhotos().isEmpty)
    }
}
