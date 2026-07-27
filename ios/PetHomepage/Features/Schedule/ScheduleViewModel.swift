// ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift
import Foundation
import Observation

/// Day-pager state for the Schedule tab: which day is shown, its computed slots, and the
/// post-check-off "Add a photo?" toast. All writes delegate to RoutineStore; `now` is an
/// injectable clock so tests are deterministic.
@Observable
final class ScheduleViewModel {
    private(set) var day: Date
    private(set) var slots: [RoutineSlot] = []
    var errorMessage: String?
    /// The completion that just happened; non-nil arms the "Add a photo?" toast.
    private(set) var toastCompletion: LogEntry?
    /// Fired after any mutation that changes what should remind (check-off, skip, time
    /// change) — the view hooks this to resync pending notifications.
    var onDayStateChanged: (() -> Void)?

    private let store: RoutineStore
    private let logStore: LogStore
    private let calendar: Calendar
    private let now: () -> Date

    init(store: RoutineStore,
         logStore: LogStore,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.logStore = logStore
        self.calendar = calendar
        self.now = now
        self.day = calendar.startOfDay(for: now())
    }

    var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }
    var isFuture: Bool { day > calendar.startOfDay(for: now()) }

    var dayTitle: String {
        if isToday { return "Today" }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1,
                                                           to: calendar.startOfDay(for: now()))!) {
            return "Yesterday"
        }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: 1,
                                                           to: calendar.startOfDay(for: now()))!) {
            return "Tomorrow"
        }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    /// Done / total for the day, with deliberately-skipped slots out of both counts.
    var progress: (done: Int, total: Int) {
        let counted = slots.filter { !$0.isSkipped }
        return (counted.filter(\.isCompleted).count, counted.count)
    }

    func load() {
        do {
            let computed = try store.slots(for: day)
            // Journal ordering: what happened (by completion time) above what's left
            // (scheduled order), deliberately-skipped slots last. Presentation-only —
            // RoutineStore.slots(for:) stays in scheduled order for its other consumers.
            let done = computed.filter(\.isCompleted).sorted {
                ($0.completion?.performedAt ?? .distantPast)
                    < ($1.completion?.performedAt ?? .distantPast)
            }
            let open = computed.filter { !$0.isCompleted && !$0.isSkipped }
            let skipped = computed.filter { !$0.isCompleted && $0.isSkipped }
            slots = done + open + skipped
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Day navigation

    func goToPreviousDay() { shift(by: -1) }
    func goToNextDay() { shift(by: 1) }

    func goToToday() {
        day = calendar.startOfDay(for: now())
        toastCompletion = nil
        load()
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = next
        toastCompletion = nil
        load()
    }

    // MARK: - Slot actions

    /// Completes the slot and arms the photo toast. Future days can't be completed.
    func checkOff(_ slot: RoutineSlot) {
        guard !isFuture, !slot.isCompleted else { return }
        do {
            toastCompletion = try store.checkOff(slot.task, on: day, now: now())
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Completes the slot stamped at an explicit time — the swipe "Done at…" path for crossing
    /// things off after the fact. No photo toast: the time sheet already had the user's focus,
    /// and the completed row keeps its own camera button.
    func checkOff(_ slot: RoutineSlot, at date: Date) {
        guard !isFuture, !slot.isCompleted else { return }
        do {
            _ = try store.checkOff(slot.task, on: day, now: date)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Logs one feeding of a meal slot (amount in the slot's unit). No photo toast — feedings
    /// are frequent and a toast per bite would nag.
    func logFeeding(_ slot: RoutineSlot, amount: Double) {
        guard !isFuture, amount > 0 else { return }
        do {
            _ = try store.logFeeding(slot.task, on: day, now: now(), amount: amount)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Removes one feeding entry; the slot reopens if the total drops below allotment.
    func removeFeeding(_ entry: LogEntry) {
        do {
            try store.uncheck(entry)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func uncheck(_ slot: RoutineSlot) {
        guard let completion = slot.completion else { return }
        do {
            if toastCompletion?.id == completion.id { toastCompletion = nil }
            try store.uncheck(completion)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleSkip(_ slot: RoutineSlot) {
        do {
            if slot.isSkipped {
                try store.unskip(slot.task, on: day)
            } else {
                try store.skip(slot.task, on: day)
            }
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Per-day time changes

    /// Moves the slot's time for the shown day only (long-press → "Change time").
    func changeTime(_ slot: RoutineSlot, hour: Int, minute: Int) {
        do {
            try store.overrideTime(slot.task, on: day, hour: hour, minute: minute)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Removes the shown day's time change, restoring the template time.
    func clearTimeChange(_ slot: RoutineSlot) {
        do {
            try store.clearOverrideTime(slot.task, on: day)
            load()
            onDayStateChanged?()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Edits when a completed slot was actually done (time-of-day only; the day is pinned).
    func updateCompletionTime(_ slot: RoutineSlot, hour: Int, minute: Int) {
        guard let completion = slot.completion else { return }
        do {
            try store.updateCompletionTime(completion, hour: hour, minute: minute)
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Photo toast

    func attachPhoto(_ data: Data, to entry: LogEntry) {
        do {
            try logStore.addPhoto(to: entry, imageData: data)
            if toastCompletion?.id == entry.id { toastCompletion = nil }
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismissToast() { toastCompletion = nil }
}
