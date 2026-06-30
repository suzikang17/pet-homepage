// ios/PetHomepage/Features/Activities/ActivityLogEditView.swift
import SwiftUI

struct ActivityLogEditView: View {
    @State private var model: ActivityLogEditViewModel
    @State private var addingNewType = false
    @Environment(\.dismiss) private var dismiss

    init(store: ActivityStore, dueScheduler: DueReminderScheduler, diaryStore: DiaryStore, editing: ActivityLog?) {
        _model = State(initialValue: ActivityLogEditViewModel(store: store, dueScheduler: dueScheduler,
                                                              diaryStore: diaryStore, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Activity",
            systemImage: "shower",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); dismiss() } }
        ) {
            Section("Activity") {
                Picker("Type", selection: Binding(
                    get: { model.selectedType },
                    set: { if let t = $0 { model.selectType(t) } }
                )) {
                    ForEach(ActivityCategory.allCases) { category in
                        let typesInCategory = model.availableTypes.filter { $0.category == category }
                        if !typesInCategory.isEmpty {
                            Section(category.displayName) {
                                ForEach(typesInCategory) { type in
                                    Label(type.name, systemImage: type.iconName)
                                        .tag(ActivityType?.some(type))
                                }
                            }
                        }
                    }
                }
                Button { addingNewType = true } label: {
                    Label("New activity", systemImage: "plus.circle")
                }
            }
            Section("When") {
                DatePicker("Performed", selection: $model.performedAt, displayedComponents: .date)
                TextField("Note", text: $model.note)
            }
            Section("Repeat") {
                Toggle("Remind me again", isOn: $model.hasCadence)
                if model.hasCadence {
                    Stepper("Every \(model.intervalDays) days", value: $model.intervalDays, in: 1...365)
                }
            }
            PendingPhotoSection(
                existing: model.existingPhotos,
                pending: model.pendingPhotos,
                onPick: { model.addPickedPhoto($0) },
                onDeleteExisting: { model.deleteExisting($0) },
                onRemovePending: { model.removePending(at: $0) }
            )
        }
        .sheet(isPresented: $addingNewType) {
            newTypeSheet
        }
    }

    private var newTypeSheet: some View {
        BrandFormSheet(
            title: "New activity",
            systemImage: "plus.circle",
            confirmDisabled: model.newTypeName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { addingNewType = false },
            onConfirm: { try? model.createAndSelectNewType(); addingNewType = false }
        ) {
            Section("Details") {
                TextField("Name", text: $model.newTypeName)
                Picker("Category", selection: $model.newTypeCategory) {
                    ForEach(ActivityCategory.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
    }
}
