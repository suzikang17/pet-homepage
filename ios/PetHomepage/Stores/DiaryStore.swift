// ios/PetHomepage/Stores/DiaryStore.swift
import CoreData

/// Photo-attach service for the not-yet-unified record entities (vet visits, vaccinations,
/// medications), pet-scoped. Diary entries and activity/dose photos now go through LogStore.
final class DiaryStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    // MARK: Photos

    @discardableResult
    func addPhoto(toVetVisit visit: VetVisit, imageData: Data, caption: String? = nil, createdAt: Date = Date()) throws -> Photo {
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.imageData = imageData
        photo.caption = caption
        photo.createdAt = createdAt
        photo.pet = try petStore.ensurePet()
        photo.vetVisit = visit
        try context.save()
        return photo
    }

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

    @discardableResult
    func addPhoto(toVaccination vax: Vaccination, imageData: Data, caption: String? = nil, createdAt: Date = Date()) throws -> Photo {
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.imageData = imageData
        photo.caption = caption
        photo.createdAt = createdAt
        photo.pet = try petStore.ensurePet()
        photo.vaccination = vax
        try context.save()
        return photo
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }
}
