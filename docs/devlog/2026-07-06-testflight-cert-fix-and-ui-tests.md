---
lore_type: devlog
created: 2026-07-06
title: "TestFlight cert-cap fix + XCUITest target lands"
date: 2026-07-06
day: 10
---

**Diagnosed and fixed the TestFlight pipeline (every run since Jul 4 failed on Apple's certificate cap — CI was minting a Development cert per push), and landed the XCUITest target (8 green UI tests with deterministic `--uitest` seams).**

## What got done
- **CI unblocked**: revoked 11 CI-minted "Created via API" Development certificates via a new manual-dispatch `ASC certificates` workflow (list first, revoke behind an explicit input + date cutoff + keep-list). Personal certs untouched.
- **Durable signing fix**: the archive step is now **unsigned** (`CODE_SIGNING_ALLOWED=NO`); the export step owns all signing via the one cloud-managed `IOS_DISTRIBUTION` cert Apple holds and reuses. Two consecutive green uploads; post-fix inventory: exactly 3 certs, zero minted.
- **XCUITest target merged** (`PetHomepageUITests`, 8 tests): capture review + all tag paths (note/activity/marker-validation/vaccine handoff with photo), pet switcher add/switch, Timeline Stream|Photos + Diary chip + "+"-menu, tab layout. App-side seams gated behind `--uitest` (in-memory store, seeded fixtures, no notification prompt) and `--uitest-stub-camera` (straight to the review sheet with a generated photo).
- `paths-ignore` on the TestFlight trigger — docs-only pushes no longer burn CI or upload duplicate builds.
- QA ticket 0002 updated: machine-covered flows vs device-only items (camera, OCR on packaging, Contacts, notifications, mirror, kindRaw backfill on real data).

## Decisions
- Unsigned archive + export-owned signing over importing a stable .p12: no new secrets, no interactive cert export, and the cloud-managed distribution cert is designed for exactly this.
- Cert cleanup as a repeatable workflow rather than a one-off portal click — it documents the failure mode and guards the keep-list.

## Issues
- First fix attempt (forcing `CODE_SIGN_IDENTITY="Apple Distribution"` at archive) conflicts with automatic signing — Xcode refuses manual identity + automatic style.
- `cancel-in-progress` concurrency made a docs push cancel the confirmation run — reading a "cancelled" conclusion as failure would have been wrong; the superseding run was the real verdict.
- XCUITest quirks (worked around in tests only): off-screen chips make `isHittable` throw (frame-math swipe), confirmationDialog duplicates buttons in the hierarchy (`firstMatch` + label matching), List-row buttons can swallow the first synthesized tap (guarded retry).

## What to remember
- UI suite: `xcodebuild test … -only-testing:PetHomepageUITests` (~2m15s); the `--uitest` launch arg is what keeps it deterministic — don't remove the seams.
- The `ASC certificates` workflow is the tool if "maximum number of certificates" ever reappears.
- TestFlight ignores docs/**, **.md, .claude/** pushes now — dispatch manually if a build is wanted anyway.

---

## Commits
18cb2a7 docs: QA ticket — note machine-covered flows vs device-only items
4319578 Merge feat/ui-tests: XCUITest target (8 UI tests, deterministic --uitest seams)
4cdd26b test: XCUITest target — capture, switcher, timeline UI flows (deterministic --uitest seams)
232f8c2 ci: archive unsigned; export step owns all signing (cloud-managed distribution)
569f8e0 ci: archive with cloud-managed Apple Distribution identity
4df720d ci: ASC certificate maintenance workflow (list / revoke CI-minted dev certs)
