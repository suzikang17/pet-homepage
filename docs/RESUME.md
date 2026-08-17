# Resume

## State
`main` = `ca8c9a6`, CI green (425 unit tests), shipped to TestFlight (delivery `81083e52`).
CloudKit `nextReminderAt` deployed to Production; the v1→v2 migration has run on the real device.
Home = Care routine grid → Upcoming reminders → Recent activity. Timeline is history only.
Schedule has a Today/Upcoming subtab. Doses are a first-class `TimelineKind`.

## Next steps
1. **UI tests are broken and CI never runs them.** 3/4 `CaptureFlowTests` + 2 `TimelineTests` fail at
   `sheet.save` after `openCapture()`. Verified failing at `7ca4525` (pre-2026-08-17), so this is old rot,
   not from the catalogue work. Fix them, then add `-only-testing:PetHomepageUITests` to `ios-tests.yml`.
2. **`MedFrequency(parsing:)` silently degrades unrecognised text to daily** — `"1x/month"`, `"q30d"` become
   every-day reminders. Real risk for AI-extracted records (`RecordIngestionService`).
3. Four `docs/features/*.md` still describe the deleted "Due soon" card (001, 005, 006, 007, 014).

## Gotchas
- **CloudKit schema changes need a manual deploy.** The container creates schema only in Development, only
  when a build containing the field runs signed into iCloud. TestFlight uses Production. Order: run from
  Xcode → CloudKit Console → Deploy Schema Changes → Production → then ship. Failure is **silent**.
- `Medication.startedAt` is dead but permanent (CloudKit is append-only). Read `nextReminder`.
- Activity reminders are keyed by the **LogEntry's** id — a new entry does NOT replace the old one's
  reminder; cancel the prior explicitly.
- Suite flakes two ways, both exit 65 with **0 failures**: Core Data harness crash, and runner-hang.
  Judge by `Executed N tests, with M failures`, never the exit code. Re-run.
