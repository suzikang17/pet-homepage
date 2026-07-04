---
lore_type: devlog
created: 2026-07-04
title: "Activities, camera-first capture, and the full LogEntry unification"
date: 2026-07-04
day: 8
---

**Shipped the Activities feature, made the app camera-first (center camera tab + OCR tag suggestion), and completed the full data-model unification: 12 Core Data entities → 8, with everything that happens on a date now a `LogEntry` kind.**

## What got done
- **Activities**: user-defined `ActivityType`s (pre-seeded, editable, categorized, per-type reminder times) + logged occurrences with cadence → "Due soon" + notifications. Type editor, archive, icon picker.
- **Camera capture everywhere**: "Take photo" in the shared photo sections, then a **center camera tab** (Home · Timeline · 📷 · Diary · Care Team) → instant viewfinder → review-and-tag sheet. A photo becomes a diary entry, activity, dose, marker (inline value), or hands off to the prefilled vaccine/vet editors.
- **On-device OCR tag suggestion**: Vision OCR + whole-word fuzzy match against the user's med/activity names pre-selects the matching chip with a ✨ — no network, no API cost.
- **Occurrence unification** (phase 1): DiaryEntry + ActivityLog + DoseLog → one `LogEntry` behind one `LogStore`.
- **Full unification** (phase 2): Vaccination, VetVisit, HealthMarker, SymptomEpisode also became `LogEntry` kinds (`kindRaw`: diary/activity/dose/vaccine/vet/marker/symptom; sparse optional columns for kind fields). Definitions (Medication, ActivityType) and children (VetRecommendation, SymptomEntry) survived, retargeted. Final model: 8 entities.
- **Mirror**: activity logs now render on the desktop dashboard; all snapshot reads re-sourced through LogStore with the JSON contract byte-identical.
- **Multi-pet**: active-pet selection behind `PetStore.currentPet()`, avatar menu (Switch/Add/Change photo), per-pet vet-cadence reminder identity, pet names in notification copy, seeding on switch.
- **Diary merged into Timeline**: diary entries flow into the stream as a filter chip; the photo grid became a Stream|Photos in-tab view mode; Diary tab deleted (4-tab layout: Home · Timeline · 📷 · Care Team).
- Device bug fixes: camera collapsing (nested-sheet → `.fullScreenCover` + explicit dismiss), Contacts import dropping picks (`CNContactPickerViewController` must be *presented by* a VC, not be a sheet's root).

## Decisions
- **Definitions vs occurrences** is the load-bearing split: occurrences unify into LogEntry; definitions (Medication, ActivityType) and child rows stay as entities. "Full unification" ≠ god-object.
- Kind is an explicit stored `kindRaw` (with a one-time launch backfill from refs), not derived — vaccine/vet/marker/symptom have no defining ref.
- Sparse explicit columns over a JSON fields blob (CloudKit-safe, queryable).
- Clean cutover migrations (data disposable, user-confirmed) — additive → per-kind consumer migration → narrow deletion, full suite green at every step.
- Camera-centric without compromising utility: camera owns the center tab; structured logging keeps Timeline's "+" (Home's capture bar removed as redundant).
- OCR before paid AI: try on-device Vision first; Claude fallback only with evidence it's needed.

## Issues
- `xcodebuild test` exits 65 with "TEST FAILED" **even when all tests pass**: the host app crashes once at launch on the simulator (CloudKit `CKAccountStatusNoAccount`), xcodebuild restarts and everything passes. Judge runs by counting `' passed ('` vs `' failed ('` lines. Confirmed pre-existing on main via a worktree baseline.
- Swift optional-enum gotcha shipped and got caught in review: `optionalEnum == .none` resolves to `Optional.none`, so nil "matched" and lit a phantom ✨ on the Note-only chip. Spell out `CaptureTag.none`.
- `preparingThumbnail(of:)` is point-based — on a 3× device it returns 3× the pixels you asked for; the downscaler uses an explicit `UIGraphicsImageRenderer(scale: 1)`.
- Presenting a sheet in the same SwiftUI transaction as dismissing a full-screen cover silently drops the sheet — stage state and promote it in `onDismiss`.
- Known flaky test: `ActivityLogEditViewModelTests.testSaveCancelsPriorLatestReminderOfSameType` (cross-test Core Data pollution; passes in isolation).
- One subagent stalled mid-narrow-pass (watchdog); its deletions were complete — finished the DiaryStore cleanup inline and verified. Ledgers made recovery trivial.

