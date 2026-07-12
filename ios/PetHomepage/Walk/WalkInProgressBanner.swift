// ios/PetHomepage/Walk/WalkInProgressBanner.swift
import SwiftUI

/// UI-facing wrapper over WalkSessionStore: the store is plain (readable from notification
/// handlers), this adds observation so SwiftUI surfaces refresh when a session starts/ends.
@Observable
final class WalkSessionModel {
    private let sessions: WalkSessionStore
    private let petName: () -> String
    private(set) var active: WalkSession?

    init(sessions: WalkSessionStore, petName: @escaping () -> String = { "Your pet" }) {
        self.sessions = sessions
        self.petName = petName
        refresh()
    }

    /// Re-reads persisted state — call on appear/foreground so sessions started from
    /// notification actions (other launches) show up.
    func refresh() { active = sessions.active }

    func startRoutine(taskID: UUID) {
        _ = try? sessions.startRoutine(taskID: taskID, source: .manual)
        refresh()
        WalkLiveActivityController.sync(active: active, petName: petName())
    }

    func end() {
        _ = try? sessions.end()
        refresh()
        WalkLiveActivityController.sync(active: active, petName: petName())
    }

    func cancel() {
        sessions.cancel()
        refresh()
        WalkLiveActivityController.sync(active: active, petName: petName())
    }
}

/// Card shown while a walk session runs: elapsed timer + End, with Cancel behind a
/// confirmation so a fat-finger can't discard a real walk.
struct WalkInProgressBanner: View {
    let model: WalkSessionModel
    @State private var confirmCancel = false

    var body: some View {
        if let session = model.active {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Walk in progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(session.startedAt, style: .timer)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Button("End") { model.end() }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
            }
            .padding(12)
            .background(Theme.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onLongPressGesture { confirmCancel = true }
            .confirmationDialog("Discard this walk?", isPresented: $confirmCancel,
                                titleVisibility: .visible) {
                Button("Discard without logging", role: .destructive) { model.cancel() }
                Button("Keep walking", role: .cancel) {}
            }
            .accessibilityIdentifier("walkInProgressBanner")
        }
    }
}
