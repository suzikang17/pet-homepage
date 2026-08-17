// ios/PetHomepage/Notifications/DueReminderPlanner.swift
import CoreData
import Foundation

/// Re-derives every due reminder — vaccinations, the vet cadence, and recurring activities —
/// from the data, and hands them to DueReminderScheduler.
///
/// These three kinds were previously scheduled ONLY at the moment a record was saved, logged, or
/// deleted, and never re-derived. Nothing re-armed them, so a reinstall, a restore, or a record
/// synced in from another device left the user with silence and no way to notice. There was even
/// a `syncVaccinations(_:)` bulk method sitting unused with zero callers.
///
/// This is the counterpart of RoutineReminderPlanner.resync, which does the same job for the
/// weekly routine, and it is called from the same place: the app-launch task.
enum DueReminderPlanner {
    static func resync(context: NSManagedObjectContext,
                       using dueScheduler: DueReminderScheduler,
                       cadenceMonths: Int) async {
        let petStore = PetStore(context: context)
        let logStore = LogStore(context: context, petStore: petStore)
        let activityStore = ActivityStore(context: context, petStore: petStore)

        // Vaccinations: each entry carries its own nextDueAt, so each one owns a reminder.
        await dueScheduler.syncVaccinations((try? logStore.vaccines()) ?? [])

        // Activities: reminders are keyed by the LOG ENTRY's id, and only the newest log of a
        // type is the live one — re-arming older entries would resurrect reminders for cycles
        // already completed.
        for type in (try? activityStore.types(includeArchived: false)) ?? [] {
            if let latest = try? logStore.latestLog(of: type) {
                await dueScheduler.syncActivity(latest)
            }
        }

        // Vet cadence: one per pet, derived from the most recent visit — mirrors
        // VetVisitEditViewModel.save() and TimelineViewModel's delete path.
        if let pet = try? petStore.currentPet() {
            await dueScheduler.syncVetCadence(
                petID: pet.id,
                petName: pet.name,
                lastVisit: try? logStore.mostRecentVisitDate(),
                cadence: VetCadence(months: cadenceMonths, hour: 9, minute: 0)
            )
        }
    }
}
