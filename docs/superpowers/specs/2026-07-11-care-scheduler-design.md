# Care Scheduler — Design

**Date:** 2026-07-11
**Status:** approved (data model approved explicitly; remaining sections approved via "keep going all the way to implement")

## Summary

A new **Schedule** tab where each pet gets a day-by-day care checklist (walk, feeding times, wind down, training…). Tasks are defined on a weekly template (day-of-week aware), fire local notifications at their times, can be checked off per day, and each check-off can capture a photo/note that lands in the unified Timeline.

## Decisions made during brainstorming

| Question | Decision |
|---|---|
| Fixed daily template vs day-of-week | **Day-of-week aware** (weekday mask per task) |
| Per-pet vs household schedule | **Per-pet** (follows active pet, like every other tab) |
| Photo capture on check-off | **Optional, one tap away** — instant check-off, then a transient toast ("Done! 📷 Add a photo?"); photo can also be added later from the completed row |
| History integration | **Unified Timeline** — completions are `LogEntry` records (new kind `routine`) with a filter chip to hide routine noise |
| Day tweaks | **Template + day tweaks** — one-off tasks for a single day, skip-a-task-for-today |
| Template edits vs history | **Versioned via per-task effective windows** — editing never rewrites past days |

## Architecture (Approach B + effective windows)

The weekly template is the source of truth; a day's checklist is **computed**, never materialized. Only deviations are stored (completions, skips, one-offs). This is CloudKit-safe by construction — no midnight materialization job, no multi-device dedup races — and it reuses the existing `LogEntry`/photo/Timeline machinery.

## Data model

Two new Core Data entities + a small `LogEntry` extension. All CloudKit-compatible (optional attributes with defaults, UUID ids).

### `RoutineTask` — versioned weekly template row, per pet

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | row identity |
| `lineageID` | UUID | stable across versions of "the same task"; completions/skips key on this |
| `name` | String | "Morning walk" |
| `iconName` | String | SF Symbol, default `pawprint` |
| `categoryRaw` | String | reuses `ActivityCategory` (care/play/feeding/training/health/other) |
| `hour` / `minute` | Int64 | due time + notification time |
| `weekdayMask` | Int64 | bit 0 = Sunday … bit 6 = Saturday; `0b1111111` = daily |
| `effectiveFrom` | Date | day-granular; the first day this version applies |
| `effectiveUntil` | Date? | nil = still active; day-granular, exclusive |
| `sortOrder` | Int64 | tiebreak within the same time |
| `pet` | →Pet | required scope |