## What to remember
- The whole app scopes through `PetStore.currentPet()` — that choke point is what made both unification and multi-pet cheap.
- `LogStore` is the single occurrence API; per-kind extensions live in `LogStore+Vaccine/Vet/Marker/Symptom.swift`. Surviving enums moved to `MarkerType.swift`, `EpisodeStatus.swift`, `SymptomCategory.swift`.
- Mirror `schemaVersion` is 4 (activity_logs added); dashboard parses all new keys optionally.
- Simulator destination that works: **iPhone 17 Pro** ("iPhone 16" doesn't resolve).

---

## Commits
01fd0f8 feat: merge Diary into Timeline — diary chip, Stream|Photos view mode, 4-tab layout
7e9a30e feat: pet switcher — avatar menu, switch/add sheets, seeding on switch
a74f098 feat: per-pet vet-cadence identity + pet names in reminder copy
956b7f6 feat: active-pet selection in PetStore
2a7d038 docs: multi-pet design spec
d484021 refactor: delete Vaccination/VetVisit/HealthMarker/SymptomEpisode entities (unified into LogEntry)
5b9b89c feat: capture photos into markers, vaccines, and vet visits
8ad71b3 refactor: symptom episodes as LogEntry kind
4917306 refactor: health markers as LogEntry kind
b0e8e81 refactor: vet visits as LogEntry kind
24d2723 refactor: vaccine records as LogEntry kind
063e1f1 refactor: LogEntry gains explicit kindRaw + record-kind columns (additive)
7c15233 feat: per-activity reminder times
6dd5714 feat: remove Home capture bar (center camera tab + Timeline + cover it)
2a7e577 feat: mirror activity logs to the desktop dashboard
8745697 docs: full LogEntry unification design spec (12 entities → 8)
c89d66e fix: phantom ✨ on Note-only chip — bare .none resolved to Optional.none
ca1cc84 feat: on-device OCR tag suggestion in capture review
562ae3b fix: present capture review sheet from camera cover's onDismiss
daf1703 feat: center camera tab + capture review-and-tag sheet
cb9b11e feat: dashboard Capture hub — bottom Capture button routing to all editors
117672a refactor: delete DiaryEntry/ActivityLog/DoseLog entities (unified into LogEntry)
4ac2696 refactor: migrate dose logging to LogEntry/LogStore; remove DoseLogStore
b1a97da refactor: migrate Diary occurrences to LogEntry/LogStore
ec6c399 refactor: migrate Activity occurrences to LogEntry/LogStore
2257d02 fix: camera capture and Contacts import both collapsing on device
48d9a51 feat: add unified LogEntry entity + LogStore (additive foundation)
8c09498 feat: move "Scan a record" from dashboard into the Timeline add menu
6252bb2 feat: group low-frequency record types under a Health record submenu
ee05d1c feat: activity follow-ups — type editor, delete re-arms reminder, UI polish
dae24aa feat: activity log sheet, type management, and Timeline wiring
b3e1313 fix: propagate edit-path save error in ActivityLogEditViewModel
e50df43 feat: ActivityLogEditViewModel with cadence + reminder sync
e3c21b2 feat: surface activity logs in the unified Timeline
86f2fe6 feat: camera capture in shared photo sections
0f4b565 feat: add activity due reminders to DueReminderScheduler
f9fba7b feat: seed default activity types (idempotent, dedupe by name)
1c3081c feat: add ActivityStore type CRUD, logging, and queries
66c4136 feat: add ActivityType and ActivityLog Core Data entities
30c816f feat: add ActivityCategory enum
