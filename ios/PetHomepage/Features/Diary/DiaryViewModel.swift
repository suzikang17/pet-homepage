// ios/PetHomepage/Features/Diary/DiaryViewModel.swift
import Foundation
import Observation

@Observable
final class DiaryViewModel {
    var entries: [LogEntry] = []
    var photos: [Photo] = []

    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
        load()
    }

    func load() {
        entries = (try? logStore.diaryEntries()) ?? []
        photos = (try? logStore.allPhotos()) ?? []
    }

    func deleteEntry(_ entry: LogEntry) {
        try? logStore.delete(entry)
        load()
    }

    func deletePhoto(_ photo: Photo) {
        try? logStore.deletePhoto(photo)
        load()
    }
}
