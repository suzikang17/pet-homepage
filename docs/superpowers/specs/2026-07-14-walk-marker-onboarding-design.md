---
lore_type: spec
title: "Explicit walk marker on routine tasks + auto-detect onboarding"
status: approved
date: 2026-07-14
---

# Walk marker + auto-detect onboarding

Approved 2026-07-14 (brainstorm). Two parts:

## 1. `RoutineTask.isWalk`

Walk matching stops guessing (category/name heuristic) and uses an explicit
flag:

- New Core Data attribute `isWalk` (Bool, default NO) — lightweight
  migration; CloudKit schema push + production deploy required after ship.
- Task editor gains a "Counts as a walk" toggle, auto-flipped while typing
  when the name contains "walk" (until the user touches the toggle).
- `RoutineStore.createTask/addOneOff/editTask` accept `isWalk: Bool?`
  (nil = infer from name); versioned edits carry the flag to successors.
- One-time backfill on launch (`walk.isWalkBackfilled` defaults flag) marks
  existing tasks: name contains "walk", or play/training category with the
  figure.walk icon. One-time so a user's later opt-out is never re-flipped.
- `WalkSlotFinder` matches `task.isWalk` only. "Start now" stays available
  on every slot (any task can be timed); only matching uses the flag.

## 2. Auto-detect onboarding (both surfaces)

- **Schedule setup card**: shown when a walk-marked slot exists, detection
  is not configured (`HomeLocationStore.isConfigured == false`), and the
  card wasn't dismissed (`walk.setupCardDismissed`). "Set up" presents the
  Walk detection settings in a sheet; "Not now" dismisses permanently
  (Settings remains the home).
- **First-launch intro**: one-time single-screen sheet (`walk.introShown`)
  on app open — what auto-detect does, [Set up] → same settings sheet
  (presented via the pending-flag/onDismiss pattern the codebase already
  uses for sheet chaining), [Maybe later]. Skipped under UI tests.
  Existing installs see it once after updating.

## Testing

RoutineStore: inference on create, explicit override, successor carries the
flag, backfill rules. WalkSlotFinder: matches only `isWalk` slots. Existing
walk-named fixtures keep passing via inference.
