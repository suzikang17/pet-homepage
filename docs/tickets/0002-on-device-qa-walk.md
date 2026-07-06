---
title: "On-device QA walk: capture, OCR, multi-pet, unification smoke"
created: "2026-07-04"
status: open
owner: human
category: qa
priority: high
effort: small
lore_type: ticket
---

Manual QA on a real iPhone for everything shipped 2026-06-29 → 07-04 (main @ b5e6a11).
None of this is simulator-verifiable — the sim has no camera, no Contacts, no iCloud
account. Report failures back to the agent session for fixes.

## Outcome

- [ ] **Camera capture flow** — center 📷 tab opens the viewfinder instantly (no
  collapse); snap → review-and-tag sheet appears; each tag path works: Note only
  (→ Diary chip), activity (→ logged + Due soon + reminder), active med (→ dose in
  med history), marker (inline value; Save disabled until a number parses),
  Vaccine/Vet visit (→ full editor opens with the photo already attached).
- [ ] **OCR ✨ suggestion** — a real med bottle / preventative box (e.g. Heartgard)
  pre-selects the right chip with ✨ within ~2s; a textless photo suggests nothing
  (and no phantom ✨ on "Note only"); a manual chip tap is never overridden.
  *This result decides whether the paid Claude-vision fallback ever gets built.*
- [ ] **Contacts import** — Care Team → Import from Contacts fills
  name/clinic/phone/email/address from the picked contact.
- [ ] **Multi-pet** — avatar menu (Switch / Add / Change photo, all three work);
  a 2nd pet gets seeded activity types and everything follows the active pet;
  both pets' vet-cadence reminders coexist; notification copy names the pet.
- [ ] **Post-unification smoke (real pre-existing data)** — all old records render
  in Timeline/detail/editors after the update; pre-unification diary/activity/dose
  entries are filed under the right chips (kindRaw backfill); weight tile + trend
  still show old data.
- [ ] **Merged Timeline** — Diary chip; Stream|Photos toggle (grid shows photos from
  ALL record types); "Note" in the + menu; a custom per-activity reminder time
  (e.g. 18:30) fires at that time.
- [ ] **Mirror** — push → dashboard renders the new Activities section (schema v4),
  older sections unchanged.

## Notes

- Shipped range: `dae24aa … b5e6a11` on main; the risky bits were all
  presentation-layer (camera cover, contact picker host, sheet handoffs) — exactly
  what unit tests can't see.
- Known non-bugs: full `xcodebuild test` exits 65 on the sim even when green
  (CloudKit launch crash + retry); not observable on device.
- **Machine-covered since 2026-07-06** (XCUITest target, 8 tests, `-only-testing:PetHomepageUITests`):
  the capture review sheet + every tag path (note/activity/marker validation/vaccine
  handoff with photo), pet switcher add/switch, Timeline Stream|Photos + Diary chip +
  "+"-menu contents, tab layout. **Still device-only:** real camera behavior, OCR on
  physical packaging, Contacts import, notification timing/copy, mirror push, CloudKit
  sync, and the kindRaw backfill against real pre-unification data.
