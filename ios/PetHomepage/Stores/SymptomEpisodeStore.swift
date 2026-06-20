// ios/PetHomepage/Stores/SymptomEpisodeStore.swift
import CoreData

/// Symptom episodes (the container for "start tracking a digestive issue"),
/// scoped to the single current pet (v1). Follows the MedicationStore pattern.
final class SymptomEpisodeStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore

    init(context: NSManagedObjectContext, petStore: PetStore) {
        self.context = context
        self.petStore = petStore
    }

    @discardableResult
    func start(category: SymptomCategory,
               title: String?,
               startedAt: Date = Date()) throws -> SymptomEpisode {
        let episode = SymptomEpisode(context: context)
        episode.id = UUID()
        episode.category = category
        episode.title = title
        episode.startedAt = startedAt
        episode.resolvedAt = nil
        episode.status = .active
        episode.pet = try petStore.currentPet()
        try context.save()
        return episode
    }

    /// All episodes for the current pet, most recently started first.
    func episodes() throws -> [SymptomEpisode] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = SymptomEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return try context.fetch(request)
    }

    func activeEpisodes() throws -> [SymptomEpisode] {
        try episodes(withStatus: .active)
    }

    func resolvedEpisodes() throws -> [SymptomEpisode] {
        try episodes(withStatus: .resolved)
    }

    private func episodes(withStatus status: EpisodeStatus) throws -> [SymptomEpisode] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = SymptomEpisode.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND statusRaw == %@", pet, status.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return try context.fetch(request)
    }

    func resolve(_ episode: SymptomEpisode, at date: Date = Date()) throws {
        episode.status = .resolved
        episode.resolvedAt = date
        try context.save()
    }

    func update(_ episode: SymptomEpisode, category: SymptomCategory, title: String?) throws {
        episode.category = category
        episode.title = title
        try context.save()
    }

    func delete(_ episode: SymptomEpisode) throws {
        context.delete(episode)
        try context.save()
    }
}
