// ios/PetHomepage/Notifications/DueReminderScheduler.swift
import Foundation

/// User-configurable "see the vet every N months" cadence, fired at a fixed time of day.
struct VetCadence: Equatable {
    let months: Int
    let hour: Int
    let minute: Int
}

/// Schedules one-shot due reminders for vaccinations (from nextDueAt) and a vet-visit
/// cadence (lastVisit + N months) through the shared NotificationScheduling. Pure enough
/// to unit-test with the FakeNotificationScheduler — never touches UNUserNotificationCenter.
final class DueReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    private let hour: Int
    private let minute: Int
    private let now: () -> Date

    init(scheduler: NotificationScheduling, calendar: Calendar = .current, hour: Int = 9,
         minute: Int = 0, now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.hour = hour
        self.minute = minute
        self.now = now
    }

    /// The trigger components for a due date, shared by all three kinds.
    ///
    /// Returns the due date's components while it is still ahead — a one-shot on that day. Once
    /// the date has PASSED, returns nil, which PendingReminder treats as a daily repeating
    /// trigger at the reminder's hour/minute. A one-shot on a past date never fires at all, so
    /// an ignored due date used to go permanently silent: a vaccination three weeks overdue said
    /// nothing. Overdue things should keep asking until they are actually done, and logging the
    /// thing replaces this with the next one-shot.
    ///
    /// Day granularity, matching CadenceItem.dueState: due today is not overdue.
    private func triggerComponents(for due: Date) -> DateComponents? {
        guard calendar.startOfDay(for: due) >= calendar.startOfDay(for: now()) else { return nil }
        return calendar.dateComponents([.year, .month, .day], from: due)
    }

    // MARK: - Vaccinations

    /// A one-shot reminder on the vaccine log's nextDueAt date, or nil if it has no due date.
    /// Body names the pet when the entry has one ("Rabies is due for Milo"), else falls back
    /// to the pet-agnostic copy ("Rabies is due").
    func vaccinationReminder(for vaccine: LogEntry) -> PendingReminder? {
        guard let due = vaccine.nextDueAt else { return nil }
        let dateComponents = triggerComponents(for: due)
        let title = vaccine.title ?? "Vaccine"
        let body: String
        if let petName = vaccine.pet?.name, !petName.isEmpty {
            body = "\(title) is due for \(petName)"
        } else {
            body = "\(title) is due"
        }
        return PendingReminder(
            kind: .vaccination,
            entityID: vaccine.id,
            title: "Vaccination due",
            body: body,
            hour: hour,
            minute: minute,
            dateComponents: dateComponents
        )
    }

    /// Schedules the vaccination reminder if it has a due date, otherwise cancels it.
    func syncVaccination(_ vaccine: LogEntry) async {
        if let reminder = vaccinationReminder(for: vaccine) {
            await scheduler.schedule(reminder)
        } else {
            await scheduler.cancel(kind: .vaccination, entityID: vaccine.id)
        }
    }

    func syncVaccinations(_ vaccines: [LogEntry]) async {
        for vaccine in vaccines {
            await syncVaccination(vaccine)
        }
    }

    func cancelVaccination(_ vaccine: LogEntry) async {
        await scheduler.cancel(kind: .vaccination, entityID: vaccine.id)
    }

    // MARK: - Vet cadence

    /// A one-shot reminder on (lastVisit + cadence.months), or nil if there is no last visit.
    /// Keyed by `petID` (not a shared sentinel) so each pet's cadence reminder coexists with
    /// every other pet's — with two pets, syncing both must not overwrite one another.
    func vetCadenceReminder(petID: UUID, petName: String?, lastVisit: Date?, cadence: VetCadence) -> PendingReminder? {
        guard let lastVisit else { return nil }
        guard let dueDate = calendar.date(byAdding: .month, value: cadence.months, to: lastVisit) else { return nil }
        let dateComponents = triggerComponents(for: dueDate)
        let body: String
        if let petName, !petName.isEmpty {
            body = "It's been \(cadence.months) months — time for \(petName)'s vet visit"
        } else {
            body = "It's been \(cadence.months) months — time to see the vet"
        }
        return PendingReminder(
            kind: .vetCadence,
            entityID: petID,
            title: "Vet visit due",
            body: body,
            hour: cadence.hour,
            minute: cadence.minute,
            dateComponents: dateComponents
        )
    }

    func syncVetCadence(petID: UUID, petName: String? = nil, lastVisit: Date?, cadence: VetCadence) async {
        if let reminder = vetCadenceReminder(petID: petID, petName: petName, lastVisit: lastVisit, cadence: cadence) {
            await scheduler.schedule(reminder)
        } else {
            await cancelVetCadence(petID: petID)
        }
    }

    func cancelVetCadence(petID: UUID) async {
        await scheduler.cancel(kind: .vetCadence, entityID: petID)
    }

    // MARK: - Activities

    /// A one-shot reminder on the log's nextDueAt date, or nil if it has no due date. Body names
    /// the pet when the entry has one ("Time for Bella's bath"), else falls back to the
    /// pet-agnostic copy ("Time for Bath").
    func activityReminder(for log: LogEntry) -> PendingReminder? {
        guard let due = log.nextDueAt else { return nil }
        let name = log.activityType?.name ?? "Activity"
        let dateComponents = triggerComponents(for: due)
        // Use the activity type's own reminder time when available; otherwise the scheduler default.
        let reminderHour = log.activityType.map { Int($0.reminderHour) } ?? hour
        let reminderMinute = log.activityType.map { Int($0.reminderMinute) } ?? minute
        let body: String
        if let petName = log.pet?.name, !petName.isEmpty {
            body = "Time for \(petName)'s \(name)"
        } else {
            body = "Time for \(name)"
        }
        return PendingReminder(
            kind: .activity,
            entityID: log.id,
            title: "\(name) due",
            body: body,
            hour: reminderHour,
            minute: reminderMinute,
            dateComponents: dateComponents
        )
    }

    /// Schedules the activity reminder if it has a due date, otherwise cancels it.
    func syncActivity(_ log: LogEntry) async {
        if let reminder = activityReminder(for: log) {
            await scheduler.schedule(reminder)
        } else {
            await scheduler.cancel(kind: .activity, entityID: log.id)
        }
    }

    func cancelActivity(_ log: LogEntry) async {
        await scheduler.cancel(kind: .activity, entityID: log.id)
    }
}
