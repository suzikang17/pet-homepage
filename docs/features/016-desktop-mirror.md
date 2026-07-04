---
lore_type: feature
title: "Desktop mirror dashboard (web)"
status: shipped
area: web
entry_point: "web dashboard, paired from iOS Settings"
since: 2026-06-27
---

**A read-only web dashboard of the pet's full health record — for the desk, the vet's office, or a family member's laptop.**

## How it works
The iOS app (the system of record) pushes a full snapshot of the active pet — profile, meds + doses, vaccines, vet visits + recommendations, markers, symptoms, diary, activities — to the web app whenever data changes. Pairing is a one-time flow: the signed-in dashboard shows a short code/QR; the iOS app claims it and receives a long-lived device token (stored in the Keychain). The dashboard renders the latest snapshot; tokens are listable/revocable on the web.

## Details
- Strictly one-way: the web never writes pet data.
- Multi-pet: the dashboard shows whichever pet was most recently pushed (the active one).
- Old snapshots stay renderable — the dashboard parses newer fields optionally.

## Design notes
- The snapshot is an opaque, versioned JSON blob to the backend (currently schema v4) — the mirror contract is owned by the iOS side, which keeps model refactors from breaking the web.
- Auth: dashboard sign-in via Convex Auth; the iOS push authenticates with a hashed capability token, not a user session.
