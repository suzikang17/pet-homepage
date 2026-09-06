# Cadence tile sheet + tab consolidation — design

**Date:** 2026-09-06
**Status:** approved, ready for implementation planning

## Problem

Two unrelated complaints, both about surfaces that do the wrong thing when you
touch them.

### A tap on a cadence tile writes to the database

`CadenceTile` has no confirmation step. A single tap calls
`CadenceCatalogueViewModel.log(item)`, which writes a dose or an activity log
immediately. The affordance that looks most like "show me this thing" is in fact
the destructive one, and on a two-column grid of similar-looking tiles a stray
tap is easy.

The mitigations already in place do not cover the gap:

- The inline confirmation strip offers **Undo**, but auto-dismisses after four
  seconds (`PetProfileView:284`). Miss that window and the stray log is silent.
- The full record — history, backdated logging, per-entry delete — exists for
  both sources (`MedicationDetailView`, `CareActivityDetailView`) but is reachable
  only by **long-press**, an invisible gesture that needs a text hint under the
  grid to be discoverable at all ("Hold a tile for details").

So the app's two gestures are inverted: the discoverable one mutates data, and
the hidden one is the safe read.

There is also a silent-failure path. `log()` returns without writing when
something was already logged the same day — the dedupe at
`CadenceCatalogueViewModel:263` (medications, inside `MedicationDoseLogger`) and
`:278` (activities). Nothing is written, so `lastLogged` stays nil and no
confirmation strip appears. From the outside the tap simply did nothing, with no
explanation.

### The tabs are split along the wrong seam

`TimelineView` hosts two unrelated things behind a segmented picker: **Stream**
(the date-sorted record list, with type-filter chips, per-row editors, and an
add-record menu) and **Photos** (`PhotoGalleryView`). They share a tab because
they share a data source, not because they answer the same question.

Meanwhile `ScheduleView` already has its own **Today / Upcoming** picker. The
log belongs next to those — what happened, what is happening, what is coming —
and the photos belong on their own.

## Decisions taken

Settled with the user before this document:

1. **Tap opens a sheet; long-press logs.** The gestures swap. The fast one-tap
   path survives because it is genuinely useful right after you have done the
   thing — it just now requires deliberate intent. The Undo strip stays.
2. **The sheet is a bottom sheet**, not the existing pushed detail screen. The
   full record remains reachable from inside it.
3. **Schedule gains a third subtab, `Log`**, carrying what is today the Timeline
   Stream. Order is Log / Today / Upcoming.
4. **The Timeline tab becomes Gallery** — photos only, in a masonry layout.
5. **One merged `+` menu** on all three Schedule subtabs, rather than a menu
   whose contents change with the active subtab.
6. **Tab names stay minimal**: `Schedule` is unchanged, `Timeline` → `Gallery`.
7. **Two commits, not one.** The tile sheet and the tab consolidation are
   independent; landing them separately keeps a revert surgical.

## Constraint: tab tags are load-bearing

`ContentView`'s `.tag` values are mapped by raw value in
`NotificationRouter.Tab` (`home = 0, timeline = 1, schedule = 3, careTeam = 4`),
and `ContentView.screenLabel(for:)` switches on the same integers. Display order
in the `TabView` is already decoupled from tag order. **Tags must not be
renumbered.** Gallery keeps tag `1`; Schedule keeps tag `3`.

## Constraint: no Core Data schema change

The `Photo` entity stores `id`, `imageData`, `caption`, `createdAt` and three
relationships. It has **no pixel dimensions**, which masonry needs.

Adding them is disproportionately expensive here: a model change requires a Mac
with an iCloud-signed-in simulator to push the dev schema, then a manual
promotion in the CloudKit console, and CI cannot do it. This design therefore
derives aspect ratios at runtime and adds no attributes.

## Part 1 — Cadence tile sheet

### Gestures (`CadenceTile.swift`)

| Gesture | Before | After |
|---|---|---|
| Tap | logs immediately | opens the sheet |
| Long press | pushes the detail screen | logs immediately, with the Undo strip |

The success haptic moves with the write: it fires on the long-press, not the
tap. The existing comment on `CadenceTile:39` explaining why this is a shaped
container with separate gestures rather than a `Button` still applies and stays
— a `Button` action plus an attached long-press can both fire on one press.

