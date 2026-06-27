// ios/PetHomepage/Features/Medications/LogDoseView.swift
import SwiftUI

/// Two-step "log a dose" sheet: a form to adjust the time + note (with a live next-reminder
/// preview), then a confirmation screen showing the logged dose and the new next reminder.
struct LogDoseView: View {
    @State private var model: LogDoseViewModel
    @Environment(\.dismiss) private var dismiss

    init(medication: Medication, doseLogStore: DoseLogStore, reminderScheduler: MedicationReminderScheduler) {
        _model = State(initialValue: LogDoseViewModel(
            medication: medication,
            doseLogStore: doseLogStore,
            reminderScheduler: reminderScheduler
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isConfirmed { confirmation } else { form }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(model.isConfirmed ? "Dose logged" : "Log a dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.isConfirmed {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .brandSheet()
        }
    }

    private var form: some View {
        Form {
            Section("When") {
                DatePicker("Given", selection: $model.givenAt)
            }
            Section("Note") {
                TextField("e.g. with food, half dose", text: $model.note, axis: .vertical)
            }
            Section {
                LabeledContent("Next reminder") {
                    Text(model.nextReminder(), format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(Theme.primary)
                        .fontWeight(.semibold)
                }
            } footer: {
                Text("Logging this dose moves the next reminder to follow the \(model.frequency.label.lowercased()) schedule.")
            }
            Section {
                Button {
                    Task { await model.confirm() }
                } label: {
                    Text("Log dose").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .headerProminence(.increased)
    }

    private var confirmation: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.ok)
            Text("Dose logged")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
            Text(model.givenAt, format: .dateTime.weekday().month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)

            if let next = model.confirmedNextReminder {
                VStack(spacing: 5) {
                    Text("NEXT REMINDER")
                        .font(.caption2.weight(.heavy)).tracking(1.4)
                        .foregroundStyle(Theme.inkSoft)
                    Text(next, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 6)
            }

            Text("\(model.doseCount) dose\(model.doseCount == 1 ? "" : "s") logged")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}
