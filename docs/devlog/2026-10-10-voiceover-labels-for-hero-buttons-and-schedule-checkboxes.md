---
lore_type: devlog
created: 2026-10-10
title: "VoiceOver labels for hero buttons and schedule checkboxes"
date: 2026-10-10
day: 106
---

**The Home settings gear read out as "gearshape.fill" and every schedule check-off as "circle"; both now have real labels, on a branch awaiting merge.**

## What got done
- Gave every hero icon button an explicit accessibility label. `HeroHeader` gained `settingsLabel` (default "Settings"); Schedule passes "Edit routine" and Timeline "Manage activity types". The add and avatar buttons read "Add" and "Change photo".
- Gave the schedule check-off button the label "Mark <task> done" or "Mark <task> not done", depending on state.
- Verified in the simulator by dumping the accessibility tree with `--uitest`. Home now has 7/7 tappable elements labelled.
- Pushed on `a11y/header-and-schedule-labels` (`e83210c`). Not merged.

## Decisions
- Used action-style labels on the check-off button ("Mark Breakfast done") rather than label + value. VoiceOver then reads what the tap does, and tests can target it by its words.
- Left identifiers untouched, so existing tests that query by identifier (`timelineViewModePicker` and others) are unaffected.

## Issues
- Found while using pet-homepage as the first target for suziQai's iOS automation. Jev picked the right element on 13/14 test intents, despite the bad labels, because the developer identifiers carried the meaning.
- 6 of 11 UI tests fail **identically on unmodified `main`**: 3 CaptureFlow, 2 Timeline, and ScheduleTests check-off. That's old breakage, as RESUME already notes, not from this change.
- New root cause for `ScheduleTests.testScheduleSeedAndCheckOffWithPhoto`: the row's `.accessibilityIdentifier("scheduleRow.<name>")` overrides the checkbox's own `"scheduleCheck.<name>"`. The test therefore can't find `scheduleCheck.Breakfast`, and the checkbox shows up in the tree as `scheduleRow.Breakfast`.

## What to remember
- SF Symbols don't reliably supply a VoiceOver label. An image-only `Button` exposes the raw symbol name, so always add `.accessibilityLabel`.
- A SwiftUI identifier on a container propagates to and overrides its children's identifiers. Put the identifier on the specific control, or on a non-wrapping element.
- Still unlabelled: 4 Settings form fields (2 text fields, a switch, a secure field).

---
## Commits
e83210c fix(ios): VoiceOver labels for hero buttons and schedule checkboxes
