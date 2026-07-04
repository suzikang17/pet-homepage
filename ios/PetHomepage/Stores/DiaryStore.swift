// ios/PetHomepage/Stores/DiaryStore.swift
import CoreData

/// Photo-attach service for Medication (a definition, so its photos hang off the med itself,
/// not a LogEntry). Every occurrence photo — diary, activity, dose, vaccine, vet, marker — goes
/// through LogStore.addPhoto(to:) instead.
final class DiaryStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    // MARK: Photos

    @discardableResult
    func addPhoto(toMedication med: Medication, imageData: Data, caption: String? = nil, createdAt: Date = Date()) throws -> Photo {
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.imageData = imageData
        photo.caption = caption
        photo.createdAt = createdAt
        photo.pet = try petStore.ensurePet()
        photo.medication = med
        try context.save()
        return photo
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }
}
