---
lore_type: feature
title: "On-device OCR tag suggestion"
status: shipped
area: ios
entry_point: "automatic, in capture review"
since: 2026-07-04
---

**Photograph a med bottle or preventative box and the right chip pre-selects itself — free, instant, on-device.**

## How it works
When the capture review sheet opens, the photo is OCR'd on-device (Apple Vision) and the recognized text is fuzzy-matched against the user's own vocabulary — their medication names and activity type names. A match pre-selects that chip with a ✨ "suggested" marker; the user still hits Save. No match, no camera text, or the user already tapped a chip → nothing happens.

## Details
- Matching is whole-word and case/diacritic-insensitive ("HEARTGARD® PLUS CHEWABLES" → med "Heartgard"; "bathroom" does NOT match "Bath").
- A suggestion never overrides a manual choice and costs one tap to change.
- Zero network calls, zero API cost, photos never leave the device for this.

## Design notes
- Chosen over a cloud vision call deliberately: packaging photos are text-rich, and on-device OCR handles them well. A paid Claude-vision fallback for text-less photos (wet dog in tub → "Bath") stays unbuilt until real usage shows on-device whiffing on cases that matter.