Accessibility: the default action opens the sheet; the existing "Log now" action
is retained, and "Open details" is dropped as redundant (the default action now
does that).

`PetProfileView`'s hint text changes from "Hold a tile for details" to "Hold a
tile to log instantly".

### The sheet (`Features/PetProfile/CadenceSheet.swift` + view model)

Presented from `PetProfileView` via `.sheet(item:)` with `.medium` and `.large`
detents. It carries its own `NavigationStack` so "Open full record" can push
`MedicationDetailView` / `CareActivityDetailView` inside the sheet — the
existing `navigationDestination(item: $detailTarget)` on the Home stack moves
there.

One view over both sources, backed by a thin wrapper over the existing
`MedicationDetailViewModel` and `CareActivityDetailViewModel` rather than a
third implementation of load/log/delete.

```
┌──────────────────────────────────┐
│ 💊  Heartgard      Due today     │
│     1 tablet                     │
│  ┌────────────────────────────┐  │
│  │  Log a dose                │  │  expands inline; no nested sheet
│  └────────────────────────────┘  │
│      Given  [Sep 6, 2026 2:14 PM]│  DatePicker, defaults to now
│      Note   [                   ]│
│      Next reminder  Sep 7, 9:00  │
│                                  │
│  HISTORY (12)                    │
│  Sep 2, 2026 at 9:03 AM       ⋯  │  ⋯ = Edit time / Delete
│  Aug 30, 2026 at 8:47 AM      ⋯  │
│  Open full record             ›  │
└──────────────────────────────────┘
```

- **History** renders full date *and* time (`Sep 2, 2026 at 9:03 AM`), newest
  first. Both source view models already sort descending by `performedAt`.
- **Delete** is an explicit destructive item in a per-row `Menu`, behind a
  confirmation dialog. Swipe-to-delete stays as a shortcut. Deletion repairs the
  cadence exactly as `MedicationDetailViewModel.deleteDose` and
  `CareActivityDetailViewModel.delete` already do.
- **Edit time** on an existing entry reuses the same inline date picker.

### Editing an existing entry's date

`LogStore` has `updateDiary` and `updateActivity` but **no dose equivalent**.
Activities reuse `updateActivity`. Medications need a new
`LogStore.updateDose(_:performedAt:note:)`, plus a `nextReminder` resync through
`MedicationDoseLogger.nextDue(for:after:)` — the same repair
`MedicationDetailViewModel.deleteDose:63` performs after a deletion.

### Same-day dedupe becomes visible

`CadenceCatalogueViewModel.log()` gains a return value distinguishing *written*
from *suppressed by same-day dedupe*. The tile's long-press path ignores it (the
absent Undo strip is adequate feedback for a gesture you meant). The sheet's Log
button reports "Already logged today" and offers to edit that entry instead of
appearing to do nothing.

## Part 2 — Tab consolidation

### Extracting the stream

`TimelineView` (355 lines) splits along its existing picker:

- **`Features/Timeline/LogStreamView.swift`** — filter chips, day-grouped rows,
  per-row editors, delete, and the add-record menu. Still driven by the existing
  `TimelineViewModel`.
- **`Features/Timeline/GalleryView.swift`** — `HeroHeader("Gallery")`, the
  capture/import actions currently passed as `onCapture`/`onImport`, and
  `PhotoGalleryView`. No picker.

`TimelineView` is retired. `TimelineViewModel` is **not** modified; that
`TimelineViewModelTests` still passes untouched is the check that the extraction
was clean.

Two rejected alternatives: embedding `TimelineView` whole with its picker hidden
(leaves a view rendering two unrelated things plus a dead branch), and moving the
stream code directly into `ScheduleView` (which is already among the largest
views in the app and would roughly double).

### `ContentView`

```
Home (tag 0)    Schedule (tag 3)    Gallery (tag 1)    Care Team (tag 4)
                                     ↑ label "Gallery", icon photo.on.rectangle
```

`screenLabel(for: 1)` returns "Gallery". `PetProfileView`'s
`onShowTimeline: { selectedTab = 1 }` is unchanged and still correct —
`RecentMomentsStrip` is photos, so it should land on Gallery.

### Notification routing regression

`NotificationRouter.route` sends medication reminders to `Tab.timeline` (1)
because that tab "owns the medication rows and the Log dose flow". Tab 1 becomes
a photo gallery, so a tapped medication reminder would land on pictures.

