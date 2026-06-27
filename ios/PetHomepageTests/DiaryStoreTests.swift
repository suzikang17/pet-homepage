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

    func testCreateEntryListsNewestFirstAndScopesToPet() throws {
        try store.createEntry(date: Date(timeIntervalSince1970: 100), note: "Older")
        try store.createEntry(date: Date(timeIntervalSince1970: 500), note: "Newer")

        let entries = try store.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.note, "Newer")
        XCTAssertEqual(entries.first?.pet?.name, "Your pet")
    }

    func testAddPhotoLinksToEntryAndAppearsInAllPhotos() throws {
        let entry = try store.createEntry(date: Date(), note: "Walk")
        try store.addPhoto(to: entry, imageData: Data([0x1, 0x2, 0x3]))

        XCTAssertEqual(entry.photoArray.count, 1)
        XCTAssertEqual(try store.allPhotos().count, 1)
        XCTAssertEqual(try store.allPhotos().first?.diaryEntry, entry)
    }

    func testVetVisitPhotoAppearsInAllPhotos() throws {
        let vetVisitStore = VetVisitStore(context: context, petStore: petStore)
        let visit = try vetVisitStore.create(occurredAt: Date(), clinicName: "Bayside", vetName: nil,
                                             reason: "checkup", diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try store.addPhoto(toVetVisit: visit, imageData: Data([0x9]))

        XCTAssertEqual(visit.photoArray.count, 1)
        XCTAssertEqual(try store.allPhotos().count, 1, "record photos join the pet-wide grid")
        XCTAssertEqual(try store.allPhotos().first?.vetVisit, visit)
    }

    func testMedicationAndVaccinePhotosJoinAllPhotos() throws {
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
        XCTAssertEqual(try store.allPhotos().count, 2, "med + vaccine photos join the pet-wide grid")
    }

    func testDeleteEntryCascadesItsPhotos() throws {
        let entry = try store.createEntry(date: Date(), note: "Walk")
        try store.addPhoto(to: entry, imageData: Data([0x1]))
        XCTAssertEqual(try store.allPhotos().count, 1)

        try store.deleteEntry(entry)

        XCTAssertTrue(try store.entries().isEmpty)
        XCTAssertTrue(try store.allPhotos().isEmpty)
    }
}
