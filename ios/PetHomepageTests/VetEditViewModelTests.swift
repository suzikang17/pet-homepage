// ios/PetHomepageTests/VetEditViewModelTests.swift
import Contacts
import CoreData
import XCTest
@testable import PetHomepage

final class VetEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: VeterinarianStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        store = VeterinarianStore(context: context, petStore: petStore)
    }

    override func tearDownWithError() throws {
        context = nil
        petStore = nil
        store = nil
    }

    func testApplyContactFillsFields() {
        let vm = VetEditViewModel(store: store, editing: nil)
        let contact = CNMutableContact()
        contact.givenName = "Ruth"
        contact.familyName = "Vet"
        contact.organizationName = "Maple Vet"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain,
                                               value: CNPhoneNumber(stringValue: "555-1234"))]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ruth@maple.vet" as NSString)]
        contact.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: "maple.vet" as NSString)]
        let addr = CNMutablePostalAddress()
        addr.street = "1 Main St"
        addr.city = "Townsville"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: addr)]

        vm.apply(contact: contact)

        XCTAssertEqual(vm.name, "Ruth Vet")
        XCTAssertEqual(vm.clinic, "Maple Vet")
        XCTAssertEqual(vm.phone, "555-1234")
        XCTAssertEqual(vm.email, "ruth@maple.vet")
        XCTAssertEqual(vm.website, "maple.vet")
        XCTAssertTrue(vm.address.contains("1 Main St"))
    }

    func testApplyThenSavePersistsImportedVet() throws {
        let vm = VetEditViewModel(store: store, editing: nil)
        let contact = CNMutableContact()
        contact.givenName = "Ruth"
        vm.apply(contact: contact)

        try vm.save()

        XCTAssertEqual(try store.veterinarians().first?.name, "Ruth")
    }
}
