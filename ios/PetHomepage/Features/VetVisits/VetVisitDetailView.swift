// ios/PetHomepage/Features/VetVisits/VetVisitDetailView.swift
import SwiftUI

struct VetVisitDetailView: View {
    @State private var model: VetVisitDetailViewModel

    init(visit: VetVisit, recommendationStore: VetRecommendationStore) {
        _model = State(initialValue: VetVisitDetailViewModel(visit: visit, recommendationStore: recommendationStore))
    }

    var body: some View {
        Form {
            Section("Visit") {
                LabeledContent("Date", value: model.visit.occurredAtValue.formatted(date: .abbreviated, time: .omitted))
                if let clinic = model.visit.clinicName { LabeledContent("Clinic", value: clinic) }
                if let vet = model.visit.vetName { LabeledContent("Vet", value: vet) }
                if let reason = model.visit.reason { LabeledContent("Reason", value: reason) }
                if let diagnosis = model.visit.diagnosis { LabeledContent("Diagnosis", value: diagnosis) }
                if let notes = model.visit.treatmentNotes { LabeledContent("Treatment", value: notes) }
            }
            Section("Recommendations") {
                ForEach(model.recommendations, id: \.objectID) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.text)
                        Text(rec.dateValue.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Add recommendation", text: $model.newRecommendationText)
                    Button("Add") { try? model.addRecommendation() }
                        .disabled(model.newRecommendationText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Visit detail")
    }
}