Medication reminders re-route to `Tab.schedule`, opening on the **Log** subtab.
The router gains a `pendingScheduleSubtab` alongside `pendingTab`; `ScheduleView`
consumes and clears it on appear, mirroring how `ContentView` consumes
`pendingTab`. Routine and walk notifications are unaffected — they already route
to Schedule and should continue landing on Today.

### `ScheduleView`

`Tab` becomes `case log = "Log", today = "Today", upcoming = "Upcoming"`, in that
display order. The default stays `.today` — it is the daily driver and matches
where the tab opens today.

The header's `+` becomes one merged menu, identical on all three subtabs:

```
New one-off task
─────────────────
Diary entry
Symptom
Vet visit
Vaccination
```

The sliders button (template editor) is unchanged. `progressSubtitle` describes
the day's checklist, so the header shows it only on `.today`. The `.log` subtab
renders `LogStreamView`; `.upcoming` is unchanged.

### Masonry (`Features/Timeline/MasonryLayout.swift`)

Inside each existing month section, the
`LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))])` is replaced by a
column-balanced masonry: 2 columns on phone, 3 when the width allows. Each photo
is placed into the currently-shortest column, its height derived from its aspect
ratio. Month grouping, the section headers, and the full-screen pager are
untouched.

Aspect ratios come from `CGImageSourceCopyPropertiesAtIndex` on the already
cached thumbnail URL — image properties only, no decode — resolved off the main
thread in a `.task(id:)` pass modelled on the existing
`TimelineViewModel.resolveThumbnails()`, and memoized by photo id. A photo whose
ratio has not landed renders 1:1, so first paint is a plain grid that settles.

**Trade-off, accepted:** placement requires every cell's height, so cells within
one month lay out eagerly. Months themselves stay lazy inside the `LazyVStack`.
This is fine at ordinary volume; a single month holding hundreds of photos would
warrant revisiting.

## Files

**New**

- `ios/PetHomepage/Features/PetProfile/CadenceSheet.swift` + view model
- `ios/PetHomepage/Features/Timeline/LogStreamView.swift`
- `ios/PetHomepage/Features/Timeline/GalleryView.swift`
- `ios/PetHomepage/Features/Timeline/MasonryLayout.swift` (+ aspect-ratio cache)

**Changed**

- `Features/PetProfile/CadenceTile.swift` — gesture swap, haptic, accessibility
- `Features/PetProfile/PetProfileView.swift` — sheet presentation, hint text
- `Features/PetProfile/CadenceCatalogueViewModel.swift` — surface dedupe outcome
- `Stores/LogStore.swift` — `updateDose(_:performedAt:note:)`
- `App/ContentView.swift` — Gallery tab item, `screenLabel`
- `Notifications/NotificationRouter.swift` — medication re-route + subtab
- `Features/Schedule/ScheduleView.swift` — third subtab, merged `+` menu
- `Features/Timeline/PhotoGalleryView.swift` — masonry
- `Features/Timeline/TimelineView.swift` — retired

## Testing

- **New** `CadenceSheetViewModelTests` — history ordering, backdated log, delete
  repairs the cadence, editing a time re-syncs next-due, dedupe reported rather
  than silent.
- **New** `MasonryLayoutTests` — column balancing is pure arithmetic and the one
  genuinely algorithmic piece here; covers unknown ratios, single column, and
  the shortest-column invariant.
- **Updated** `NotificationRouterTests` — medication reminders land on Schedule
  with the Log subtab pending; routine and walk routing unchanged.
- **Updated** `CadenceCatalogueViewModelTests` — the new `log()` return value.
- **Unchanged** `TimelineViewModelTests` — must pass untouched; that is the
  extraction check.

Verification is `xcodebuild` build plus the unit suite. Note the known
intermittent nil-insert crash in the unit suite (see the CI flake note) — a
single retry is the established backstop and does not indicate a regression
here. Simulator-driven visual QA of the sheet and the masonry is a separate
on-device pass.

## Out of scope

- Any change to `TimelineViewModel`'s data loading.
- Reworking `MedicationDetailView` / `CareActivityDetailView` themselves; they
  remain the full record, now reached from inside the sheet.
- Photo capture and import flows, beyond moving their entry points to Gallery.
