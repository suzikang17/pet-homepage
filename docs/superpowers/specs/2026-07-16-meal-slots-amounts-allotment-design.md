---
lore_type: spec
title: "Meal routine slots — multi-log feedings with amounts and a daily allotment"
status: approved
date: 2026-07-16
---

# Meal slots with amounts + allotment

Approved 2026-07-16 (brainstorm). Meals live as **routine slots** (Schedule).
A slot marked as a meal can be logged multiple times a day, each feeding
carries an amount in the slot's unit, amounts sum toward the slot's allotment,
and the slot auto-completes when the total reaches the allotment.

## Decisions

- **Home:** routine slots (not activity types / not a new feature).
- **Allotment:** per meal slot (Breakfast 1 cup, Dinner 1 cup) — not day-wide.
- **Done rule:** slot completes when summed feedings ≥ allotment; under
  allotment it stays open and still reminds.
- **Units:** unit chosen per slot (cups / grams / oz / scoops); every feeding
  log requires an amount in that unit.

## Data model

- `RoutineTask.isMeal: Bool` (default NO) — parallels `isWalk`.
- `RoutineTask.mealAllotment: Double` (default 0) — the daily target.
- `RoutineTask.mealUnit: String?` — cups / grams / oz / scoops.
- Each feeding is a `.routine` LogEntry sharing the slot's `routineLineageID`,
  reusing the existing `value: Double` (amount) and `unit: String?` fields
  (unused by routine entries today). No new entity.
- Lightweight Core Data migration; CloudKit schema push needed after ship
  (`CD_RoutineTask.CD_isMeal / CD_mealAllotment / CD_mealUnit`).

The load-bearing change: routine slots are single-completion today
(`RoutineStore.completion(of:on:)` + walk-session dedupe assume ≤1 per day).
Meal slots become **multi-completion**; non-meal slots keep single-completion
semantics unchanged.

## RoutineStore

- `createTask/editTask/addOneOff` gain `isMeal / mealAllotment / mealUnit`
  params (nil-inferred like isWalk: infer isMeal from feeding category +
  name, but explicit toggle wins).
- `completions(of:on:) -> [LogEntry]` — all feedings for a slot on a day
  (existing `completion(of:on:)` stays for single-completion callers).
- `logFeeding(_ task:on:now:amount:) -> LogEntry` — append a feeding entry
  (never dedupes); non-meal check-off path unchanged.
- `fedTotal(of:on:) -> Double` — sum of today's feeding values.

## RoutineSlot

- Carries `isMeal`, `mealAllotment`, `mealUnit`, `feedings: [LogEntry]`,
  `fedTotal: Double`.
- `isCompleted` for a meal slot = `fedTotal >= mealAllotment` (allotment > 0);
  non-meal slots keep the "has a completion" rule.
- `mealProgress: Double` (0…1) for the ring.

## UI

- **RoutineTaskEditView:** "Counts as a meal" toggle (beside the walk toggle;
  the two are mutually exclusive — a slot is a walk or a meal or neither).
  When on, reveal a unit Picker and an allotment stepper (0.25 increments for
  cups/scoops, 5 for grams, 1 for oz).
- **Schedule row:** meal slot shows a progress ring + `1.5 / 2 cups`; tapping
  the ring opens a compact "Add feeding" amount sheet (prefilled to the
  remaining amount, editable). Non-meal rows unchanged. Long-press menu adds
  "Add feeding". Completed (full) meal slots recede like other done rows.
- **Feeding entries** are visible/removable: swipe a feeding in the day's
  breakdown removes it and reopens the slot if it drops below allotment.

## Reminders

Reuses the occurrence model: `RoutineReminderPlanner` already schedules only
for slots where `!isCompleted`. Since a meal slot's `isCompleted` reflects
allotment, an under-fed meal keeps reminding and a full one goes quiet — no
scheduler change beyond the slot-completion definition.

## Testing

RoutineStore: infer isMeal, explicit toggle wins, logFeeding appends (no
dedupe), fedTotal sums, meal slot completes at allotment and reopens below.
RoutineSlot: mealProgress math, isCompleted crossover. Reminder planner: a
half-fed meal slot still produces an occurrence; a full one does not.
Walk/meal exclusivity. Existing single-completion routine tests stay green.
