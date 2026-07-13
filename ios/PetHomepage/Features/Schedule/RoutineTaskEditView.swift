// ios/PetHomepage/Features/Schedule/RoutineTaskEditView.swift
import SwiftUI

/// What a save writes: a versioned template row, or a single-day one-off.
enum RoutineEditMode {
    case template
    case oneOff(day: Date)
}

/// Add/edit form for a routine task: name, category (drives the icon), time, and — for template
/// tasks — the weekday picker. Saving syncs the task's notifications.
struct RoutineTaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: ActivityCategory
    @State private var time: Date
    @State private var weekdayMask: Int64

    private let store: RoutineStore
    private let reminderScheduler: RoutineReminderScheduler
    private let petStore: PetStore
    private let mode: RoutineEditMode
    private let editing: RoutineTask?

    init(store: RoutineStore, reminderScheduler: RoutineReminderScheduler,
         petStore: PetStore, mode: RoutineEditMode, editing: RoutineTask?) {
        self.store = store
        self.reminderScheduler = reminderScheduler
        self.petStore = petStore
        self.mode = mode
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _category = State(initialValue: editing?.category ?? .care)
        let calendar = Calendar.current
        let hour = editing.map { Int($0.hour) } ?? 9
        let minute = editing.map { Int($0.minute) } ?? 0
        _time = State(initialValue: calendar.date(bySettingHour: hour, minute: minute,
                                                  second: 0, of: Date()) ?? Date())
        _weekdayMask = State(initialValue: editing?.weekdayMask ?? Weekdays.all)
    }

    private var isOneOff: Bool {
        if case .oneOff = mode { return true }
        return false
    }

    var body: some View {
        BrandFormSheet(
            title: isOneOff ? "One-off task" : (editing == nil ? "New routine task" : "Edit task"),
            systemImage: "checklist",
            confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onConfirm: { save() }
        ) {
            Section("Task") {
                TextField("Name (e.g. Morning walk)", text: $name)
                    .accessibilityIdentifier("routineTaskName")
                Picker("Category", selection: $category) {
                    ForEach(ActivityCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                    }
                }
            }
            Section("Time") {
                DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
            }
            if !isOneOff {
                Section("Days") {
                    weekdayPicker
                    Button(weekdayMask == Weekdays.all ? "Every day ✓" : "Every day") {
                        weekdayMask = Weekdays.all
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    /// Seven toggle circles, Sun…Sat. At least one day must stay selected.
    private var weekdayPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = Weekdays.contains(weekdayMask, weekday: weekday)
                Button {
                    let toggled = weekdayMask ^ Weekdays.bit(for: weekday)
                    if toggled != 0 { weekdayMask = toggled }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(selected ? Theme.primary : Theme.inkSoft.opacity(0.12),
                                    in: Circle())
                        .foregroundStyle(selected ? .white : Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("routineWeekday.\(weekday)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        // Category drives the icon — one less thing to pick.
        let icon = category.systemImage

        do {
            let saved: RoutineTask
            switch (mode, editing) {
            case (.oneOff(let day), _):
                saved = try store.addOneOff(name: trimmed, category: category, iconName: icon,
                                            hour: hour, minute: minute, on: day)
            case (.template, .some(let task)):
                saved = try store.editTask(task, name: trimmed, category: category, iconName: icon,
                                           hour: hour, minute: minute, weekdayMask: weekdayMask)
            case (.template, .none):
                saved = try store.createTask(name: trimmed, category: category, iconName: icon,
                                             hour: hour, minute: minute, weekdayMask: weekdayMask)
            }
            Task {
                // A versioned edit moves reminders from the closed row to its successor; the
                // old row's pending snooze must not survive it. The full resync then
                // re-derives every occurrence (including `saved`'s) from day state.
                if let old = editing, old.id != saved.id {
                    await reminderScheduler.cancelTask(old)
                }
                await RoutineReminderPlanner.resync(context: store.context,
                                                    using: reminderScheduler)
            }
            dismiss()
        } catch {
            // Store errors here are programmer errors (save conflicts) — keep the sheet open.
        }
    }
}
