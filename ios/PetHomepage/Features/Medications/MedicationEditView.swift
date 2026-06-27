// ios/PetHomepage/Features/Medications/MedicationEditView.swift
import SwiftUI

struct MedicationEditView: View {
    @State private var model: MedicationEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: MedicationStore,
         reminderScheduler: MedicationReminderScheduler,
         editing: Medication?) {
        _model = State(initialValue: MedicationEditViewModel(
            store: store,
            reminderScheduler: reminderScheduler,
            editing: editing
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Form {
                    Section("Details") {
                        TextField("Drug name", text: $model.drugName)
                        TextField("Dosage", text: $model.dosage)
                    }
                    Section("Frequency") {
                        Picker("Repeat by", selection: $model.frequencyUnit) {
                            Text("Days").tag(FrequencyUnit.day)
                            Text("Weeks").tag(FrequencyUnit.week)
                            Text("Months").tag(FrequencyUnit.month)
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                        .onChange(of: model.frequencyUnit) { _, _ in model.resetNextReminderFromFrequency() }
                        Stepper(value: $model.frequencyInterval, in: 1...60) {
                            HStack {
                                Text("Every")
                                Spacer()
                                Text(model.frequencyLabel)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .onChange(of: model.frequencyInterval) { _, _ in model.resetNextReminderFromFrequency() }
                    }
                    Section {
                        DatePicker("Reminder time", selection: $model.scheduleTime, displayedComponents: .hourAndMinute)
                        DatePicker("Next reminder", selection: $model.startedAt, displayedComponents: .date)
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text("You’ll be reminded then, repeating \(model.frequencyLabel.lowercased()).")
                    }
                    Section("Refill") {
                        Toggle("Track refill", isOn: $model.hasRefillDue)
                        if model.hasRefillDue {
                            DatePicker("Refill due", selection: $model.refillDueAt, displayedComponents: .date)
                        }
                    }
                    Section("End") {
                        Toggle("Ended", isOn: $model.hasEnded)
                        if model.hasEnded {
                            DatePicker("Ended", selection: $model.endedAt, displayedComponents: .date)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .headerProminence(.increased)
            }
            .background(Theme.bg)
            .tint(Theme.primary)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
        }
        .presentationDragIndicator(.hidden)
    }

    /// Gradient header carrying the title + Cancel/Save — replaces the stock nav bar so the
    /// modal matches Home/Timeline/Settings (and avoids iOS 26's capsule-button-on-color clash).
    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Button("Save") {
                    Task {
                        try? await model.save()
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .disabled(!model.isValid)
                .opacity(model.isValid ? 1 : 0.45)
            }
            HStack(spacing: 10) {
                Image(systemName: "pills.fill").font(.title3)
                Text("Medication").font(Theme.title(26))
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.brandGradient)
        .clipShape(.rect(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.25), radius: 14, y: 6)
    }
}
