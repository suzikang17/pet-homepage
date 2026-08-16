# Home cadence catalogue — design

**Date:** 2026-08-16
**Status:** approved, ready for implementation planning

## Problem

Everything in this app that recurs is logged through a different door. A
preventative dose lives behind four taps in the Timeline; a bath lives in the
Activities list; a daily walk lives in Schedule. There is no single surface that
answers "what does this pet need, and how do I record that I did it."

Home (`PetProfileView`) has an **Upcoming** card that gestures at this and falls
short in two specific ways:

- It is built from `TimelineViewModel.dueSoon(within:)`, which filters the
  Timeline stream — *past log entries* carrying a `nextDue`. A recurring thing
  that has never been logged has no entry, so it never appears. A `Bath` type you
  have not yet logged is invisible on the surface meant to remind you to bathe.
- Its filter is `due >= now`, so **overdue items are excluded**. Something three
  days late vanishes from the only card that shows what is due.

It is also read-only and capped at five rows. You cannot act on it.

A related failure motivated this work: monthly preventative reminders fired once
and went silent, and the *only* thing that re-armed them was logging the dose
in-app through that four-tap journey. Reminder delivery is fixed separately (see
`fix/medication-repeating-reminders`), but the lesson stands — if the only way to
record something is buried, the record rots.

## Decisions taken

Settled with the user before this document:

1. **Catalogue, not due-list.** A tile per recurring thing, always present, even
   when nothing is due. A due-list can only show what the app *believes* is due,
   and that belief has already been demonstrated to go stale. A catalogue always
   offers a way to log "I bathed her today" regardless.
2. **Preventatives are `Medication`s.** They are prescribed drugs with a dosage
   and a prescriber. `ActivityType` carries none of that.
3. **Drop the clashing seeds.** `Flea & tick` and `Deworming` leave
   `ActivityStore.defaultSeeds`; existing rows are untouched.
4. **Home becomes the first tab**, Schedule second.
5. **The grid lives inside `PetProfileView`**, not a replacement screen.
   `PetProfileView` is the sole host of the pet switcher (avatar → Switch pet /
   Add pet / Change photo) and the only entry to `SettingsView`. Replacing it
   would make both unreachable. Embedding also matches PRODUCT.md's framing — "a
   homepage for your pet" reads better as *hero + what needs doing* than as a
   bare grid.
6. **The catalogue replaces the Upcoming card.** Showing both would list `Bath`
   twice, and the catalogue is a strict superset: it includes never-logged items
   and overdue ones, both of which Upcoming drops.

## Scope

### In

- A `CadenceItem` value type unifying `Medication` + `ActivityType`.
- A `CadenceCatalogueViewModel` producing an ordered list of tiles.
- A tile grid section inside `PetProfileView`, replacing `upcomingCard`.
- One-tap logging from a tile; long-press to log at a chosen time.
- Tab reorder and launch-default change.
- Removing two entries from `ActivityStore.defaultSeeds`.

### Out (deliberately)

- Tile reordering, per-tile settings, and an "add new" affordance —
  `ActivityTypesView` already owns catalogue management.
- Any Core Data schema change. Every field this needs already exists.
- `TimelineViewModel.dueSoon` itself. It becomes unused by Home; leave it and its
  tests alone rather than widening this change.
- Fixing the vaccination / vet-cadence / activity one-shot reminder flaw. Real,
  tracked, out of scope here.

## Architecture

### `CadenceItem` — the unifying value type

A plain struct, not a Core Data entity. Both sources project into it, so the view
never branches on origin.

```swift
struct CadenceItem: Identifiable, Equatable {
    enum Source: Equatable {
        case medication(NSManagedObjectID)
        case activityType(NSManagedObjectID)
    }
    let id: UUID              // the underlying entity's `id`
    let source: Source
    let name: String          // drugName, or ActivityType.name
    let iconName: String      // SF Symbol
    let subtitle: String?     // dosage for medications; nil for activities
    let lastDone: Date?
    let nextDue: Date?
}
```

`Source` carries an `NSManagedObjectID` rather than the object, so the value type
stays inert and the view model re-fetches on the main context when acting.

### Due state — derived, never stored

```swift
enum DueState: Equatable {
    case overdue(days: Int)
    case dueToday
    case dueIn(days: Int)
    case noCadence        // nextDue == nil
}
```

Computed by comparing `nextDue` to an injected clock at **day granularity**, via
`Calendar.dateComponents([.day], from: startOfDay(now), to: startOfDay(nextDue))`.
Day granularity matters: a dose due at 09:00 must not read "overdue" at 09:01.

The badge is decoration. **Every tile is tappable in every state** — that is the
point of a catalogue.

### Sources

