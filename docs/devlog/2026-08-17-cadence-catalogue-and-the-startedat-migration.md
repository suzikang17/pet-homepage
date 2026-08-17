---
lore_type: devlog
created: 2026-08-17
title: "Cadence catalogue, reminder repairs, and the startedAt migration"
date: 2026-08-17
day: 52
---

**Chased "why didn't my preventative reminder fire?" to its root, and found one mis-named Core Data field behind six separate bugs — then built the Home cadence catalogue on top of the repaired foundation.**

## What got done

- **Fixed the reported bug.** Weekly/monthly medication reminders were scheduled as one-shot `UNCalendarNotificationTrigger`s (`repeats` defaults to `false`), which fire once and are consumed. `MedicationReminderScheduler`'s own doc comment promised a resync "on save, dose log, and app launch" — but `syncAll(_:)` had **zero non-test callers**. So a monthly preventative got exactly one notification, ever. Calendar-expressible cadences now use repeating triggers; everything else re-arms via a real launch resync.
- **One-tap dose logging.** Added a `medicationReminder` notification category (Log dose / Snooze 1 hour) and routed medication taps to Timeline. Logging went from four taps to one.
- **Home cadence catalogue.** A tile per recurring thing (medications by cadence, `ActivityType`s by interval), tap to log, hold for the record. Built via a 7-task subagent-driven plan.
- **`CareActivityDetailView`** — the `ActivityType` twin of `MedicationDetailView`: history, cadence editor, full log form, per-entry delete.
- **Separated Upcoming from Recent** across Home, Timeline and Schedule. Doses became a first-class `TimelineKind`.
- **Due reminders resync + re-nag.** `DueReminderPlanner.resync` re-derives vaccination/vet/activity reminders on launch; overdue items switch to a daily repeating trigger instead of going silent.
- **v2 Core Data model** introducing `Medication.nextReminderAt`, with backfill. First time this app has been versioned.

## Decisions

- **Preventatives are `Medication`s, not `ActivityType`s** — they carry a dosage and a prescriber. Dropped `Flea & tick` / `Deworming` from `ActivityStore.defaultSeeds` so new pets don't get duplicate tiles; existing rows untouched.
- **Catalogue, not due-list.** A due-list can only show what the app *believes* is due, and that belief had already been shown to go stale. A catalogue always offers a way to log something you just did.
- **Additive migration, not a rename.** Core Data supports a renaming identifier, but `NSPersistentCloudKitContainer` would publish the new name as a new CloudKit field and keep the old one forever — CloudKit's production schema is append-only. A rename takes migration risk and still carries both fields.
- **Backfill keyed on `nextReminderAt == nil`**, not a run-once flag, so records arriving later from a device still on v1 get carried across.
- **Upcoming includes everything with a due date**, accepting that doses and activities appear both as a tile and in the list — chosen over a duplication-free split so one list answers "what's coming" completely.

## Issues

- **`Medication.startedAt` never meant "started at."** It held the next reminder date and every dose log overwrote it. Six bugs traced to that single lie: the fires-once reminder; Home's quick action logging without advancing the cadence; `deleteDose` as a half-undo; Undo recomputing instead of restoring (silently doing nothing when the undone dose was the only one); "Recent activity" listing future dates as history; the Timeline feed opening on future-dated records. Every earlier fix was downstream of the same name — hence the migration.
- **`context.object(with:)` returns a fault, never nil, for a deleted row.** The `guard let ... as?` protected nothing; the next property access threw `NSObjectInaccessibleException`. `existingObject(with:)` throws instead, so `try?` yields the nil the guard expects. This was in the plan *I* wrote; a reviewer caught it.
- **`Button` + `.onLongPressGesture` can both fire on one press** — long-press to backdate would have logged at `now` first, then again from the sheet. Replaced with `contentShape` + separate gestures.
- **UI tests have been failing since before this session** (3/4 `CaptureFlowTests`, verified against `7ca4525`) and **CI has never run them** — `ios-tests.yml` scopes to `-only-testing:PetHomepageTests`. I initially blamed today's restructure; checking the pre-session commit disproved that.
- **Local test runs truncated constantly** (168/361/172 of 420, or a runner hang), always with 0 failures. The machine had ~105 `claude` processes alive, 69 owned by another account. Agent spawns also hit `fork failed: Device not configured`.
- **`MedFrequency(parsing:)` silently degrades unrecognised text to daily** — `"1x/month"`, `"q30d"` become every-day reminders. Untouched; a real risk for AI-extracted records.

## What to remember

- **`startedAt` still exists in the schema and always will** — CloudKit can abandon a field but never remove it. Nothing writes it except the backfill. Read `nextReminder`.
- **CloudKit schema changes need a manual deploy.** `NSPersistentCloudKitContainer` creates schema only in Development, and only when a build containing the field actually runs signed into iCloud. TestFlight uses Production. Order: run from Xcode → CloudKit Console → Deploy Schema Changes → Production → *then* ship. Get it wrong and the field fails to sync **silently**.
- **Activity reminders are keyed by the LOG ENTRY's id, not the type's.** A new entry does not replace the previous entry's pending reminder — it must be cancelled explicitly, as `ActivityLogEditViewModel`, `CaptureReviewViewModel` and `TimelineViewModel` all do.
- **A one-shot trigger on a past date never fires.** Any "due date" reminder needs either a repeating trigger or a resync that re-arms it.
- The suite has two documented flakes, both surfacing as exit 65 with **zero** test failures: a nondeterministic Core Data harness crash, and `runner hung before establishing connection`. Judge by `Executed N tests, with M failures`, never the exit code.

---

## Commits

- `7bd2a0a` fix(ios): weekly/monthly medication reminders repeat instead of firing once
- `059c49d` feat(ios): log a dose from the medication notification, and resync on launch
- `597f595` docs: design for the Home cadence catalogue
- `3f90be1` docs: implementation plan for the Home cadence catalogue
- `deafa2f` feat(ios): CadenceItem value type with day-granularity due state
- `2a0598d` refactor(ios): one MedicationDoseLogger; fixes Home's dose quick action
- `5ac6941` feat(ios): CadenceCatalogueViewModel aggregates medications + activity types
- `4345a77` fix(ios): use existingObject(with:) in CadenceCatalogueViewModel.log
- `e3b3fda` feat(ios): CadenceTile view with due badge
- `ef85fd0` fix(ios): use Theme.danger for the overdue badge tint
- `66bcac0` feat(ios): Home shows a cadence catalogue instead of the Upcoming card
- `9339dd8` feat(ios): Home is the first tab and the launch default
- `01c60e4` feat(ios): stop seeding Flea & tick / Deworming as activity types
- `3b686f5` fix(ios): three defects the final whole-branch review caught
- `ef6c955` feat(ios): tiles become shortcuts; care activities get their own detail screen
- `9df6cad` fix(ios): deleting a dose rolls the cadence back instead of half-undoing
- `e91f5cf` fix(ios): make the care detail screen reachable without logging first
- `799f91d` fix(ios): due reminders resync on launch and re-nag when overdue
- `8c32230` fix(ios): doses appear in the timeline; Recent activity shows history, not reminders
- `bbbd311` feat(ios): Home separates Upcoming reminders from Recent activity
- `dd2c149` feat(ios): Timeline is history only; Schedule gains an Upcoming subtab
- `ca8c9a6` feat(ios): v2 model — Medication.nextReminderAt replaces the mis-named startedAt
