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
            slots = try store.slots(for: day)
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
