---
lore_type: devlog
created: 2026-10-10
title: "Care Team list doesn't show vet edits"
date: 2026-10-10
day: 106
---

**Editing a vet saved fine but the Care Team list kept the old clinic until restart; rows now observe their vet. Found by suziQai's feature mode.**

## What got done
- Fixed the Care Team row not refreshing after an edit (branch `fix/care-team-row-refresh`, pushed, not merged). The row is now a `VetRow` view with `@ObservedObject var vet: Veterinarian`.
- Verified on the iPhone 17 Pro simulator (`--uitest` store) by adding "Dr. Sarah Chen, Old Clinic", editing the clinic to "New Clinic", and saving. Before the fix the list still read "Old Clinic", even after switching tabs, although reopening the sheet showed "New Clinic". After the fix the list shows "New Clinic" right away.

## Issues
- Root cause: `CareTeamViewModel.load()` re-fetches the vets, but Core Data hands back the same `NSManagedObject` instances. The `vets` array is "the same" to SwiftUI, and the row read `vet.clinic` without observing the object, so it never re-rendered.
- `VetEditView`'s `onConfirm` is `try? model.save()`, so save errors are silently dropped. Left as is, but worth surfacing.

## What to remember
- Any list row that takes a Core Data object and reads its properties directly has the same trap. Other features with edit sheets over lists (medications, vaccinations, vet visits) are worth checking the same way.
- suziQai's "Edit an existing vet" scenario got stuck with "the list still shows Old Clinic". It had also hit a suziQai bug (iOS `fill` appended instead of replacing), which was fixed first so the app bug could be confirmed separately.

---

## Commits
97be24d fix(care-team): list row shows edits immediately
