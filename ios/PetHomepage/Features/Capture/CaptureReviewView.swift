// ios/PetHomepage/Features/Capture/CaptureReviewView.swift
import SwiftUI

/// The review-and-tag sheet shown right after a capture (camera or library fallback): preview the
/// photo, pick what it's of (nothing / an activity / a medication dose), add an optional note and
/// date, then save. Untagged saves become a diary entry; a tag creates the matching log — either
/// way the photo attaches to whichever LogEntry gets created.
struct CaptureReviewView: View {
    @State private var model: CaptureReviewViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void

    init(photo: Data,
         logStore: LogStore,
         activityStore: ActivityStore,
         medicationStore: MedicationStore,
         dueScheduler: DueReminderScheduler,
         onSaved: @escaping () -> Void) {
        _model = State(initialValue: CaptureReviewViewModel(
            photo: photo,
            logStore: logStore,
            activityStore: activityStore,
            medicationStore: medicationStore,
            dueScheduler: dueScheduler
        ))
        self.onSaved = onSaved
    }

    var body: some View {
        BrandFormSheet(
            title: "Capture",
            systemImage: "camera.fill",
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); onSaved(); dismiss() } }
        ) {
            Section {
                photoPreview
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("What's this?") {
                chips
            }
            .listRowInsets(EdgeInsets())

            Section {
                DatePicker("Date", selection: $model.performedAt, displayedComponents: .date)
                TextField("Note", text: $model.note)
            }
        }
        .task { await model.runSuggestion() }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image = UIImage(data: model.photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(16)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // NB: `CaptureTag.none` must be spelled out — a bare `.none` against the optional
                // `suggestedTag` resolves to `Optional.none`, making nil "match" and showing a
                // phantom ✨ on this chip before any suggestion exists.
                chip(title: "Note only", systemImage: "square.and.pencil", active: model.tag == .none, suggested: model.suggestedTag == CaptureTag.none) {
                    model.pick(.none)
                }
                ForEach(model.availableTypes) { type in
                    chip(title: type.name, systemImage: type.iconName, active: model.tag == .activity(type), suggested: model.suggestedTag == .activity(type)) {
                        model.pick(.activity(type))
                    }
                }
                ForEach(model.activeMeds, id: \.id) { med in
                    chip(title: med.drugName, systemImage: "pills", active: model.tag == .medication(med), suggested: model.suggestedTag == .medication(med)) {
                        model.pick(.medication(med))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func chip(title: String, systemImage: String, active: Bool, suggested: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                if suggested {
                    Image(systemName: "sparkles")
                }
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Theme.primary : Color.white, in: Capsule())
                .foregroundStyle(active ? .white : Theme.ink)
                .overlay(Capsule().stroke(Theme.ink.opacity(active ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}
