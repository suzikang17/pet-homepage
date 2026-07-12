// ios/PetHomepageWidgets/WalkLiveActivityWidget.swift
// Display-only Live Activity: elapsed walk timer on the lock screen / Dynamic Island.
// Tapping opens the app (default behavior); ending happens in-app or via the home geofence.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PetHomepageWidgets: WidgetBundle {
    var body: some Widget {
        WalkLiveActivityWidget()
    }
}

struct WalkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.petName)’s walk")
                        .font(.subheadline.weight(.semibold))
                    Text("Ends automatically when you get home")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.startedAt, style: .timer)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .frame(maxWidth: 64)
                    .multilineTextAlignment(.trailing)
            }
            .padding(14)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.walk.motion")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.petName)’s walk")
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 56)
                }
            } compactLeading: {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(.blue)
            }
        }
    }
}
