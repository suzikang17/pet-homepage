// ios/PetHomepage/Stores/VetRecommendationStore.swift
import CoreData

/// Logs recommendations a vet gave. Each may link to a VetVisit (vetVisit != nil)
/// or stand alone (vetVisit == nil — "the vet said X over the phone").
final class VetRecommendationStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func create(text: String, date: Date = Date(), vetVisit: VetVisit?) throws -> VetRecommendation {
        let rec = VetRecommendation(context: context)
        rec.id = UUID()
        rec.text = text
        rec.date = date
        rec.vetVisit = vetVisit
        try context.save()
        return rec
    }

    /// Recommendations attached to a specific visit, most recent first.
    func recommendations(for visit: VetVisit) throws -> [VetRecommendation] {
        let request = VetRecommendation.fetchRequest()
        request.predicate = NSPredicate(format: "vetVisit == %@", visit)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    /// Recommendations not linked to any visit, most recent first.
    func unlinkedRecommendations() throws -> [VetRecommendation] {
        let request = VetRecommendation.fetchRequest()
        request.predicate = NSPredicate(format: "vetVisit == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request)
    }

    func update(_ recommendation: VetRecommendation, text: String, date: Date) throws {
        recommendation.text = text
        recommendation.date = date
        try context.save()
    }

    func delete(_ recommendation: VetRecommendation) throws {
        context.delete(recommendation)
        try context.save()
    }
}
