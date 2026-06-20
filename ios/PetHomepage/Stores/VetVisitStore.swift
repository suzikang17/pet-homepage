// ios/PetHomepage/Stores/VetVisitStore.swift
import CoreData

/// CRUD for vet visits, scoped to the single current pet (v1). Mirrors MedicationStore.
final class VetVisitStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func create(occurredAt: Date,
                clinicName: String?,
                vetName: String?,
                reason: String?,
                diagnosis: String?,
                treatmentNotes: String?,
                nextVisitDate: Date?) throws -> VetVisit {
        let visit = VetVisit(context: context)
        visit.id = UUID()
        visit.occurredAt = occurredAt
        visit.clinicName = clinicName
        visit.vetName = vetName
        visit.reason = reason
        visit.diagnosis = diagnosis
        visit.treatmentNotes = treatmentNotes
        visit.nextVisitDate = nextVisitDate
        visit.pet = try petStore.currentPet()
        try context.save()
        return visit
    }

    /// All vet visits for the current pet, most recent first.
    func visits() throws -> [VetVisit] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = VetVisit.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]
        return try context.fetch(request)
    }

    func update(_ visit: VetVisit,
                occurredAt: Date,
                clinicName: String?,
                vetName: String?,
                reason: String?,
                diagnosis: String?,
                treatmentNotes: String?,
                nextVisitDate: Date?) throws {
        visit.occurredAt = occurredAt
        visit.clinicName = clinicName
        visit.vetName = vetName
        visit.reason = reason
        visit.diagnosis = diagnosis
        visit.treatmentNotes = treatmentNotes
        visit.nextVisitDate = nextVisitDate
        try context.save()
    }

    func delete(_ visit: VetVisit) throws {
        context.delete(visit)
        try context.save()
    }

    /// The `occurredAt` of the most recent vet visit, or nil — drives the vet-cadence reminder.
    func mostRecentVisitDate() throws -> Date? {
        try visits().first?.occurredAt
    }
}
