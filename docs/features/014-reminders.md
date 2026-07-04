---
lore_type: feature
title: "Reminders & notifications"
status: shipped
area: ios
entry_point: "automatic (local notifications)"
since: 2026-06-27
---

**The app remembers so the owner doesn't: due vaccines, vet cadence, daily meds, and repeat activities all notify.**

## How it works
Four reminder kinds, all local notifications (no server):
- **Medication** — repeating daily/interval reminders at the med's schedule time.
- **Vaccination** — one-shot on the next-due date.
- **Vet cadence** — one-shot when it's been N months (default 6) since the last visit, per pet.
- **Activity** — one-shot on the activity's next-due date, at the activity type's own reminder time (default 9:00).

Everything with an upcoming date also appears in Home's "Due soon" — notifications and the dashboard read the same dates.

## Details
- Reminders are idempotent per record: rescheduling replaces, deleting cancels, and only the newest occurrence of a repeating activity holds one.
- Copy includes the pet's name for multi-pet households.
- Notification permission is requested once at first launch.
