// ios/PetHomepage/Features/VetVisits/VetVisitDetailView.swift
import PhotosUI
import SwiftUI
import UIKit

struct VetVisitDetailView: View {
    @State private var model: VetVisitDetailViewModel
    @State private var photos: [Photo] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    private let visit: VetVisit
    private let diaryStore: DiaryStore

    init(visit: VetVisit, recommendationStore: VetRecommendationStore, diaryStore: DiaryStore) {
        _model = State(initialValue: VetVisitDetailViewModel(visit: visit, recommendationStore: recommendationStore))
        self.visit = visit
        self.diaryStore = diaryStore
    }

    var body: some View {
        Form {
            Section("Visit") {
                LabeledContent("Date", value: model.visit.occurredAt.formatted(date: .abbreviated, time: .omitted))
                if let clinic = model.visit.clinicName { LabeledContent("Clinic", value: clinic) }
                if let careVet = model.visit.veterinarian { LabeledContent("Veterinarian", value: careVet.name) }
                if let vet = model.visit.vetName { LabeledContent("Vet", value: vet) }
                if let reason = model.visit.reason { LabeledContent("Reason", value: reason) }
                if let diagnosis = model.visit.diagnosis { LabeledContent("Diagnosis", value: diagnosis) }
                if let notes = model.visit.treatmentNotes { LabeledContent("Treatment", value: notes) }
            }
            Section("Photos") {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add photos", systemImage: "photo.on.rectangle")
                }
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                if let data = photo.imageData, let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button { delete(photo) } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .black.opacity(0.55))
                                                    .font(.system(size: 18))
                                            }
                                            .padding(3)
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
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
        .onChange(of: pickerItems) { _, items in loadPicked(items) }
    }

    private func delete(_ photo: Photo) {
        try? diaryStore.deletePhoto(photo)
        photos = visit.photoArray
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { continue }
                let scaled = ui.preparingThumbnail(of: CGSize(width: 1600, height: 1600)) ?? ui
                if let jpeg = scaled.jpegData(compressionQuality: 0.8) {
                    await MainActor.run { _ = try? diaryStore.addPhoto(toVetVisit: visit, imageData: jpeg) }
                }
            }
            await MainActor.run {
                photos = visit.photoArray
                pickerItems = []
            }
        }
    }
}