- **Edit** = close current row (`effectiveUntil = today`) + insert successor (same `lineageID`, `effectiveFrom = today`). Past days keep computing against the old row.
- **Delete** = close current row. History intact.
- **One-off task** for a single day = a `RoutineTask` whose window covers exactly that day (`effectiveFrom = day`, `effectiveUntil = day + 1`, `weekdayMask` = that weekday's bit, fresh `lineageID`). No second entity needed.

### `RoutineSkip` — "skipped for this day" deviation

| Attribute | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `date` | Date | day-granular (start of day) |
| `taskLineageID` | UUID | which task lineage is skipped |
| `pet` | →Pet | |

Existence = skipped. Un-skip deletes the record. Skipped slots render as "Skipped" (distinct from unchecked/missed).

### `LogEntry` extension

- New optional attribute `routineLineageID: UUID?`.
- New kind raw value `"routine"`.
- Check-off writes a `LogEntry` with the task's `name`, icon and scheduled time **copied on** (existing pattern: editing a template never rewrites history), `date` = the moment of completion, `routineLineageID` + day linking it back to its slot. Photos/notes attach via the existing `Photo` relationship and edit affordances.
- Un-check deletes the `LogEntry` (same as deleting any log).

### Day computation (pure function, unit-testable)

```
tasks(for day) = RoutineTasks where pet == active
                 && effectiveFrom <= day && (effectiveUntil == nil || day < effectiveUntil)
                 && weekdayMask contains weekday(day)
sorted by (hour, minute, sortOrder)
each slot overlaid with:
  completion = LogEntry(kind: routine, routineLineageID == lineageID, same day)
  skip       = RoutineSkip(taskLineageID == lineageID, date == day)
```

## UI

**Fifth tab: "Schedule"** (SF Symbol `checklist`), inserted after Timeline. Tab layout becomes Home / Timeline / Capture(pseudo) / Schedule / Care Team.

- **Day pager:** date header with ‹ › chevrons and a "Today" shortcut; swipe between days. Defaults to today. Past and future days both browsable.
- **Task rows:** time-sorted; icon, name, due time, check circle. Completed rows show a checkmark, the completion time, and a photo thumbnail when one is attached. Skipped rows show a muted "Skipped" state.
- **Check-off:** tap the circle → instant completion + haptic → toast slides up for ~4s: "Done! Add a photo?" → tap opens the camera (existing `CameraPicker` + `ImageDownscaler`), photo attaches to the completion `LogEntry`. Ignoring the toast costs nothing; a completed row's context menu / detail also offers "Add photo" and "Add note" later.
- **Un-check:** tap again → confirm → deletes the completion entry (and its photos).
- **Skip today:** swipe action on an unchecked row. Un-skip via swipe on a skipped row.
- **One-off task:** "+" in the toolbar adds a task to the currently viewed day only (name, icon, category, time).
- **Future days:** browsable preview; check-off disabled (can't complete the future). Past days: check-off allowed (forgot-to-log).
- **Template editor:** toolbar "Edit routine" → list of active `RoutineTask`s (grouped by time of day: Morning/Afternoon/Evening) with add/edit/archive. Task form: name, icon, category, time, weekday picker (7 toggles with "Every day" shortcut). Uses the existing `BrandFormSheet` styling.
- **Seeding:** per-pet, idempotent, CloudKit-safe (same de-dupe-by-name approach as `ActivityStore.seedDefaultsIfNeeded`): Breakfast 7:00 daily, Morning walk 8:00 daily, Dinner 18:00 daily, Wind down 21:00 daily, Training 17:00 Tue+Thu (shows off day-of-week from minute one).

## Notifications

- New `ReminderKind.routine` in the existing `NotificationScheduling` layer.
- `PendingReminder` gains a `repeats` flag so a non-nil `dateComponents` can express a **repeating weekly** trigger (`[.weekday, .hour, .minute]`, repeats: true) in addition to today's one-shot and daily cases. Back-compat shims preserved (existing initializers default the flag).
- New `RoutineReminderScheduler` (same pure/testable shape as `DueReminderScheduler`):
  - Task active on **all 7 days** → one daily repeating trigger (1 notification slot).
  - Otherwise → one weekly repeating trigger per selected weekday. Request ID: `routine-reminder-<taskID>-w<weekday>` (extends `ReminderIdentifier` parsing).
  - Sync on template save/close/delete: schedule active version, cancel closed ones. Idempotent per (task, weekday).
- Copy names the pet: "Time for Bella's morning walk 🐾" (title "Morning walk").
- **Known v1 limitation (accepted):** skipping a task for today does not suppress that day's already-scheduled notification; and iOS's 64-pending-notification budget is shared — a schedule of ~10 tasks with mixed weekdays stays comfortably inside it, but we document the constraint in code.

## Timeline integration

- Kind `routine` entries appear in the Timeline stream with a **"Routine" filter chip** (same chip mechanism as Diary) so daily noise is one tap to hide. Photos surface in the Photos view mode alongside everything else.
- `LogStore.backfillKindsIfNeeded` untouched — new kind only ever written going forward.
- Mirror/web dashboard: out of scope for v1 (snapshot builder unchanged); noted as follow-up.

## New files

```
ios/PetHomepage/Models/RoutineTask.swift
ios/PetHomepage/Models/RoutineSkip.swift
ios/PetHomepage/Stores/RoutineStore.swift          // CRUD, versioned edits, day computation, seeding
ios/PetHomepage/Notifications/RoutineReminderScheduler.swift
ios/PetHomepage/Features/Schedule/ScheduleView.swift        // tab: day pager + list
ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift
ios/PetHomepage/Features/Schedule/RoutineTaskEditView.swift // template + one-off form
ios/PetHomepage/Features/Schedule/RoutineTemplateView.swift // "Edit routine" list
```
Modified: Core Data model (2 entities + LogEntry attr), `ContentView` (5th tab + store wiring), `NotificationScheduling` (`.routine`, `repeats` flag, identifier parsing), Timeline chip, `LogEntry` kind.

## Testing

Unit (mirrors existing store/scheduler test style, in-memory Core Data + `FakeNotificationScheduler`):
- **Day computation:** weekday mask, effective windows (edited task: old day shows old version, today shows new), one-offs appear only on their day, skip overlay, completion overlay, sort order.
- **Versioned edit:** edit closes + spawns successor sharing `lineageID`; delete closes; past-day computation unaffected.
- **Seeding:** idempotent, per-pet, de-dupes by name.
- **Check-off:** writes `LogEntry` kind `routine` with copied name/time + lineage; un-check deletes; photo attaches.
- **RoutineReminderScheduler:** 7-day task → single daily trigger; partial week → one weekly trigger per day; edit re-syncs; delete cancels; identifier round-trips.

UI test (existing `--uitest` seams): Schedule tab renders seeded tasks; check-off marks the row complete.

## Out of scope (v1)

- Household/multi-pet combined view; suppressing notifications on skip; streaks/stats; mirror dashboard sync; day-of-week templates per season/date range.
