# Activities (logged care events) + Camera Capture — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorm), pending implementation plan
**Scope:** iOS app (`ios/PetHomepage`). The iOS app is the system of record (Core Data + CloudKit); Convex is only the read-only desktop mirror and is **out of scope** for this round.

## Problem

The app can log medical records (vaccines, vet visits, meds, health markers, symptoms), but there is no way to log **recurring care activities** — bath, nail trim, grooming, teeth brushing, flea/tick, deworming, etc. These are point-in-time events that:

- happen repeatedly and should be tracked as a history,
- have a sane recurring cadence ("bathe every ~4 weeks"),
- should surface in Home's **"Due soon"** and fire a reminder, like vaccines and vet visits already do.

Separately: photo attachment today is **library-only** (`PhotosPicker`). Users want to **take a photo with the camera** when logging.

## Decisions

1. **User-defined activity types, pre-seeded with sane defaults.** Not a hardcoded enum, and not a setup chore — a real `ActivityType` entity that ships pre-populated with editable starter types so logging works with zero setup.
2. **Definition vs. occurrence are separate entities, named after the existing `Medication` → `DoseLog` convention:** `ActivityType` is the kind of thing; `ActivityLog` is each time it happened. This split is what makes pre-seeding, custom-before-first-log, rename, and archive possible.
3. **Category is a fixed enum, not a third entity.** Each `ActivityType` belongs to an app-defined `ActivityCategory` (Care, Play, Feeding, Training, Health, Other). Unlike types, categories are a small stable set nobody needs to create/rename/archive — so it mirrors the existing `MarkerType` enum (stored as `categoryRaw`, `.other` fallback) rather than adding entity sprawl. It groups the type picker into sections and gives the Timeline a coarse filter.
4. **Cadence lives per-type as a default, copied onto each occurrence.** Mirrors the existing `Vaccination` pattern (each occurrence carries its own `nextDueAt`), so cadence needs no separate schedule entity and no migration gymnastics.
5. **Reuse the existing notification system** (`DueReminderScheduler` / `NotificationScheduling`) rather than inventing a new one.
6. **Camera capture is a cross-cutting improvement** to the shared photo components, so every record type (and the new Activities) gets it at once.

## Non-goals (this round)

