// ios/PetHomepage/Features/Timeline/PhotoGalleryView.swift
import SwiftUI
import UIKit

/// The Timeline's Photos mode, grown up: a month-grouped gallery of rounded photo cards, and a
/// tap-to-go full-screen pager with pinch/double-tap zoom and caption overlays. Read-only —
/// captions and photos are still edited through each record's editor.
struct PhotoGalleryView: View {
    /// Newest-first, as `LogStore.allPhotos()` returns them.
    let photos: [Photo]

    @State private var viewerIndex: ViewerIndex?

    /// Identifiable wrapper so `.fullScreenCover(item:)` can present "open at photo N".
    private struct ViewerIndex: Identifiable {
        let value: Int
        var id: Int { value }
    }

    /// One month's worth of photos, in display order. Grouping is by consecutive run — the
    /// input is date-sorted, so each month appears exactly once.
    private struct MonthSection: Identifiable {
        let id: String
        var items: [(index: Int, photo: Photo)]
    }

    private var sections: [MonthSection] {
        var result: [MonthSection] = []
        for (index, photo) in photos.enumerated() {
            let title = photo.createdAt.formatted(.dateTime.month(.wide).year())
            if result.last?.id == title {
                result[result.count - 1].items.append((index, photo))
            } else {
                result.append(MonthSection(id: title, items: [(index, photo)]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.id.uppercased())
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.leading, 6)
                        // Two big cells per phone width — the photos are the point of this view.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                                  spacing: 8) {
                            ForEach(section.items, id: \.photo.id) { item in
                                cell(item.photo, index: item.index)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        .scrollContentBackground(.hidden)
        .fullScreenCover(item: $viewerIndex) { start in
            PhotoPagerView(photos: photos, initialIndex: start.value)
        }
    }

    @ViewBuilder
    private func cell(_ photo: Photo, index: Int) -> some View {
        if let data = photo.imageData, let ui = UIImage(data: data) {
            Button {
                viewerIndex = ViewerIndex(value: index)
            } label: {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if photo.caption?.isEmpty == false {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(6)
                        }
                    }
                    .shadow(color: Theme.shadow.opacity(0.08), radius: 6, y: 3)
                    // Keep the identifier the UI test queries (app.images["timelinePhotoCell"]).
                    .accessibilityIdentifier("timelinePhotoCell")
            }
            .buttonStyle(.plain)
        }
    }
}

/// Full-screen, swipeable photo viewer: black stage, page dots off, pinch or double-tap to
/// zoom, single tap toggles the chrome (close button, counter, caption card).
private struct PhotoPagerView: View {
    let photos: [Photo]
    @State private var index: Int
    @State private var showChrome = true
    @Environment(\.dismiss) private var dismiss

    init(photos: [Photo], initialIndex: Int) {
        self.photos = photos
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    ZoomablePhoto(photo: photo) {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showChrome {
                chrome
                    .transition(.opacity)
            }
        }
        .accessibilityIdentifier("photoPager")
    }

    private var current: Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    private var chrome: some View {
        VStack {
            // Top bar: close + position counter, on a scrim so they read over any photo.
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .accessibilityIdentifier("photoPagerClose")
                Spacer()
                Text("\(index + 1) of \(photos.count)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 30)
            .background(
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            )

            Spacer()

            // Bottom card: caption + where the photo came from.
            if let photo = current {
                VStack(alignment: .leading, spacing: 5) {
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                    }
                    Text(sourceLine(for: photo))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    /// "Morning walk · Jul 11, 2026 at 8:04 AM" — the parent record's title (or its kind as a
    /// fallback) plus the moment the photo was taken.
    private func sourceLine(for photo: Photo) -> String {
        let when = photo.createdAt.formatted(date: .abbreviated, time: .shortened)
        let source = photo.logEntry?.title
            ?? photo.logEntry.map { entryKindLabel($0.kind) }
            ?? photo.medication?.drugName
        if let source, !source.isEmpty {
            return "\(source) · \(when)"
        }
        return when
    }

    private func entryKindLabel(_ kind: LogKind) -> String {
        switch kind {
        case .diary: "Diary"
        case .activity: "Activity"
        case .dose: "Medication"
        case .vaccine: "Vaccine"
        case .vet: "Vet visit"
        case .marker: "Health"
        case .symptom: "Symptom"
        case .routine: "Routine"
        }
    }
}

/// One page of the viewer: pinch to zoom (1x–4x), double-tap to toggle 2x, single tap reports
/// up so the pager can toggle its chrome. Zoom resets when the page scrolls off.
private struct ZoomablePhoto: View {
    let photo: Photo
    let onTap: () -> Void

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        if let data = photo.imageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * pinch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { value in
                            scale = min(max(scale * value, 1), 4)
                        }
                )
                // Double-tap BEFORE single-tap so both register (SwiftUI resolves the pair
                // in declaration order).
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        scale = scale > 1 ? 1 : 2
                    }
                }
                .onTapGesture(count: 1) { onTap() }
                .onDisappear { scale = 1 }
        }
    }
}
