---
lore_type: feature
title: "Multi-pet"
status: shipped
area: ios
entry_point: "Home avatar → Switch pet / Add pet"
since: 2026-07-04
---

**A household of pets in one app — switch the active pet and everything follows.**

## How it works
Tapping the Home avatar opens a menu: **Switch pet…** (sheet listing all pets, checkmark on the active one), **Add pet…** (name + species), **Change photo…**. Switching makes that pet "active": Home, Timeline, Diary photos, capture, and the desktop mirror all show the active pet's data. A newly added or switched-to pet automatically gets the starter activity types.

## Details
- Notification copy names the pet ("Time for Bella's bath"; "Rabies is due for Milo") so reminders are unambiguous with several pets.
- Each pet keeps its own vet-cadence reminder — they coexist rather than overwrite.
- The active-pet choice is per-device (not synced across a user's devices) — deliberate v1 simplification.
- No pet deletion yet (destructive cascade; deferred until asked for).

## Design notes
- The whole app already scoped every read/write through "the current pet," so multi-pet = redefining "current" + a switcher — the data model needed zero changes.
