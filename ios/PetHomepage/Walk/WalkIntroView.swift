// ios/PetHomepage/Walk/WalkIntroView.swift
import SwiftUI

/// One-time first-launch introduction to walk auto-detection. Shown once ever
/// (walk.introShown); [Set up] chains into the Walk detection settings sheet via the
/// pending-flag/onDismiss pattern the app already uses for sheet handoffs.
struct WalkIntroView: View {
    let onSetUp: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Theme.primary.opacity(0.3), radius: 16, y: 6)
                .padding(.bottom, 24)

            Text("Walks that log themselves")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                introRow(icon: "bell.badge", text: "Get a prompt when a walk starts — no need to remember to log it")
                introRow(icon: "house", text: "The walk ends itself the moment you're back home")
                introRow(icon: "checklist", text: "Scheduled walks get checked off with real start and end times")
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button(action: onSetUp) {
                    Text("Set up (2 min)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Maybe later", action: onLater)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .interactiveDismissDisabled(false)
    }

    private func introRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
