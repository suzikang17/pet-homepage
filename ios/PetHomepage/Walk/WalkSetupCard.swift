// ios/PetHomepage/Walk/WalkSetupCard.swift
import SwiftUI

/// Dismissible Schedule card nudging auto-detect setup, shown while a walk-marked slot
/// exists but detection isn't configured. "Not now" dismisses permanently — Settings →
/// Walk detection remains the home for setup.
struct WalkSetupCard: View {
    let onSetUp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Walks can log themselves")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Prompted when you head out, done when you're home.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button("Set up") { onSetUp() }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                Button("Not now") { onDismiss() }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("walkSetupCard")
    }
}
