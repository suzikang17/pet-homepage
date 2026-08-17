// ios/PetHomepage/Models/Medication.swift
import CoreData

@objc(Medication)
public class Medication: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var drugName: String
    @NSManaged public var dosage: String
    @NSManaged public var frequency: String
    @NSManaged public var scheduleTime: Date

    /// DEPRECATED — read `nextReminderAt` instead. Despite the name this never meant "when the
    /// course began": it held the NEXT REMINDER DATE, and every dose log overwrote it. That lie
    /// caused six separate bugs (reminders that fired once and died, a quick action that logged
    /// without advancing the cadence, two half-undos, and a "Recent activity" card that listed
    /// future dates), because each new reader reasonably assumed it meant what it says.
    ///
    /// Kept only so the v1 store still maps and CloudKit's append-only schema stays satisfied.
    /// `PersistenceController.backfillNextReminderAt` copies it forward once; nothing writes it.
    @NSManaged public var startedAt: Date

    /// When this medication's next reminder should fire. Advanced by MedicationDoseLogger each
    /// time a dose is recorded — the single writer.
    @NSManaged public var nextReminderAt: Date?

    @NSManaged public var endedAt: Date?
    @NSManaged public var refillDueAt: Date?
    @NSManaged public var pet: Pet?
    @NSManaged public var veterinarian: Veterinarian?
    @NSManaged public var photos: NSSet?
}

extension Medication {
    /// The next reminder date, as a non-optional.
    ///
    /// CloudKit requires new attributes to be optional, so the stored `nextReminderAt` is
    /// `Date?`. This falls back to the legacy `startedAt` for any row the backfill has not
    /// reached — a record synced in from a device still running the old build, for instance —
    /// so a partially-migrated store never reads as "no reminder".
    var nextReminder: Date {
        get { nextReminderAt ?? startedAt }
        set { nextReminderAt = newValue }
    }

    @nonobjc public static func fetchRequest() -> NSFetchRequest<Medication> {
        NSFetchRequest<Medication>(entityName: "Medication")
    }

    /// This medication's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}
