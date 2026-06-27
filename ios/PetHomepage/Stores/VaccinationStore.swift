// ios/PetHomepage/Stores/VaccinationStore.swift
import CoreData

/// CRUD for vaccinations, scoped to the single current pet (v1).
/// Mirrors MedicationStore; adds "last given" / "next due" helpers per vaccine name.
final class VaccinationStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func create(vaccineName: String,
                administeredAt: Date,
                nextDueAt: Date?,
                lotNumber: String?,
                administeredBy: String?) throws -> Vaccination {
        let vax = Vaccination(context: context)
        vax.id = UUID()
        vax.vaccineName = vaccineName
        vax.administeredAt = administeredAt
        vax.nextDueAt = nextDueAt
        vax.lotNumber = lotNumber
        vax.administeredBy = administeredBy
        vax.pet = try petStore.ensurePet()
        try context.save()
        return vax
    }

    /// All vaccinations for the current pet, most recently administered first.
    func vaccinations() throws -> [Vaccination] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = Vaccination.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "administeredAt", ascending: false)]
        return try context.fetch(request)
    }

    func update(_ vaccination: Vaccination,
                vaccineName: String,
                administeredAt: Date,
                nextDueAt: Date?,
                lotNumber: String?,
                administeredBy: String?) throws {
        vaccination.vaccineName = vaccineName
        vaccination.administeredAt = administeredAt
        vaccination.nextDueAt = nextDueAt
        vaccination.lotNumber = lotNumber
        vaccination.administeredBy = administeredBy
        try context.save()
    }

    func delete(_ vaccination: Vaccination) throws {
        context.delete(vaccination)
        try context.save()
    }

    /// Most-recent `administeredAt` for a given vaccine name on the current pet, or nil.
    func lastGiven(vaccineName: String) throws -> Date? {
        guard let pet = try petStore.currentPet() else { return nil }
        let request = Vaccination.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND vaccineName == %@", pet, vaccineName)
        request.sortDescriptors = [NSSortDescriptor(key: "administeredAt", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.administeredAt ?? nil
    }

    /// Earliest `nextDueAt` for a given vaccine name on the current pet, or nil.
    func nextDue(vaccineName: String) throws -> Date? {
        guard let pet = try petStore.currentPet() else { return nil }
        let request = Vaccination.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND vaccineName == %@ AND nextDueAt != nil", pet, vaccineName)
        request.sortDescriptors = [NSSortDescriptor(key: "nextDueAt", ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.nextDueAt ?? nil
    }
}
