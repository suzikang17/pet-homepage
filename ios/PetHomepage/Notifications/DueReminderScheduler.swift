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

    /// Single sentinel ID for the one-per-pet vet cadence reminder (idempotent replace).
    static let vetCadenceEntityID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0DEC")!

    init(scheduler: NotificationScheduling, calendar: Calendar = .current, hour: Int = 9, minute: Int = 0) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.hour = hour
        self.minute = minute
    }

    // MARK: - Vaccinations

    /// A one-shot reminder on the vaccination's nextDueAt date, or nil if it has no due date or id.
    func vaccinationReminder(for vaccination: Vaccination) -> PendingReminder? {
        guard let entityID = vaccination.id, let due = vaccination.nextDueAt else { return nil }
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: due)
        return PendingReminder(
            kind: .vaccination,
            entityID: entityID,
            title: "Vaccination due",
            body: "\(vaccination.vaccineName) is due",
            hour: hour,
            minute: minute,
            dateComponents: dateComponents
        )
    }

    /// Schedules the vaccination reminder if it has a due date, otherwise cancels it.
    func syncVaccination(_ vaccination: Vaccination) async {
        if let reminder = vaccinationReminder(for: vaccination) {
            await scheduler.schedule(reminder)
        } else if let entityID = vaccination.id {
            await scheduler.cancel(kind: .vaccination, entityID: entityID)
        }
    }

    func syncVaccinations(_ vaccinations: [Vaccination]) async {
        for vaccination in vaccinations {
            await syncVaccination(vaccination)
        }
    }

    func cancelVaccination(_ vaccination: Vaccination) async {
        guard let entityID = vaccination.id else { return }
        await scheduler.cancel(kind: .vaccination, entityID: entityID)
    }

    // MARK: - Vet cadence

    /// A one-shot reminder on (lastVisit + cadence.months), or nil if there is no last visit.
    func vetCadenceReminder(lastVisit: Date?, cadence: VetCadence) -> PendingReminder? {
        guard let lastVisit else { return nil }
        guard let dueDate = calendar.date(byAdding: .month, value: cadence.months, to: lastVisit) else { return nil }
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
        return PendingReminder(
            kind: .vetCadence,
            entityID: Self.vetCadenceEntityID,
            title: "Vet visit due",
            body: "It's been \(cadence.months) months — time to see the vet",
            hour: cadence.hour,
            minute: cadence.minute,
            dateComponents: dateComponents
        )
    }

    func syncVetCadence(lastVisit: Date?, cadence: VetCadence) async {
        if let reminder = vetCadenceReminder(lastVisit: lastVisit, cadence: cadence) {
            await scheduler.schedule(reminder)
        } else {
            await cancelVetCadence()
        }
    }

    func cancelVetCadence() async {
        await scheduler.cancel(kind: .vetCadence, entityID: Self.vetCadenceEntityID)
    }

    // MARK: - Activities

    /// A one-shot reminder on the log's nextDueAt date, or nil if it has no due date.
    func activityReminder(for log: ActivityLog) -> PendingReminder? {
        guard let due = log.nextDueAt else { return nil }
        let name = log.activityType?.name ?? "Activity"
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: due)
        return PendingReminder(
            kind: .activity,
            entityID: log.id,
            title: "\(name) due",
            body: "Time for \(name)",
            hour: hour,
            minute: minute,
            dateComponents: dateComponents
        )
    }

    /// Schedules the activity reminder if it has a due date, otherwise cancels it.
    func syncActivity(_ log: ActivityLog) async {
        if let reminder = activityReminder(for: log) {
            await scheduler.schedule(reminder)
        } else {
            await scheduler.cancel(kind: .activity, entityID: log.id)
        }
    }

    func cancelActivity(_ log: ActivityLog) async {
        await scheduler.cancel(kind: .activity, entityID: log.id)
    }
}
