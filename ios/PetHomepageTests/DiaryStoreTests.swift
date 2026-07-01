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

    func testVetVisitPhotoAppearsAsPetPhoto() throws {
        let vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        let visit = try vetVisitStore.create(occurredAt: Date(), clinicName: "Bayside", vetName: nil,
                                             reason: "checkup", diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.addPhoto(toVetVisit: visit, imageData: Data([0x9]))

        XCTAssertEqual(visit.photoArray.count, 1)
        XCTAssertEqual(try allPhotos().count, 1, "record photos are attached to the pet")
        XCTAssertEqual(try allPhotos().first?.vetVisit, visit)
    }

    func testMedicationAndVaccinePhotosAreAttached() throws {
        let medStore = MedicationStore(context: context, petStore: petStore)
        let med = try medStore.create(drugName: "Apoquel", dosage: "16mg", frequency: "daily",
                                      scheduleTime: Date(), startedAt: Date(), endedAt: nil, refillDueAt: nil)
        try store.addPhoto(toMedication: med, imageData: Data([0x1]))

        let vaxStore = VaccinationStore(context: context, petStore: petStore)
        let vax = try vaxStore.create(vaccineName: "Rabies", administeredAt: Date(),
                                      nextDueAt: nil, lotNumber: nil, administeredBy: nil)
        try store.addPhoto(toVaccination: vax, imageData: Data([0x2]))

        XCTAssertEqual(med.photoArray.count, 1)
        XCTAssertEqual(vax.photoArray.count, 1)
        XCTAssertEqual(try allPhotos().count, 2, "med + vaccine photos are attached")
    }

    func testDeletePhotoRemovesIt() throws {
        let vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        let visit = try vetVisitStore.create(occurredAt: Date(), clinicName: "Bayside", vetName: nil,
                                             reason: "checkup", diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let photo = try store.addPhoto(toVetVisit: visit, imageData: Data([0x9]))
        XCTAssertEqual(try allPhotos().count, 1)

        try store.deletePhoto(photo)

        XCTAssertTrue(try allPhotos().isEmpty)
    }
}
