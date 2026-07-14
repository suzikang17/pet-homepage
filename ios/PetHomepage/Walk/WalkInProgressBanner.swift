// ios/PetHomepage/Walk/WalkInProgressBanner.swift
import SwiftUI

/// UI-facing wrapper over WalkSessionStore: the store is plain (readable from notification
/// handlers), this adds observation so SwiftUI surfaces refresh when a session starts/ends.
@Observable
final class WalkSessionModel {
    private let sessions: WalkSessionStore
    private let petName: () -> String
    private(set) var active: WalkSession?
    /// Name of the slot/activity the session is bound to (banner headline).
    private(set) var activeTitle: String?
    /// Fired after any session mutation so the hosting view can reload day state
    /// (the ended walk just completed a slot) and resync reminders.
    var onChange: (() -> Void)?

    init(sessions: WalkSessionStore, petName: @escaping () -> String = { "Your pet" }) {
        self.sessions = sessions
        self.petName = petName
        refresh()
    }

    /// Re-reads persisted state — call on appear/foreground so sessions started from
    /// notification actions (other launches) show up.
    func refresh() {
        active = sessions.active
        activeTitle = active.flatMap { sessions.title(for: $0) }
    }

    func startRoutine(taskID: UUID) {
        _ = try? sessions.startRoutine(taskID: taskID, source: .manual)
        didMutate()
    }

    func end() {
        _ = try? sessions.end()
        didMutate()
    }

    func cancel() {
        sessions.cancel()
        didMutate()
    }

    private func didMutate() {
        refresh()
        WalkLiveActivityController.sync(active: active, petName: petName())
        onChange?()
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
                    Text("\(model.activeTitle ?? "Walk") in progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
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
