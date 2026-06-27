// ios/PetHomepage/Features/Diary/DiaryEntryEditViewModel.swift
import Foundation
import Observation

@Observable
final class DiaryEntryEditViewModel {
    var date: Date
    var note: String
    var pendingPhotos: [Data] = []   // newly picked, saved on confirm
    var existingPhotos: [Photo] = [] // already attached (edit mode)

    private let store: DiaryStore
    private let editing: DiaryEntry?

    init(store: DiaryStore, editing: DiaryEntry?) {
        self.store = store
        self.editing = editing
        date = editing?.date ?? Date()
        note = editing?.note ?? ""
        existingPhotos = editing?.photoArray ?? []
    }

    var photoCount: Int { existingPhotos.count + pendingPhotos.count }

    /// An entry needs at least a note or a photo.
    var isValid: Bool { !note.trimmingCharacters(in: .whitespaces).isEmpty || photoCount > 0 }

    func addPickedPhoto(_ data: Data) { pendingPhotos.append(data) }

    func removePending(at index: Int) {
        if pendingPhotos.indices.contains(index) { pendingPhotos.remove(at: index) }
    }

    func deleteExisting(_ photo: Photo) {
        try? store.deletePhoto(photo)
        existingPhotos.removeAll { $0 == photo }
    }

    func save() throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry: DiaryEntry
        if let editing {
            try store.updateEntry(editing, date: date, note: trimmed.isEmpty ? nil : trimmed)
            entry = editing
        } else {
            entry = try store.createEntry(date: date, note: trimmed.isEmpty ? nil : trimmed)
        }
        for data in pendingPhotos {
            try store.addPhoto(to: entry, imageData: data)
        }
    }
}
