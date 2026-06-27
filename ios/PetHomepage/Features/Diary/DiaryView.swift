// ios/PetHomepage/Features/Diary/DiaryView.swift
import SwiftUI
import UIKit

/// The Diary tab: dated journal entries (date + note + photos) and a photo grid aggregating
/// every photo for the pet (diary entries + records).
struct DiaryView: View {
    @State private var model: DiaryViewModel
    @State private var section: DiarySection = .entries
    @State private var editTarget: DiaryEntry?
    @State private var addEntry = false
    private let store: DiaryStore

    enum DiarySection: String, CaseIterable, Identifiable {
        case entries = "Entries"
        case photos = "Photos"
        var id: String { rawValue }
    }

    init(store: DiaryStore) {
        self.store = store
        _model = State(initialValue: DiaryViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    HeroHeader(
                        title: "Diary",
                        subtitle: section.rawValue,
                        systemImage: "book.fill"
                    )
                    Picker("Section", selection: $section) {
                        ForEach(DiarySection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)

                    if section == .entries { entriesList } else { photoGrid }
                }
                if section == .entries { addButton }
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { model.load() }
            .sheet(isPresented: $addEntry, onDismiss: { model.load() }) {
                DiaryEntryEditView(store: store, editing: nil)
            }
            .sheet(item: $editTarget, onDismiss: { model.load() }) { entry in
                DiaryEntryEditView(store: store, editing: entry)
            }
        }
    }

    /// Floating add button — bottom-trailing, matching the Timeline.
    private var addButton: some View {
        Button { addEntry = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Theme.primary, in: Circle())
                .shadow(color: Theme.primary.opacity(0.35), radius: 12, y: 5)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var entriesList: some View {
        if model.entries.isEmpty {
            ContentUnavailableView(
                "No entries yet",
                systemImage: "book",
                description: Text("Tap + to write your first diary entry.")
            )
        } else {
            List {
                ForEach(model.entries) { entry in
                    Button { editTarget = entry } label: { entryRow(entry) }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.bg)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { model.deleteEntry(entry) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date, format: .dateTime.weekday().month().day().year())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.primary)
            if let note = entry.note, !note.isEmpty {
                Text(note).font(.body).foregroundStyle(Theme.ink).lineLimit(3)
            }
            let photos = entry.photoArray
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            if let data = photo.imageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var photoGrid: some View {
        if model.photos.isEmpty {
            ContentUnavailableView(
                "No photos yet",
                systemImage: "photo.on.rectangle",
                description: Text("Photos from diary entries and records show up here.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(model.photos) { photo in
                        if let data = photo.imageData, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollContentBackground(.hidden)
        }
    }
}
