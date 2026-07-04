---
lore_type: feature
title: "Home dashboard"
status: shipped
area: ios
entry_point: "Home tab"
since: 2026-06-27
---

**One glance answers "how is my pet doing and what's coming up?"**

## How it works
Home opens on the active pet's hero (photo, name, species — name/species editable inline) above a stack of glanceable cards: **Due soon** (anything with an upcoming next-due within ~60 days — vaccines, vet visits, activities, med refills), **Recent** (the last few logged records), plus tiles for **latest weight** and **next vet visit**. The gear opens Settings (mirror pairing, extraction endpoint, document sharing).

## Details
- Due soon and Recent are read projections of the same unified Timeline stream — tapping through lands in the record's editor.
- The hero avatar tap opens the pet menu (see Multi-pet).
- Quick-add sheets for weight and symptoms are reachable from their tiles.

## Design notes
- Home is deliberately read-mostly: capture happens via the center camera tab and Timeline's "+" (a bottom capture bar was tried and removed as a third redundant entry point).
