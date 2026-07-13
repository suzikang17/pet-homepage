// ios/PetHomepage/Features/Schedule/RoutineTemplateView.swift
import SwiftUI

/// "Edit routine": the current weekly template. Rows show name, time, and a days summary;
/// tapping opens the editor (versioned edit), swiping deletes (closes the version — history
/// keeps it). One-offs never appear here.
struct RoutineTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [RoutineTask] = []
    @State private var editTarget: RoutineTask?
    @State private var showAdd = false

    let store: RoutineStore
    let reminderScheduler: RoutineReminderScheduler
    let petStore: PetStore

    var body: some View {
        List {
            ForEach(tasks) { task in
                Button { editTarget = task } label: { row(task) }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await reminderScheduler.cancelTask(task)
                                try? store.endTask(task)
                                await RoutineReminderPlanner.resync(context: store.context,
                                                                    using: reminderScheduler)
                                reload()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tint(Theme.primary)
        .navigationTitle("Edit routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("routineTemplateAdd")
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $editTarget, onDismiss: reload) { task in
            RoutineTaskEditView(store: store, reminderScheduler: reminderScheduler,
                                petStore: petStore, mode: .template, editing: task)
        }
        .sheet(isPresented: $showAdd, onDismiss: reload) {
            RoutineTaskEditView(store: store, reminderScheduler: reminderScheduler,
                                petStore: petStore, mode: .template, editing: nil)
        }
    }

    private func reload() {
        tasks = (try? store.currentTasks()) ?? []
    }

    private func row(_ task: RoutineTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primary.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(timeLabel(task)) · \(daysSummary(task.weekdayMask))")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("routineTemplateRow.\(task.name)")
    }

    private func timeLabel(_ task: RoutineTask) -> String {
        let date = Calendar.current.date(bySettingHour: Int(task.hour), minute: Int(task.minute),
                                         second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }

    private func daysSummary(_ mask: Int64) -> String {
        if mask == Weekdays.all { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols // ["Sun", "Mon", …]
        return Weekdays.weekdays(in: mask).map { symbols[$0 - 1] }.joined(separator: " ")
    }
}
