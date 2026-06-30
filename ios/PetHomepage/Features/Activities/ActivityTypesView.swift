// ios/PetHomepage/Features/Activities/ActivityTypesView.swift
import SwiftUI

struct ActivityTypesView: View {
    @State private var model: ActivityTypesViewModel
    @State private var editingType: ActivityType?
    @Environment(\.dismiss) private var dismiss

    init(store: ActivityStore) {
        _model = State(initialValue: ActivityTypesViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(ActivityCategory.allCases) { category in
                let typesInCategory = model.types.filter { $0.category == category }
                if !typesInCategory.isEmpty {
                    Section(category.displayName) {
                        ForEach(typesInCategory) { type in
                            Button { editingType = type } label: {
                                HStack {
                                    Label(type.name, systemImage: type.iconName)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(type.defaultIntervalDays > 0 ? "every \(type.defaultIntervalDays)d" : "no repeat")
                                        .font(.caption).foregroundStyle(Theme.inkSoft)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.archive(type) } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity types")
        .brandSheet()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { model.reload() }
        .sheet(item: $editingType, onDismiss: { model.reload() }) { type in
            ActivityTypeEditView(type: type) { name, category, iconName, intervalDays in
                model.update(type, name: name, category: category, iconName: iconName, defaultIntervalDays: intervalDays)
            }
        }
    }
}
