---
lore_type: feature
title: "Medications & dose logging"
status: shipped
area: ios
entry_point: "Timeline + → Medication; 📷 capture (dose)"
since: 2026-06-27
---

**Track prescriptions — dosage, frequency, schedule, refills — and log every dose given.**

## How it works
A medication is a standing definition: drug name, dosage, frequency (daily/interval/free-text), optional schedule time, start/end dates, refill-due date, prescribing vet, photos (e.g. the label). Daily/interval schedules fire repeating dose reminders at the set time; refill dates surface in "Due soon." Each dose given is logged (from the med's detail page, or one tap in camera capture) with a timestamp and optional note; the detail page shows dose history, count, and last-given.

## Details
- Ended medications stop reminding and drop out of capture's chip strip.
- Dose logs are occurrences in the unified stream like everything else.

## Design notes
- Medication is deliberately a *definition* (like an activity type), not an occurrence — the dose is the occurrence. This split is what makes "tap Apoquel after snapping a photo" a one-tap dose log.
