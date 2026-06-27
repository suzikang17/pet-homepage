// ios/PetHomepage/Stores/HealthMarkerStore.swift
import CoreData

/// Generic health markers (weight, appetite, energy, water, temperature, other),
/// scoped to the single current pet (v1). Follows the MedicationStore pattern.
final class HealthMarkerStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func create(markerType: MarkerType,
                value: Double,
                unit: String?,
                recordedAt: Date = Date()) throws -> HealthMarker {
        let marker = HealthMarker(context: context)
        marker.id = UUID()
        marker.markerType = markerType
        marker.value = value
        marker.unit = unit
        marker.recordedAt = recordedAt
        marker.pet = try petStore.ensurePet()
        try context.save()
        return marker
    }

    /// All markers for the current pet, most recent first.
    func markers() throws -> [HealthMarker] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = HealthMarker.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: false)]
        return try context.fetch(request)
    }

    /// The most-recently recorded marker of a given type, or nil if none.
    func latest(of markerType: MarkerType) throws -> HealthMarker? {
        guard let pet = try petStore.currentPet() else { return nil }
        let request = HealthMarker.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND markerTypeRaw == %@", pet, markerType.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// A time-ordered (oldest-first) series of one marker type — drives a simple trend.
    func series(of markerType: MarkerType) throws -> [HealthMarker] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = HealthMarker.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND markerTypeRaw == %@", pet, markerType.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: true)]
        return try context.fetch(request)
    }

    func delete(_ marker: HealthMarker) throws {
        context.delete(marker)
        try context.save()
    }
}
