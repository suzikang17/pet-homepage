---
lore_type: feature
title: "Unified Timeline (stream + photos)"
status: shipped
area: ios
entry_point: "Timeline tab"
since: 2026-06-27
---

**Every record — vaccines, vet visits, meds, markers, symptoms, activities, diary notes — in one date-sorted, filterable stream.**

## How it works
The Timeline tab shows one reverse-chronological list of everything that happened, each row typed with an icon/tint and, where relevant, a "NEXT" due date. Filter chips (All · Vaccines · Vet · Meds · Health · Symptoms · Activities · Diary) narrow the stream. A **Stream | Photos** toggle swaps the list for a photo grid of every picture attached to any record. Tapping a row opens that record's editor/detail; swipe deletes (cancelling any reminder it owned). The floating "+" adds any record type; low-frequency ones (Vaccine, Vet visit, Health marker) sit under a "Health record" submenu, and "Scan a record" (AI extraction) lives at the top. The header's slider icon opens activity-type management.

## Details
- Deleting the newest occurrence of a repeating activity re-arms the previous one's reminder, so a type never silently loses its "due next."
- Photos mode aggregates photos from all record kinds, not just diary entries.

## Design notes
- The Timeline replaced per-type tabs (Meds/Vaccines/Vet) early on, and later absorbed the Diary tab too — one stream + filters beat parallel tabs each time.
- The data model matches the UI: every row is one `LogEntry` occurrence with a kind, which is why the stream, filters, and "Due soon" need no special-casing.
