---
lore_type: feature
title: "Camera-first capture (center tab + review-and-tag)"
status: shipped
area: ios
entry_point: "📷 center tab"
since: 2026-07-04
---

**Snap a photo from anywhere in the app, then tag what it was — the photo becomes a real record, not just a picture.**

## How it works
The center tab-bar slot is a camera button: tap → viewfinder opens instantly (photo-library picker on devices without a camera). After the shot, a **review-and-tag sheet** shows the photo with a "What's this?" chip strip: **Note only** (default — saves a diary entry), any **activity type** (Bath, Nail trim…), any **active medication** (logs a dose), a **health marker** (pick weight etc., type the value inline), or **Vaccine / Vet visit** — which hand off to the full editor with the photo already attached (those need more fields). Date and note are editable; Save commits.

## Details
- Tagging an activity applies its cadence and schedules the reminder — identical behavior to logging from the editor.
- "Take photo" also exists inside every record editor's photo section (library + camera).
- Symptoms are deliberately not offered from capture (episodes are time spans, not snap-moments).

## Design notes
- Camera-centric without compromising utility: the camera owns the marquee gesture; structured entry keeps its own affordances (Timeline "+").
- One tap must never silently mis-file: chip choices are explicit, and Save is always the gate.
