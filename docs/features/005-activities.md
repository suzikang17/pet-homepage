---
lore_type: feature
title: "Activities (repeatable care events)"
status: shipped
area: ios
entry_point: "Timeline + → Activity; 📷 capture"
since: 2026-06-30
---

**Log anything you do for your pet repeatedly — bath, nail trim, flea treatment — and get reminded when it's due again.**

## How it works
Activity **types** are user-defined and pre-seeded so logging works with zero setup: Bath (30d), Nail trim (21d), Teeth brushing (1d), Brushing (7d), Grooming (42d), Flea & tick (30d), Deworming (90d) — each with a category (Care/Play/Feeding/Training/Health/Other), an icon, a default repeat interval, and its own reminder time of day. Logging an occurrence stamps the next due date, surfaces it in Home's "Due soon," and schedules a notification ("Time for Bella's bath"). Types are managed from the Timeline header: rename, recategorize, change icon/cadence/reminder time, archive (history preserved). New custom types take one field (a name) and can be created inline mid-log.

## Details
- Only the newest occurrence of a type holds a pending reminder; deleting it re-arms the previous one.
- Seeding is per-pet, idempotent, and CloudKit-safe (de-dupes by name so synced devices can't double-seed).
- Repeat interval is copied onto each occurrence at log time, so editing a type never rewrites history.

## Design notes
- User-defined types (not a hardcoded enum) with pre-seeded editable defaults — "super easy setup" and full flexibility at once.
- Category is a fixed enum, not a third entity: it only groups pickers, nobody needs to manage it.
