// ios/PetHomepage/Stores/MedicationStore.swift
import CoreData

/// CRUD for medications, scoped to the single current pet (v1).
final class MedicationStore {
    let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func create(drugName: String,
                dosage: String,
                frequency: String,
                scheduleTime: Date,
                startedAt: Date,
                endedAt: Date? = nil,
                refillDueAt: Date?) throws -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.drugName = drugName
        med.dosage = dosage
        med.frequency = frequency
        med.scheduleTime = scheduleTime
        med.startedAt = startedAt
        med.endedAt = endedAt
        med.refillDueAt = refillDueAt
        med.pet = try petStore.ensurePet()
        try context.save()
        return med
    }

    /// All medications for the current pet, sorted by drug name.
    func medications() throws -> [Medication] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "drugName", ascending: true)]
        return try context.fetch(request)
    }

    func update(_ medication: Medication,
                drugName: String,
                dosage: String,
                frequency: String,
                scheduleTime: Date,
                startedAt: Date,
                endedAt: Date?,
                refillDueAt: Date?) throws {
        medication.drugName = drugName
        medication.dosage = dosage
        medication.frequency = frequency
        medication.scheduleTime = scheduleTime
        medication.startedAt = startedAt
        medication.endedAt = endedAt
        medication.refillDueAt = refillDueAt
        try context.save()
    }

    func delete(_ medication: Medication) throws {
        context.delete(medication)
        try context.save()
    }
}
