---
lore_type: feature
title: "AI record scan (document extraction)"
status: shipped
area: cross
entry_point: "Timeline + → Scan a record"
since: 2026-06-27
---

**Photograph or upload a vet bill / vaccine certificate and the app files the records for you.**

## How it works
"Scan a record" (top of the Timeline "+" menu, ✨ icon) takes a PDF or photo, ships it to the extraction endpoint (`/api/extract`, Claude vision on the web side), and writes the parsed results back as real records — vaccinations, vet visits, medications — which the user reviews in place. The original document is retained via the document store (iCloud Drive when available).

## Details
- The endpoint + secret are configured in Settings; the menu entry hides when unconfigured.
- This is the one AI feature that uses the network — capture tag suggestion (OCR) is fully on-device by contrast.