- Adding Activities to the Convex `MirrorSnapshot` / desktop dashboard.
- Per-activity custom reminder times (uses the scheduler's default hour/minute, like vaccinations).
- Multi-pet scoping beyond the existing single-pet (v1) model.

---

## Data model

Two new Core Data entities, plus one new relationship on `Photo`.

### `ActivityType` (the definition — user-manageable)

| field | type | purpose |
|---|---|---|
| `id` | UUID | identity |
| `name` | String | "Bath", "Nail trim", custom names |
| `categoryRaw` | String | `ActivityCategory` rawValue (`.other` fallback) |
| `iconName` | String | SF Symbol name |
| `defaultIntervalDays` | Int (0 = no cadence) | sane default repeat interval |
| `sortOrder` | Int | ordering in pickers/lists |
| `isArchived` | Bool | hide without deleting; preserves history |
| `logs` | [ActivityLog] | inverse relationship |

### `ActivityLog` (one occurrence)

| field | type | purpose |
|---|---|---|
| `id` | UUID | identity |
| `performedAt` | Date | when it happened |
| `note` | String? | optional note |
| `intervalDays` | Int (0 = no cadence) | copied from the type at log time; editable per occurrence |
| `nextDueAt` | Date? | `performedAt + intervalDays` when interval > 0, else nil; stamped on save |
| `activityType` | ActivityType? | the definition this log belongs to |
| `pet` | Pet? | scoping (single-pet v1) |
| `photos` | [Photo] | new inverse on `Photo` |

### `ActivityCategory` (fixed enum, not an entity)

Mirrors `MarkerType`: a `String`-backed enum with `displayName`, an SF Symbol, and a `.other` fallback for unknown raw values.

| case | displayName | iconName (provisional) |
|---|---|---|
| `care` | Care | `heart` |
| `play` | Play | `tennisball` |
| `feeding` | Feeding | `fork.knife` |
| `training` | Training | `figure.walk` |
| `health` | Health | `cross.case` |
| `other` | Other | `pawprint` |

### `Photo` — add one relationship

Add `activityLog: ActivityLog?` (optional, maxCount 1, Nullify) mirroring the existing per-parent relationships (`vetVisit`, `medication`, `vaccination`, `diaryEntry`, `pet`), plus the inverse `photos` on `ActivityLog`.

---

## Seeding (zero-setup defaults)

On first use, seed a starter set of editable `ActivityType` rows so the user can log immediately:

| name | category | defaultIntervalDays | iconName |
|---|---|---|---|
| Bath | care | 30 | `shower` |
| Nail trim | care | 21 | `scissors` |
| Teeth brushing | care | 1 | `mouth` |
| Brushing / coat | care | 7 | `comb` |
| Flea & tick | health | 30 | `ladybug` |
| Deworming | health | 90 | `pills` |
| Grooming | care | 42 | `dog` |

(SF Symbol names are provisional; verify each exists at build time and substitute a close match if not.)

Seeded rows are **real, editable rows** — the user can rename them, change cadence, or archive ones they don't want.

### CloudKit-safe seeding

The store syncs via CloudKit, so a naïve "seed on first launch per device" double-seeds when a second device syncs. Approach:

- Seed **lazily** the first time the Activities screen is opened (not at app launch).
- Guard the seed so it runs **once per iCloud account** (e.g. a flag that is itself a synced record, or a check that no non-archived default types already exist after the initial cloud import settles).
- **De-dupe by name on load** as a backstop: if two same-named default types exist, collapse to one and re-point logs.

The exact guard mechanism is an implementation-plan detail; the requirement is: **default types appear exactly once per account, and never block first-use logging.**

---

## Store — `ActivityStore`

Manages both `ActivityType` and `ActivityLog` (they're tightly coupled — you can't log without a type). Mirrors `HealthMarkerStore` (same `context` + `petStore` constructor, single-pet scoping). Responsibilities:

- **ActivityType CRUD:** list (non-archived, by category then `sortOrder`), create (name required; category defaults to `.other`, icon defaults to a generic paw e.g. `pawprint`, interval defaults to 0/no-repeat), update, archive. A type with logged occurrences cannot be hard-deleted — only archived.
- **Log:** `log(type:performedAt:note:intervalDays:)` — copies `intervalDays` from the type unless overridden, stamps `nextDueAt`, sets `pet` via `petStore.ensurePet()`, saves.
- **Queries:** `logs()` (all, newest first), `logs(of type:)`, `latestLog(of type:)`.
- **Reminder sync on log:** schedule the new log's reminder and **cancel the prior latest-of-type reminder** so a type never has two pending reminders. `delete(_:)` cancels the log's reminder.
- **Seeding:** `seedDefaultsIfNeeded()` per the CloudKit-safe rules above.

---

## Reminders — extend the existing system

- Add `case activity` to `ReminderKind` (`NotificationScheduling.swift`) and to the `ReminderIdentifier.parse` kind loop.
- Add `activityReminder(for: ActivityLog) -> PendingReminder?` to `DueReminderScheduler` — a near-copy of `vaccinationReminder`: returns nil when there's no `nextDueAt`/`id`; otherwise a one-shot on `nextDueAt` at the scheduler's default hour/minute. Title/body e.g. *"Bath due"* / *"Time for {pet}'s bath"*.
- Add `syncActivity(_:)` and `cancelActivity(_:)` mirroring the vaccination methods. Keyed per log `id` (same as vaccinations).

---

## Timeline integration

The Timeline is already a unified projection ("a typed thing that happened on a date, maybe with a next-one-due"). Add Activities to it:

- `TimelineKind`: add `case activity` (label "Activities", SF Symbol e.g. `shower`).
- `TimelineReference`: add `case activity(ActivityLog)`.
- `TimelineItem(activity:)` mapping — `date = performedAt`, `title = activityType.name`, `nextDue = nextDueAt` (so it flows into `dueSoon(...)` automatically).
- Inject `ActivityStore` into `TimelineViewModel`; add its logs in `load()`; handle the `.activity` branch in `delete(_:)` (cancel the reminder, delete the log).

**"Due soon" semantics:** the latest log of each type is the one with a live `nextDueAt`, so it's the one that surfaces. Older logs have past due dates and naturally drop out.

---

## UI

- **Log / Edit sheet** (new log): activity-type picker **grouped into sections by category**, an inline **"+ New activity"** affordance (name + category; icon + cadence optional, cadence pre-filled from a sane default), date, note, a cadence row ("Repeat every __ days", pre-filled from the type, toggle-off allowed), and the photo section. New custom types default to category `.other` if the user doesn't pick one.
- **Activity types management** (lightweight): list of types **sectioned by category**, with rename / change category / change cadence / change icon / archive. Reachable from the Activities list or Settings.
- **Timeline** optionally exposes category as a coarse filter (in addition to the per-`TimelineKind` filter).
- **List / Detail:** follow existing list+detail patterns. Detail for a type shows its log history plus "last done / next due."
- Follow `BrandFormSheet`, `Theme`, and existing list/detail conventions.

---

## Camera capture (applies to all photo sections)

- New `CameraPicker` — a small `UIViewControllerRepresentable` over `UIImagePickerController(sourceType: .camera)`. The captured `UIImage` flows through the **same** downscale → JPEG (`preparingThumbnail` 1600px, 0.8 quality) → `onPick` / `onAdd` path already in the components.
- Add a **"Take photo"** button (camera icon) beside "Add photos" in **both** `PendingPhotoSection` and `PhotoStripSection`, gated on `UIImagePickerController.isSourceTypeAvailable(.camera)` (so it's hidden on Simulator).
- Lift the shared downscale/persist helper out of the two components so the camera and library paths don't duplicate it.
- **Permissions:** `NSCameraUsageDescription` already exists in `project.yml` (added for the pairing QR scanner). Broaden its wording to also cover attaching photos to records.

---

## Testing

- `ActivityStoreTests` — mirrors `HealthMarkerStoreTests` / `DoseLogStoreTests`: type create/list/archive, logging stamps `nextDueAt`, seeding is idempotent (runs once; no duplicates on second call).
- `DueReminderSchedulerTests` — add cases for `activityReminder` (nil without due date; correct one-shot date) using the existing `FakeNotificationScheduler`.
- `TimelineViewModelTests` — activity logs appear in the stream and in `dueSoon`.

---

## Build sequence (for the implementation plan)

1. Core Data model: add `ActivityType`, `ActivityLog`, the `ActivityCategory` enum, and the `Photo.activityLog` relationship; generated NSManagedObject subclasses.
2. `ActivityStore` (+ tests) including seeding.
3. Notification layer: `ReminderKind.activity`, parse loop, `DueReminderScheduler` methods (+ tests).
4. Timeline integration (+ tests).
5. UI: log/edit sheet, type management, list/detail; wire stores into the app composition root.
6. Camera capture: `CameraPicker`, shared helper extraction, buttons in both photo sections, usage-string wording.
