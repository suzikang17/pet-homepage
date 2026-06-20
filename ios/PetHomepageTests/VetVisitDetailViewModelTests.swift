// ios/PetHomepageTests/VetVisitDetailViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class VetVisitDetailViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var visitStore: VetVisitStore!
    private var recStore: VetRecommendationStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        visitStore = VetVisitStore(context: context, petStore: petStore)
        recStore = VetRecommendationStore(context: context)
    }

    func testLoadShowsRecommendationsForVisit() throws {
        let visit = try visitStore.create(occurredAt: Date(timeIntervalSince1970: 1),
                                          clinicName: nil, vetName: nil, reason: nil,
                                          diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        try recStore.create(text: "Senior food", date: Date(timeIntervalSince1970: 2), vetVisit: visit)
        let vm = VetVisitDetailViewModel(visit: visit, recommendationStore: recStore)

        try vm.load()

        XCTAssertEqual(vm.recommendations.map(\.text), ["Senior food"])
    }

    func testAddRecommendationAppendsAndClearsInput() throws {
        let visit = try visitStore.create(occurredAt: Date(timeIntervalSince1970: 1),
                                          clinicName: nil, vetName: nil, reason: nil,
                                          diagnosis: nil, treatmentNotes: nil, nextVisitDate: nil)
        let vm = VetVisitDetailViewModel(visit: visit, recommendationStore: recStore)
        vm.newRecommendationText = "Recheck in 2 weeks"

        try vm.addRecommendation()

        XCTAssertEqual(vm.recommendations.count, 1)
        XCTAssertEqual(vm.recommendations.first?.text, "Recheck in 2 weeks")
        XCTAssertEqual(vm.newRecommendationText, "")
    }
}
