// ios/PetHomepage/Walk/WalkInProgressBanner.swift
import SwiftUI
import UIKit

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
    /// Photos taken during the active session, shown as a badge on the camera button.
    private(set) var pendingPhotoCount: Int = 0

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
        pendingPhotoCount = sessions.pendingPhotoCount
    }

    /// Downscales through the same path as every other picker in the app, then parks it on
    /// the session. Attaching happens later, when the walk is written.
    func capture(_ image: UIImage) {
        guard let jpeg = ImageDownscaler.scaledJPEG(from: image) else { return }
        sessions.attachPhoto(jpeg)
        pendingPhotoCount = sessions.pendingPhotoCount
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
    @State private var showingCamera = false

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

                if CameraPicker.isAvailable {
                    Button { showingCamera = true } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 38, height: 38)
                            .background(Theme.primary.opacity(0.12), in: Circle())
                            .overlay(alignment: .topTrailing) {
                                if model.pendingPhotoCount > 0 {
                                    Text("\(model.pendingPhotoCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Theme.primary, in: Capsule())
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take a photo on this walk")
                    .accessibilityIdentifier("walkBannerCamera")
                }

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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(
                    onCapture: { model.capture($0) },
                    onFinish: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .confirmationDialog("Discard this walk?", isPresented: $confirmCancel,
                                titleVisibility: .visible) {
                Button("Discard without logging", role: .destructive) { model.cancel() }
                Button("Keep walking", role: .cancel) {}
            }
            .accessibilityIdentifier("walkInProgressBanner")
        }
    }
}
