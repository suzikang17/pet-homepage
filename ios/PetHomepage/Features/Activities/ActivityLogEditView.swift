// ios/PetHomepage/Features/Activities/ActivityLogEditView.swift
import SwiftUI

struct ActivityLogEditView: View {
    @State private var model: ActivityLogEditViewModel
    @State private var addingNewType = false
    @Environment(\.dismiss) private var dismiss

    init(logStore: LogStore, store: ActivityStore, dueScheduler: DueReminderScheduler, editing: LogEntry?) {
        _model = State(initialValue: ActivityLogEditViewModel(logStore: logStore, store: store,
                                                              dueScheduler: dueScheduler, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Activity",
            systemImage: "shower",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); dismiss() } }
        ) {
            Section {
                typePicker
                Button { addingNewType = true } label: {
                    Label("New activity", systemImage: "plus.circle")
                }
            }
            Section {
                DatePicker("Started", selection: $model.performedAt,
                           displayedComponents: [.date, .hourAndMinute])
                Toggle("Add end time", isOn: $model.hasEndTime)
                if model.hasEndTime {
                    DatePicker("Ended", selection: $model.endedAt,
                               in: model.performedAt...,
                               displayedComponents: [.date, .hourAndMinute])
                    if let minutes = model.durationMinutes {
                        LabeledContent("Duration", value: "\(minutes) min")
                    }
                }
                TextField("Note", text: $model.note)
            }
            Section {
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

    /// Type selector grouped into category sections. Extracted into its own builder so the
    /// nested ForEach/Section/Binding expression stays within the type-checker's budget.
    @ViewBuilder
    private var typePicker: some View {
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
    }

    private var newTypeSheet: some View {
        BrandFormSheet(
            title: "New activity",
            systemImage: "plus.circle",
            confirmDisabled: model.newTypeName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { addingNewType = false },
            onConfirm: { try? model.createAndSelectNewType(); addingNewType = false }
        ) {
            Section {
                TextField("Name", text: $model.newTypeName)
                Picker("Category", selection: $model.newTypeCategory) {
                    ForEach(ActivityCategory.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
    }
}
