---
title: Shipped to TestFlight + reshaped the app around a unified Timeline
date: 2026-06-27
phase: Post-v1 — CI/CD + UX polish
---

**Stood up a GitHub Actions → TestFlight pipeline (edit anywhere → push → OTA to the phone), closed the loop on the AI scan + device pairing features, then consolidated the 5-tab app into a Timeline + dashboard Home and did a long UI-polish pass — all shipped as one TestFlight build.**

## What got done
- **CI/CD to TestFlight.** A macOS GitHub Actions workflow now archives (Release), exports, and uploads to TestFlight on every push to `main`, using an App Store Connect API key (cloud-managed signing, no fastlane match). Repo went private on GitHub; secrets set via `gh`. The phone updates over the air — no cable, buildable from a Linux VPS via `git push`.
- **In-app "Scan a record"** — wired the previously-unreachable AI extraction pipeline: a PhotosPicker/PDF picker → `/api/extract` (Claude) → review → save into the right stores, presented from a Home card. Endpoint + secret configurable in Settings.
- **Device pairing (QR + short code)** to replace the 70-char token copy-paste: dashboard mints a short-lived single-use code shown as a QR *and* typable code; the app scans/enters it at `/mirror/pair` and self-configures (token → Keychain, mirroring on). Verified the full claim→token→push chain headlessly.
- **Tab consolidation 5 → 3** (Home · Timeline · Health). New **Timeline** aggregates all five record types into one date-sorted, filterable stream (tap → existing editor, FAB → add, swipe → delete with reminder cleanup). **Home** became a dashboard: at-a-glance stats, quick actions (log dose/weight/symptom), upcoming, recent.
- **UI iteration batch:** structured medication frequency ("Every N days/weeks/months") that drives the reminder; "Next reminder" anchors to the frequency, not today; pet avatar (tap the hero); pet name in the header; Name/Species moved to Settings (set-once); weight unit is a picker defaulting to **lb**; consistent `brandSheet()` on every add/edit sheet; Timeline brand hero; and a real **app icon** (white paw on violet).
- **Web housekeeping:** relaxed the Convex Auth password policy (was 8+upper/lower/digit), fixed sign-up redirecting to a non-existent `/onboarding`, and redeployed the dashboard to Vercel.

## Decisions
- **Build on GitHub's macOS runner, not the VPS.** iOS can't compile/sign on Linux, so the VPS is only an editor + `git push`; the runner does everything. Chose API-key cloud signing over `match` to avoid a separate certs repo.
- **Medication frequency stays a string, parsed into a `MedFrequency` value type** — avoids a Core Data/CloudKit migration. Daily uses a repeating trigger; other cadences schedule a one-shot on the next due date, recomputed each sync.
- **Timeline is the single delete/add surface.** Consolidation dropped per-type delete; restored it as swipe-to-delete on Timeline rows (moved into the view-model so it's testable).
- **Identity (name/species) belongs in Settings** since it's set once; Home is a pure dashboard.
- Planned but deferred: the full 5-entities-→-one-`HealthEvent` data-model unification.

## Issues
- **The app icon was silently rendering black** — the AppKit CLI bitmap-context approach never actually drew; SwiftUI `ImageRenderer` (run on the main actor) fixed it. The earlier TestFlight build shipped a black icon.
- **First TestFlight build failed validation** on three things, now baked into the repo: missing app icon (added a 1024² no-alpha asset), no `UISupportedInterfaceOrientations`, and the runner defaulting to Xcode 16.4 — App Store now requires the **iOS 26 SDK** (added `setup-xcode` latest-stable).
- **Export failed with "Cloud signing permission error"** until the App Store Connect API key was regenerated as **Admin** (App Manager can't mint a distribution cert).
- **`aps-environment: development`** would have broken the distribution build — removed it (app uses local notifications only).
- **Flaky test-host relaunch** intermittently reports `TEST FAILED` with 0 real failures (CloudKit-sim hiccup); a clean re-run is green. Also fixed a real crash where `PersistenceController` reloaded the model per-instance ("Multiple NSEntityDescriptions claim 'Pet'") — now loads it once.
- **OMC autopilot kept self-triggering**: its keyword detector fires on prompts that merely mention "autopilot", and a stale phantom state file under the (cwd-dependent) `.omc` dir kept the Stop hook nagging. Disabled the keyword hook (`OMC_SKIP_HOOKS=UserPromptSubmit`, needs restart), cleaned the version cache, and removed the phantom state files.

## What to remember
- App Store Connect API key for CI **must be Admin** (cloud signing mints a distribution cert).
- iOS app icons: single 1024×1024, **no alpha**; generate via SwiftUI `ImageRenderer` on the main actor (not AppKit CLI bitmap contexts).
- CI sets `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER` so build numbers stay unique.
- CloudKit must be **deployed to Production** (CloudKit Console, from the Development env) for sync to work in TestFlight/release builds — separate from the build succeeding.
- TestFlight **internal** testing needs no Apple review; **external** testers trigger a one-time Beta App Review.

---

## Commits
- `e135e40` feat(ios): app icon — white paw on brand violet
- `234b169` feat(ios): next reminder anchors to the frequency, not today
- `248e5af` feat(ios): default weight unit to lb
- `ecf4e36` style(ios): brand Timeline + clearer medication/marker forms
- `4ad6356` style(ios): consistent brandSheet() on all add/edit sheets
- `c6e616c` refactor(ios): move Name + Species into Settings
- `e330ec8` feat(ios): pet name in the header, species on the Health tab
- `e7a44b5` feat(ios): pet profile photo (tap the hero avatar)
- `1cb3735` test(ios): move Timeline delete into the view-model + cover it
- `7d8e386` feat(ios): swipe-to-delete on Timeline rows
- `bee1c51` feat(ios): Home dashboard — at-a-glance, quick actions, upcoming, recent
- `53cfba4` feat(ios): Timeline FAB + dashboard-style Home
- `b9f11ee` feat(ios): structured medication frequency that drives the reminder
- `5a36ce9` fix(ios): satisfy App Store validation (icon, orientations, iOS 26 SDK)
- `bb1083f` ci: declare export-compliance exemption
- `6bea765` ci: build + ship to TestFlight from a macOS GitHub Actions runner
- `474e952` feat(ios): consolidate 5 tabs → 3 with a unified Timeline + "due soon" Home
- `abb2112` feat: device pairing (QR + short code)
- `9a0bccd` fix(web): relax password policy + send sign-ups to /dashboard
- `9db0744` feat(ios): wire up the in-app record-upload (Scan a record)
- `1a34b91` docs: restyle autonomous-build writeups as a 4-page HTML site

## Tomorrow's plan
- Confirm the new TestFlight build went VALID and test on-device.
- Optional fuller card redesign of specific add/edit sheets.
- Eventually: data-model unification (5 entities → one `HealthEvent`), plus photos-on-records and a photo diary.
