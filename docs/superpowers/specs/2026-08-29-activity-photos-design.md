# Activity photos — design

**Date:** 2026-08-29
**Status:** approved, ready for implementation planning

## Problem

The app knows a great deal about a pet and shows almost none of it. Home renders
SF Symbols; the Timeline renders rows of text; a reminder arrives as a line of
copy. Nothing on any of these surfaces distinguishes *this* dog from any other
install of the app.

Photos are the obvious material, and much of the plumbing already exists:

- `Photo` (`Models/Photo.swift`) stores JPEG data and relates to `LogEntry`,
  `Medication`, and `Pet`.
- `PendingPhotoSection` attaches photos while creating a record;
  `PhotoStripSection` attaches them to one that already exists.
- `ActivityLogEditView` already carries a `PendingPhotoSection`, so logging a
  bath can attach photos today.
- `ScheduleView.swift:445` already shows a 44pt thumbnail on completed routine
  rows, with a camera button when there is none.

What is missing is not upload. It is **connection**. No surface asks "what does
this activity look like," because nothing designates a photo as representing an
activity, and three structural facts get in the way.

### Obstacle 1 — a live walk has no `LogEntry`

`WalkSession` is persisted in `UserDefaults` under `walk.activeSession`. The
`LogEntry` is written only at `end()` (`Walk/WalkSessionStore.swift:49`). A
camera button on the in-progress banner therefore has nothing to attach to at the
moment of capture.

### Obstacle 2 — walk photos would land in two disconnected pools

| Origin | Resulting entry |
|---|---|
| Checking off a walk slot in Schedule | `kind = .routine`, `routineLineageID` set, `activityType` **nil** (`Stores/RoutineStore.swift:401`) |
| An auto-detected walk with no matching slot | `kind = .activity`, `activityType = Walk` |

"Every photo of a walk" has no single query. Bath, by contrast, is one clean
pool keyed on `activityType`.

### Obstacle 3 — Walk has no Home tile, deliberately

`WalkActivityResolver.swift:27` creates the Walk type with
`defaultIntervalDays: 0`, and `CadenceCatalogueViewModel` filters to
`defaultIntervalDays > 0`. Bath (interval 30) earns a tile; Walk is excluded
because it genuinely has no cadence. The cadence grid means "things on a
schedule," and a walk is not one of those.

### Obstacle 4 — stored images are far too large for the small surfaces

`ImageDownscaler.scaledJPEG` stores at 1600px / quality 0.8 — roughly 200–500 KB
per photo. Decoding that for a 44pt row thumbnail in a scrolling Timeline will
drop frames. Separately, `UNNotificationAttachment` requires a **file URL** and
cannot accept `Data` out of Core Data at all.

## Decisions taken

Settled with the user before this document:

