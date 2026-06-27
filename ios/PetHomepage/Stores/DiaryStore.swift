// ios/PetHomepage/Stores/DiaryStore.swift
import CoreData

/// CRUD for diary entries + their photos, pet-scoped. `allPhotos()` returns every photo for the
/// pet (diary + record photos), which powers the Diary tab's photo grid.
final class DiaryStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    // MARK: Entries

    @discardableResult
    func createEntry(date: Date = Date(), note: String?) throws -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.note = note
        entry.pet = try petStore.ensurePet()
        try context.save()
        return entry
    }

    /// All diary entries for the current pet, newest first.
    func entries() throws -> [DiaryEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    func updateEntry(_ entry: DiaryEntry, date: Date, note: String?) throws {
        entry.date = date
        entry.note = note
        try context.save()
    }

    func deleteEntry(_ entry: DiaryEntry) throws {
        context.delete(entry)
        try context.save()
    }

    // MARK: Photos

    @discardableResult
    func addPhoto(to entry: DiaryEntry, imageData: Data, caption: String? = nil, createdAt: Date = Date()) throws -> Photo {
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.imageData = imageData
        photo.caption = caption
        photo.createdAt = createdAt
        photo.pet = try petStore.ensurePet()
        photo.diaryEntry = entry
        try context.save()
        return photo
    }

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

    /// Every photo for the current pet (diary + record photos), newest first.
    func allPhotos() throws -> [Photo] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = Photo.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }
}