| | `Medication` | `ActivityType` |
|---|---|---|
| Included when | `endedAt == nil \|\| endedAt > now` | `isArchived == false` and `defaultIntervalDays > 0` |
| Fetched by | `MedicationStore.medications()` | `ActivityStore.types(includeArchived: false)` |
| `lastDone` | `LogStore.lastDose(for:)` | `LogStore.latestLog(of:)?.performedAt` |
| `nextDue` | `Medication.startedAt` (this model's "next reminder date") | `LogStore.latestLog(of:)?.nextDueAt` |
| `iconName` | category-derived | `ActivityType.iconName` |
| Log action | `LogStore.logDose(for:at:note:)` | `LogStore.logActivity(type:performedAt:note:intervalDays:)` |

**Medications without a parseable cadence still appear.** `MedFrequency(parsing:)`
falls back to daily for unrecognized text, so there is no way to distinguish
"genuinely daily" from "we could not parse it." Excluding on that basis would
silently hide real medications.

**Activities with `defaultIntervalDays == 0` are excluded.** Those are one-off log
types with no cadence, and `nextDueAt` is nil for them by construction.

### Ordering

Overdue first (most overdue at top), then due-today, then ascending `nextDue`,
then `noCadence` last, ties broken by name. Urgency surfaces without the layout
reshuffling day to day — the grid is stable except when something crosses a
boundary.

### Logging

A tap calls `CadenceCatalogueViewModel.log(_ item: CadenceItem, at: Date = now())`,
which re-fetches the entity by `NSManagedObjectID`, calls the matching store
method, and reloads.

For medications it must **mirror `LogDoseViewModel.confirm()` exactly**: log the
dose, advance `medication.startedAt` by one cadence interval anchored at the
scheduled time, save, and re-sync via `MedicationReminderScheduler`.
`MedicationActionHandler.logDose` already duplicates this rule for the
notification path. **Extract it into one shared type during implementation** —
three copies of the cadence-advance rule is one too many, and that class of drift
is what produced the original reminder bug.

For activities: `logActivity(type:performedAt:note:intervalDays:)` with the type's
`defaultIntervalDays`, which sets `nextDueAt` for free, then re-sync via
`DueReminderScheduler.syncActivity`.

Same same-calendar-day dedupe as the notification handler.

## Files

**New**
- `ios/PetHomepage/Features/PetProfile/CadenceItem.swift` — value type + `DueState`
- `ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift`
- `ios/PetHomepage/Features/PetProfile/CadenceTile.swift`
- `ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift`

**Modified**
- `ios/PetHomepage/Features/PetProfile/PetProfileView.swift` — grid section replaces `upcomingCard`
- `ios/PetHomepage/App/ContentView.swift` — move the `ScheduleView` block after `PetProfileView`; change `selectedTab` default from `3` to `0`
- `ios/PetHomepage/Stores/ActivityStore.swift` — drop two `defaultSeeds` entries
- `ios/PetHomepage/Notifications/MedicationNotificationActions.swift` — extract the shared cadence-advance

## Testing

`CadenceCatalogueViewModel` takes injected stores and an injectable `now`, so
every case is a unit test with no view involved.

- Both sources produce tiles; one pet's medications and activities coexist.
- Ended medications and archived activity types are excluded.
- `defaultIntervalDays == 0` activity types are excluded.
- A never-logged activity type still produces a tile (`lastDone == nil`) — the
  case the Upcoming card gets wrong.
- An overdue item is present and sorts first — the other case Upcoming gets wrong.
- `DueState` boundaries: due yesterday → `.overdue(1)`; due today at any hour →
  `.dueToday`; due tomorrow → `.dueIn(1)`; nil `nextDue` → `.noCadence`.
- Ordering: overdue precedes due-today precedes future precedes `noCadence`.
- Logging a medication records exactly one dose and advances `startedAt` by one
  interval at the scheduled time.
- Logging twice in one day records one dose (dedupe).
- Logging an activity sets `nextDueAt` to `performedAt + defaultIntervalDays`.

## Risks

- **Tab tags are load-bearing, but display order is not.** `NotificationRouter.Tab`
  maps raw values to tab tags (`home = 0, timeline = 1, schedule = 3,
  careTeam = 4`). The reorder changes display order only; **tags must not move**
  or every deep link breaks. Verified: the UI tests select tabs by *label*
  (`app.tabBars.buttons["Home"].tap()`), so the reorder does not break them.
  `PetSwitcherTests` carries a now-stale comment ("The app now launches on the
  Schedule tab") that should be corrected.
- **`Medication.startedAt` is overloaded.** It means "next reminder date," not
  "started at." The catalogue surfaces it as next-due, making the misnomer more
  visible. Renaming is a schema migration and is out of scope; the shared
  cadence-advance type should document it in one place.
- **Duplicate tiles for existing users.** Anyone who already has the seeded
  `Flea & tick` / `Deworming` types *and* tracks the same drug as a Medication
  sees two tiles. Accepted: dropping the seeds fixes new pets, and users can
  archive theirs from `ActivityTypesView`.
- **`PetProfileView` is 286 lines and growing.** Adding a grid section pushes it
  further. The tile and view model are separate files specifically to keep the
  view a layout shell; if it crosses ~350 lines, extract `atAGlance` and
  `quickActions` too.
