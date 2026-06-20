// ios/PetHomepage/Features/Health/HealthMarkersView.swift
import SwiftUI
import Charts

/// Content-only — embedded in HealthTabView, which provides the NavigationStack,
/// the gradient hero, and the "+" (bound to `showingAdd`).
struct HealthMarkersView: View {
    @State private var model: HealthMarkersViewModel
    @Binding var showingAdd: Bool

    private let store: HealthMarkerStore

    init(store: HealthMarkerStore, showingAdd: Binding<Bool>) {
        self.store = store
        _showingAdd = showingAdd
        _model = State(initialValue: HealthMarkersViewModel(store: store))
    }

    var body: some View {
        List {
            Section("Weight trend") {
                if let latest = model.latestWeight {
                    LabeledContent("Latest", value: String(format: "%.1f", latest))
                } else {
                    Text("No weight logged yet").foregroundStyle(Theme.inkSoft)
                }
                if !model.weightSeries.isEmpty {
                    Chart(model.weightSeries) { point in
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Weight", point.value))
                        .foregroundStyle(Theme.primary)
                        PointMark(x: .value("Date", point.date),
                                  y: .value("Weight", point.value))
                        .foregroundStyle(Theme.primary)
                    }
                    .frame(height: 180)
                }
            }
            Section("Latest markers") {
                if model.latestRows.isEmpty {
                    Text("No markers logged yet").foregroundStyle(Theme.inkSoft)
                }
                ForEach(model.latestRows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.markerType.displayName).font(Theme.headline()).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(valueText(row)).font(.body)
                        }
                        Text(row.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .sheet(isPresented: $showingAdd, onDismiss: { try? model.load() }) {
            MarkerEditView(store: store)
        }
        .onAppear { try? model.load() }
    }

    private func valueText(_ row: MarkerLatestRow) -> String {
        let value = String(format: "%g", row.value)
        if let unit = row.unit, !unit.isEmpty {
            return "\(value) \(unit)"
        }
        return value
    }
}
