---
lore_type: feature
title: "Vet visits & recommendations"
status: shipped
area: ios
entry_point: "Timeline + → Health record → Vet visit; scan; 📷 capture"
since: 2026-06-27
---

**A record of every clinic visit — reason, diagnosis, treatment — plus the vet's follow-up recommendations and an automatic "time to see the vet again" nudge.**

## How it works
A visit captures date, clinic, vet, reason, diagnosis, treatment notes, photos, and an optional explicit next-visit date. The visit detail page keeps a running list of the vet's **recommendations** (free-text, dated). Independently, a **vet cadence** reminder fires when it's been N months (default 6) since the last visit — per pet, recomputed whenever visits change.

## Details
- The cadence reminder is one-per-pet and self-heals: deleting a visit re-syncs it from the new most-recent visit.
- Visits also arrive via document scanning and the capture-photo handoff.
