// ios/PetHomepage/Features/Diary/DiaryViewModel.swift
import Foundation
import Observation

@Observable
final class DiaryViewModel {
    var entries: [DiaryEntry] = []
    var photos: [Photo] = []

    private let store: DiaryStore

    init(store: DiaryStore) {
        self.store = store
        load()
    }

    func load() {
        entries = (try? store.entries()) ?? []
        photos = (try? store.allPhotos()) ?? []
    }

    func deleteEntry(_ entry: DiaryEntry) {
        try? store.deleteEntry(entry)
        load()
    }

    func deletePhoto(_ photo: Photo) {
        try? store.deletePhoto(photo)
        load()
    }
}
