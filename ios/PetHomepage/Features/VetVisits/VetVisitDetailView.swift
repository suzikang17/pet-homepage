// ios/PetHomepage/Features/VetVisits/VetVisitDetailView.swift
import SwiftUI

struct VetVisitDetailView: View {
    @State private var model: VetVisitDetailViewModel
    @State private var photos: [Photo] = []
    private let visit: LogEntry
    private let logStore: LogStore

    init(visit: LogEntry, recommendationStore: VetRecommendationStore, logStore: LogStore) {
        _model = State(initialValue: VetVisitDetailViewModel(visit: visit, recommendationStore: recommendationStore))
        self.visit = visit
        self.logStore = logStore
    }

    var body: some View {
        Form {
            Section("Visit") {
                LabeledContent("Date", value: model.visit.performedAt.formatted(date: .abbreviated, time: .omitted))
                if let clinic = model.visit.clinicName { LabeledContent("Clinic", value: clinic) }
                if let careVet = model.visit.veterinarian { LabeledContent("Veterinarian", value: careVet.name) }
                if let vet = model.visit.vetName { LabeledContent("Vet", value: vet) }
                if let reason = model.visit.title { LabeledContent("Reason", value: reason) }
                if let diagnosis = model.visit.diagnosis { LabeledContent("Diagnosis", value: diagnosis) }
                if let notes = model.visit.treatmentNotes { LabeledContent("Treatment", value: notes) }
            }
            PhotoStripSection(
                photos: photos,
                onAdd: { try? logStore.addPhoto(to: visit, imageData: $0) },
                onDelete: { try? logStore.deletePhoto($0); photos = visit.photoArray },
                onReload: { photos = visit.photoArray }
            )
            Section("Recommendations") {
                ForEach(model.recommendations, id: \.id) { rec in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.text)
                        Text(rec.date.formatted(date: .abbreviated, time: .omitted))
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
        .brandSheet()
        .onAppear { photos = visit.photoArray }
    }
}
