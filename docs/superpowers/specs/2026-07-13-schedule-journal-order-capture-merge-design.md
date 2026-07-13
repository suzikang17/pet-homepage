---
lore_type: spec
title: "Schedule journal ordering, muted done rows, Capture merged into Timeline +"
status: approved
date: 2026-07-13
---

# Schedule journal ordering + Capture merge

Approved design (brainstorm 2026-07-13).

## 1. Schedule ordering — journal on top, todo below

`ScheduleViewModel.load()` reorders the day's slots after fetching:
completed slots first, sorted by completion time ascending (the day reads
top-to-bottom as "what happened"), then open slots in the store's scheduled
order (unchanged), then skipped slots last. Sorting lives in the view model,
NOT `RoutineStore.slots(for:)` — that pure read is consumed by walk
slot-attach and notification dedupe, which need scheduled order.

## 2. Muted completed rows — open rows pop

Completed rows read as a quiet receipt, open rows as the actionable list:

- Check control: completed → small `checkmark.circle` (20 pt, soft ink,
  ~60% opacity); open → large `circle` (26 pt) in brand primary at ~45%
  opacity, inviting the tap.
- Completed row content drops to 55% opacity and the title loses its
  semibold weight. Open rows keep full contrast + semibold.
- Uncheck still works (tap the small check; context menu unchanged) — it
  only *looks* inert.
- Skipped-row strikethrough treatment is unchanged, but skipped rows sink
  to the bottom of the list.

## 3. Capture moves into the Timeline + menu; Capture tab removed

- Timeline's floating + menu gains a top-level **"Take photo"** entry
  (camera icon) above "Scan a record".
- The camera/review flow stays in `ContentView` (full-screen camera, photo
  library fallback, `--uitest-stub-camera` support, CaptureReviewView,
  handoffs). The tab-change handler's body is extracted into
  `startCapture()` and passed to `TimelineView` as an `onCapture` closure.
- The fake Capture tab (`Color.clear`, tag 2) and the `onChange(of:
  selectedTab)` bounce-back hack are deleted. Remaining tabs keep their
  existing tags (0, 1, 3, 4) so selection logic is untouched.

## Testing

ScheduleViewModel unit tests: done-first ordering by completion time, open
slots retain scheduled order, skipped slots last, progress unaffected.
Existing tests updated only if they asserted positional order that the new
sort legitimately changes (none expected: current tests use all-open days).
UI tests that navigated via the Capture tab are updated to the + menu entry.
