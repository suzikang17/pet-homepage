// ios/PetHomepage/Features/PetProfile/CadenceTile.swift
import SwiftUI

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
        case .overdue: return .red
        case .dueToday: return Theme.primary
        case .dueIn: return Theme.inkSoft
        case .noCadence: return Theme.inkSoft
        }
    }
}

/// One recurring thing. Tappable in EVERY state — a catalogue exists so you can record something
/// you just did regardless of what the app thinks is due.
struct CadenceTile: View {
    let item: CadenceItem
    let now: Date
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var lastDoneText: String {
        guard let lastDone = item.lastDone else { return "Never logged" }
        return lastDone.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
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
        .buttonStyle(.plain)
        .onLongPressGesture { onLongPress() }
        .accessibilityIdentifier("cadenceTile.\(item.name)")
        .accessibilityLabel("\(item.name), \(item.dueState(now: now).badgeText), last done \(lastDoneText)")
    }
}
