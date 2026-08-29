# Activity photos: the app finally looks like your dog

**Branch:** `feat/activity-photos` · **Spec:** `docs/superpowers/specs/2026-08-29-activity-photos-design.md` · **Plan:** `docs/superpowers/plans/2026-08-29-activity-photos.md`

Photos existed in the model for over a month — attached to log entries, synced,
counted — and not one surface asked what an activity *looks like*. This branch
adds the connection: a daily-shuffled photo on each cadence tile, a "Recent
moments" strip on Home, a camera button on the live walk banner, thumbnails on
Timeline rows, a photo hero on activity detail, a rotating Home hero, and
photos riding along on reminders. Zero Core Data schema changes, by design —
no CloudKit push, no console promotion.

## Shape

Four units carry everything; the seven surfaces are thin consumers.

- **`DailyShuffle`** — pure function of (day, salt, count) via explicit FNV-1a.
  Swift's `Hasher` is per-process seeded and would have reshuffled on every
  launch; a pinned-literal test exists purely to catch anyone "simplifying"
  back to it.
- **`PhotoPool`** — the one place that knows walks are split across two pools
  (routine-lineage completions vs. detected walks on the Walk type). Read-side
  union; due-date computation untouched.
- **`ThumbnailCache`** — downsampled JPEGs in `Caches/photo-thumbs/`,
  addressed by file URL. Files because 1600px blobs drop frames at 44pt, and
  because `UNNotificationAttachment` refuses `Data` outright.
- **`PendingWalkPhotos`** — mid-walk captures parked on disk (Application
  Support, not Caches — not derived data) until `writeEntry` drains them into
  the entry, covering both `end()` and `expireIfStale()` through the single
  choke point.

## What the loop caught

Built via subagent-driven development: fresh implementer per task, reviewer per
task, scoped re-reviews on fixes. Worth recording what each layer caught:

- **Plan-authoring bugs caught by implementers:** nonexistent
  `ActivityCategory.exercise/.food` cases, `logActivity`'s non-defaulted
  `note:`, `heroBackground` typed `UIImage?` against an `Image?` API, routine
  reminder content built in `RoutineReminderScheduler` not
  `DueReminderScheduler`, a third `CadenceItem` construction site in tests.
- **A real spec gap caught by a reviewer:** Task 9 wired thumbnails only at
  the plan's two anchored sites (routine, diary) — but vaccine, vet, and
  activity entries attach photos through the identical `PendingPhotoSection`.
  A Bath photo invisible on the Bath row, in the feature built for Bath
  photos. One fix round.
- **A versioning subtlety caught in final-stretch review:** salting the
  reminder shuffle with `RoutineTask.id`, which changes when a template edit
  versions the row; `lineageID` is the stable identity.

CI discipline on a Linux box with no Swift toolchain: judge runs by counting
`' passed ('` vs `' failed ('` lines, never exit codes. Four checkpoints, all
green (final: 452/0). The one mid-branch failure was the known nil-insert
flake, passed on retry.

## Deferred

- Medication tiles and Timeline rows pass `dailyPhotoURL`/`thumbnailURL` nil —
  phase-boundary choice, medications have their own photo mechanism.
- Pet-scoping comment on `PhotoPool` predicates if multi-pet ever ships.
- On-device camera QA (simulator has no camera): banner button → two photos →
  End → both on the entry; long-press → Discard → photos gone.
