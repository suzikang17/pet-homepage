// ios/PetHomepage/Features/Timeline/GalleryView.swift
import SwiftUI

/// Every photo of the pet, newest first, grouped by month and laid out as masonry.
///
/// This tab used to be "Timeline" and carried two things behind a segmented picker: the record
/// stream and this grid. They shared a data source, not a question — so the stream moved to the
/// Schedule tab, next to Today and Upcoming, and what is left is a gallery that does one thing.
struct GalleryView: View {
    @State private var model: TimelineViewModel
    private let services: TimelineServices
    /// Opens the capture flow (camera / stub / library fallback), owned by ContentView.
    private let onCapture: (() -> Void)?
    /// Opens the photo-library picker directly, owned by ContentView.
    private let onImport: (() -> Void)?

    init(services: TimelineServices, onCapture: (() -> Void)? = nil,
         onImport: (() -> Void)? = nil) {
        self.services = services
        self.onCapture = onCapture
        self.onImport = onImport
        _model = State(initialValue: TimelineViewModel(
            medicationStore: services.medicationStore,
            logStore: services.logStore
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HeroHeader(
                    title: "Gallery",
                    subtitle: subtitle,
                    systemImage: "photo.on.rectangle",
                    addMenu: addMenu
                )
                content
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { model.load() }
        }
    }

    private var subtitle: String {
        let count = model.photos.count
        return count == 1 ? "1 photo" : "\(count) photos"
    }

    /// Adding a PHOTO, not a record — record types moved to the Schedule header's "+" along with
    /// the stream. Nil when neither capture route is wired (previews, tests), which leaves the
    /// header with no "+" at all rather than an empty menu.
    private var addMenu: AnyView? {
        guard onCapture != nil || onImport != nil else { return nil }
        return AnyView(
            Group {
                if let onCapture {
                    Button { onCapture() } label: { Label("Take photo", systemImage: "camera") }
                }
                if let onImport {
                    Button { onImport() } label: {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if model.photos.isEmpty {
            ContentUnavailableView(
                "No photos yet",
                systemImage: "photo.on.rectangle",
                description: Text("Photos from diary entries and records show up here.")
            )
        } else {
            PhotoGalleryView(photos: model.photos)
        }
    }
}