1. **Daily shuffle, seeded by date.** A cadence tile shows a photo picked from
   that activity's pool, re-picked once per day. Rejected alternatives: newest
   photo (a blurry accident becomes the tile's face until the next log), a pinned
   cover (a setup step that goes stale), re-roll on every appearance (changes
   under your finger — reads as a bug), and a timed crossfade (animation competing
   with due badges, for battery and decode cost).
2. **A separate "Recent moments" strip on Home**, above the cadence grid, rather
   than forcing Walk into the grid. This is what lets walk photos reach Home
   without redefining the catalogue as something other than a cadence catalogue.
   Explicitly rejected: relaxing the grid filter to admit photogenic-but-uncadenced
   types, and giving Walk an artificial interval — the latter would start
   generating "1 day late" badges and new due reminders, turning a walk into a
   guilt trip.
3. **Resolve the two-pool split read-side.** `LogEntry.activityType` already
   exists, so unifying at write time needs no schema change — but it would
   silently fold routine walks into `latestLog(of:)` and shift Walk's due
   computation. This codebase carries visible scar tissue about due-date drift, so
   the union happens at read time and blast radius stays at zero.
4. **No Core Data schema changes anywhere in this work.** Pushing a CloudKit
   schema requires a Mac with an iCloud-signed-in simulator and then console
   promotion, with logs that mislead. A design that avoids it is worth real effort.
   This rules out a `thumbnailData` attribute on `Photo`.
5. **Disk thumbnail cache, not in-memory.** It survives launches and — decisively
   — hands notification attachments the file URLs they require.
6. **Mid-walk capture only, for walks.** A camera button on the in-progress
   banner. Rejected: querying the photo library for shots taken inside the walk's
   time window. It is the more magical option and would work retroactively, but it
   demands full `NSPhotoLibraryUsageDescription` access, which this app has never
   requested — `PhotosPicker` today is out-of-process and permission-free. Not
   worth a new permission prompt in this pass.

## Architecture

Four new units, each independently testable, none touching the Core Data model.

### `PhotoPool` — "photos of X"

```swift
enum PhotoSubject {
    case activityType(ActivityType)   // Bath, Nail trim — one pool
    case routineTask(RoutineTask)     // lineage logs, unioned with the
                                      // Walk type's logs when isWalk
}
```

Read-only. Returns `[Photo]` newest-first for a subject. This is the single place
that knows walks are split across two pools, and the only thing that needs to
change if they are ever unified at write time.

### `DailyShuffle` — the daily pick

```swift
static func pick<T>(_ items: [T], on date: Date, salt: UUID,
                    calendar: Calendar = .current) -> T?
```

Seeded by `startOfDay(date)` combined with `salt`. A pure function of its inputs,
which buys three things: the pick is stable for a whole day, two activities on the
same day pick independently, and tests assert real values without mocking
randomness — matching how the rest of this codebase is tested.

### `ThumbnailCache`

Generates into `Caches/photo-thumbs/<photoID>@<px>.jpg` using
`CGImageSourceCreateThumbnailAtIndex`, returning **file URLs**.

| Size | Consumer |
|---|---|
| 44 | Timeline rows |
| 88 | Home "Recent moments" strip |
| 800 | `UNNotificationAttachment` |
| 1200 | Detail header, Home hero |

Lives in `Caches/`, so iOS may evict it under storage pressure; every read path
regenerates transparently on a miss. Cache entries are derived data and are never
the source of truth — `Photo.imageData` remains that.

### Pending walk-photo buffer

Mid-walk captures are downscaled through the existing `ImageDownscaler` and
written to a pending directory keyed by session id. On disk rather than in memory,
because the session itself survives app termination and the photos must survive
alongside it.

`WalkSessionStore.writeEntry(for:endedAt:)` drains the buffer into `Photo` rows
and clears it. That function is the single choke point from session to entry — its
own doc comment calls it "the only path" — so hooking there covers both a normal
`end()` and a stale `expireIfStale()` without a second code path.

## Surfaces

| Where | Behavior |
|---|---|
| Home "Recent moments" strip | New section above the cadence grid; recent photos across all activities, walks included |
| `CadenceTile` | Daily-shuffled photo from that type's pool; falls back to the existing SF Symbol when the pool is empty |
| `CareActivityDetailView` | Photo hero, replacing the cold open onto a `Form` |
| `TimelineView` rows | 44pt leading thumbnail of that entry's own photo |
| `HeroHeader` | Daily rotation through recent photos |
| Reminders | `UNNotificationAttachment` built from the cached file URL |

Every surface degrades to today's appearance when its pool is empty. A fresh
install with no photos must look exactly as it does now — this feature is additive
decoration over a working app, never a precondition for one.

## Phasing

Six surfaces is more than one pass should carry. The foundation is what has risk
in it; the surfaces are repetition once it exists.

**Phase 1 — foundation and proof.** `PhotoPool`, `DailyShuffle`,
`ThumbnailCache`, the pending buffer and banner camera button, plus two consuming
surfaces: the Home "Recent moments" strip and `CadenceTile`.

One gap is deliberate: `PhotoSubject.routineTask` — the walk union — has no
phase 1 *caller*. The strip queries recent photos directly and `CadenceTile` only
ever asks about an `ActivityType`; the union's first real consumer is phase 2's
walk reminder. It is built and unit-tested in phase 1 anyway, because it is the
piece that justifies `PhotoPool` existing as a type rather than a helper on
`ActivityType`, and because writing it alongside the pool it belongs to is
cheaper than retrofitting it later.

**Phase 2 — remaining surfaces.** Detail header, Timeline rows, hero header,
notification attachments. Each is an independent consumer of a proven foundation.

## Testing

- **`DailyShuffleTests`** — same date returns the same pick; the pick changes
  across a day boundary; different salts diverge on one date; empty and
  single-element pools behave.
- **`PhotoPoolTests`** — a walk subject unions lineage logs with Walk-type logs;
  one activity type never sees another's photos; an empty pool returns empty
  rather than throwing.
- **`ThumbnailCacheTests`** — a thumbnail is generated at the requested size;
  a second request reuses the file; deleting the file regenerates it.
- **`WalkSessionStoreTests`** (extend) — buffered photos attach on `end()`;
  buffered photos also attach on `expireIfStale()`; the buffer is cleared after
  a successful write.

## Out of scope

- Photo-library time-window suggestions, and the Photos permission they require.
- Any change to `Photo`, `LogEntry`, or any other Core Data entity.
- Unifying the walk pools at write time.
- Widgets and the walk Live Activity. Both are plausible later consumers of
  `ThumbnailCache`, and neither is needed to prove the design.
- The web mirror, which remains at maintenance level.
