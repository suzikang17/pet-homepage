# Multi-Pet — Design

**Date:** 2026-07-04
**Status:** Draft for user review
**Depends on:** full LogEntry unification (steps 1–7) landed; builds on the settled model.
**User decisions (already made):** switching via the Home avatar; the desktop mirror shows the **active pet only**.

## Problem

The app is single-pet by construction: `PetStore.currentPet()` returns the first `Pet` row, and every store scopes reads/writes through it. Households have more than one pet.

## Approach

Keep the `currentPet()` choke point — that's the whole trick. Every store, the Timeline, capture, seeding, and the mirror already flow through it, so multi-pet = (1) an **active-pet selection** behind `currentPet()`, (2) UI to **switch and add pets**, and (3) fixing the few places that silently assume "one pet ever."

## Design

### 1. PetStore: active-pet selection

- `pets() -> [Pet]` — all pets, sorted by name.
- Active pet id persisted in `UserDefaults` (`activePetID`). `currentPet()` resolves: pet matching the stored id → else first pet (existing behavior; also covers a deleted/legacy id). `setActivePet(_ pet: Pet)` writes the id.
- `ensurePet()` unchanged (creates the default pet when none exists) — new pets beyond the first are created explicitly via the switcher, `createPet(name:species:)` + `setActivePet`.
- Active-pet choice is **per-device** (UserDefaults, not synced) — two devices on one iCloud account may show different active pets. Deliberate v1 simplification, noted here.

### 2. Switcher UX (one adjustment to the chosen design)

The Home hero avatar tap is **already taken** (it opens the change-photo flow). Resolution: avatar tap opens a small menu — **Switch pet…** (submenu/sheet listing pets with avatar + name, checkmark on active), **Add pet…** (small sheet: name + species → `createPet` + `setActivePet`), **Change photo…** (the existing flow). One affordance, all three intents; no lost functionality.

- Switching calls `setActivePet`, then `seedDefaultsIfNeeded()` (idempotent, pet-scoped — a new/other pet gets its starter activity types), then refreshes Home.
- Other tabs already reload `.onAppear`, so they follow the active pet on next visit. Capture/review, Timeline, Diary, Care Team all inherit scoping via the stores.
- Home's hero shows the active pet's name/photo (already does — it renders `currentPet`).

### 3. Single-pet assumptions to fix

- **Vet-cadence reminder identity:** `DueReminderScheduler.vetCadenceEntityID` is one fixed sentinel UUID — with two pets, their cadence reminders would overwrite each other. Fix: key the vet-cadence reminder by **`pet.id`** (kind stays `.vetCadence`). Sync/cancel call sites pass the active pet's id; per-pet cadence reminders coexist.
- **Reminder copy:** bodies include the pet's name so notifications are unambiguous in a multi-pet home — "Time for Bella's bath", "Rabies is due for Milo". Applies to activity + vaccination reminders (read the name off the entry's `pet`); vet-cadence body gets the pet name from the synced pet.
- **Seeding on switch/create** (covered above) — otherwise a second pet has no starter activity types.
- **Mirror:** `SnapshotBuilder` reads through pet-scoped stores → automatically snapshots the active pet. The dashboard therefore shows whichever pet was most recently pushed (user-approved). No web changes.

### 4. Explicit non-goals (v1)

- **Deleting a pet** (destructive cascade across all records; defer until asked).
- Per-pet web dashboards / multi-pet snapshot.
- Syncing the active-pet choice across devices.
- Per-pet notification sounds/times or any other per-pet settings.

## Testing

`PetStore` active-pet tests (persisted id resolution, fallback-to-first on unknown id, setActivePet roundtrip, pets() ordering); store-scoping test proving records created after a switch attach to the new active pet and queries only return its rows; vet-cadence per-pet reminder identity (two pets → two pending cadence reminders); reminder-body pet-name assertions; seeding-on-switch idempotency.

## Build shape

1. PetStore active-pet mechanics + tests (no UI).
2. Reminder fixes: per-pet vet-cadence identity + pet-name copy + tests.
3. Switcher UI (avatar menu, switch sheet, add-pet sheet) + seeding-on-switch wiring.
