// ios/PetHomepage/Features/Health/HealthMarkersView.swift
import SwiftUI
import Charts

struct HealthMarkersView: View {
    @State private var model: HealthMarkersViewModel
    @State private var showingAdd = false

    private let store: HealthMarkerStore

    init(store: HealthMarkerStore) {
        self.store = store
        _model = State(initialValue: HealthMarkersViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Weight trend") {
                    if let latest = model.latestWeight {
                        LabeledContent("Latest", value: String(format: "%.1f", latest))
                    } else {
                        Text("No weight logged yet").foregroundStyle(.secondary)
                    }
                    if !model.weightSeries.isEmpty {
                        Chart(model.weightSeries) { point in
                            LineMark(x: .value("Date", point.date),
                                     y: .value("Weight", point.value))
                            PointMark(x: .value("Date", point.date),
                                      y: .value("Weight", point.value))
                        }
                        .frame(height: 180)
                    }
                }
                Section("Latest markers") {
                    if model.latestRows.isEmpty {
                        Text("No markers logged yet").foregroundStyle(.secondary)
                    }
                    ForEach(model.latestRows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.markerType.displayName).font(.headline)
                                Spacer()
                                Text(valueText(row)).font(.body)
                            }
                            Text(row.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { try? model.load() }) {
                MarkerEditView(store: store)
            }
            .onAppear { try? model.load() }
        }
    }

    private func valueText(_ row: MarkerLatestRow) -> String {
        let value = String(format: "%g", row.value)
        if let unit = row.unit, !unit.isEmpty {
            return "\(value) \(unit)"
        }
        return value
    }
}
