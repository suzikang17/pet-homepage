// ios/PetHomepage/Features/VetVisits/VetVisitDetailViewModel.swift
import Foundation
import Observation

@Observable
final class VetVisitDetailViewModel {
    let visit: VetVisit
    var recommendations: [VetRecommendation] = []
    var newRecommendationText: String = ""

    private let recommendationStore: VetRecommendationStore

    init(visit: VetVisit, recommendationStore: VetRecommendationStore) {
        self.visit = visit
        self.recommendationStore = recommendationStore
        try? load()
    }

    func load() throws {
        recommendations = try recommendationStore.recommendations(for: visit)
    }

    func addRecommendation() throws {
        let text = newRecommendationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try recommendationStore.create(text: text, date: Date(), vetVisit: visit)
        newRecommendationText = ""
        try load()
    }
}
