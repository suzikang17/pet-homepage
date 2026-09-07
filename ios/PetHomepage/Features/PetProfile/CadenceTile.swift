// ios/PetHomepage/Features/PetProfile/CadenceTile.swift
import SwiftUI
import UIKit

extension DueState {
    var badgeText: String {
        switch self {
        case .overdue(let days): return days == 1 ? "1 day late" : "\(days) days late"
        case .dueToday: return "Due today"
        case .dueIn(let days): return days == 1 ? "Tomorrow" : "In \(days) days"
        case .noCadence: return "Not yet logged"
        }
    }

    var badgeTint: Color {
        switch self {
        case .overdue: return Theme.danger
        case .dueToday: return Theme.primaryDeep
        case .dueIn: return Theme.inkSoft
        case .noCadence: return Theme.inkSoft
        }
    }
}

/// One recurring thing. Interactive in EVERY state — a catalogue exists so you can record
/// something you just did regardless of what the app thinks is due.
///
/// Tap OPENS the item; long-press logs it. That way round because the reverse shipped first and
/// was wrong: on a two-column grid of similar cards, the most reachable gesture was writing a
/// dose with no confirmation, and the only way back was an Undo strip that expired after four
/// seconds. Logging is still one gesture for the common "I just did this" case — it now just has
/// to be meant.
struct CadenceTile: View {
    let item: CadenceItem
    let now: Date
    /// Opens the item's sheet.
    let onTap: () -> Void
    /// Logs it, at `now`.
    let onLongPress: () -> Void

    private var lastDoneText: String {
        guard let lastDone = item.lastDone else { return "Never logged" }
        return lastDone.formatted(.relative(presentation: .named))
    }

    var body: some View {
        // Deliberately NOT a Button. A Button's action and an attached .onLongPressGesture can
        // both fire on the same press, which here would log at `now` AND open the backdate sheet
        // — recording two doses for one event. Separate tap/long-press gestures on a shaped
        // container are unambiguous, and match WalkInProgressBanner, the app's only other
        // long-press surface.
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let url = item.dailyPhotoURL {
                        PhotoThumbnail(url: url, side: 28, cornerRadius: 8)
                    } else {
                        Image(systemName: item.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primaryDeep)
                    }
                    Spacer(minLength: 0)
                    Text(item.dueState(now: now).badgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.dueState(now: now).badgeTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(lastDoneText)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture {
            // Success haptic on the gesture itself, not after the async write returns — the
            // feedback is about the press landing, and a delayed buzz reads as lag. It sits on
            // the long-press because that is now the gesture that writes.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onLongPress()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("cadenceTile.\(item.name)")
        .accessibilityLabel("\(item.name), \(item.dueState(now: now).badgeText), last done \(lastDoneText)")
        // The default action opens the sheet, which is where logging, history and delete all
        // live — so VoiceOver reaches everything without this. "Log now" stays anyway: it is the
        // shortcut sighted users get from the long press, which VoiceOver cannot perform.
        .accessibilityAction(named: "Log now") { onLongPress() }
    }
}
