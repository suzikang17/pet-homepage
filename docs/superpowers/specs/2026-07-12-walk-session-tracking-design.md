---
lore_type: spec
title: "Walk session tracking — optional start/end times + auto-detection"
status: approved
date: 2026-07-12
---

# Walk session tracking

Optional start/end times for activity and routine logs, an in-progress "walk
session" with a Live Activity, and location/motion auto-detection that prompts
to start a walk and silently ends it when the owner returns home. Approved
approach: single release (Approach B) — one session model drives both manual
and detected flows.

## Decisions (from brainstorming)

- **Scope of durations:** activity logs *and* routine-task completions.
- **Detection posture:** full detection (Always-location + motion + home
  geofence) *and* first-class manual start/end.
- **Auto-end:** silent at the home-geofence crossing, with an undo/edit
  notification. No confirmation step.
- **Prompt rule:** prompt after ~4–5 min sustained walking away from home
  (start backdated to home exit). User setting: Any sustained walk (default) /
  Only near scheduled walks (±60 min) / Off.

## Data model

- `LogEntry.endedAt: Date?` — new optional Core Data attribute (lightweight
  migration). `performedAt` remains the start/occurrence time; duration is
  always derived, never stored. Only `.activity` and `.routine` kinds set it.
- `ActiveWalkSession` — Codable struct in UserDefaults (not Core Data), at
  most one: `{ id, petID, activityTypeID?, routineLineageID?, startedAt,
  source: manual|detected }`. Survives app kill; readable from notification
  handlers and the Live Activity.
- Mirror contract: `activity_logs[].ended_at` optional field;
  `schema_version` bump. Web dashboard renders "5:10–5:42 PM · 32 min" where
  present (maintenance-level change).

## Session lifecycle — `WalkSessionStore`

API: `start(type:source:startedAt:)`, `end(at:)`, `cancel()`,
`expireIfStale()`. `end` writes the LogEntry through existing paths
(`LogStore` for ad-hoc activities, `RoutineStore.checkOff` for slot
completions, both now accepting an optional end time) and clears the session.
Starting while a session is active prompts to end the first. Sessions older
than 4 h auto-expire: entry saved without `endedAt` + "never ended — tap to
fix" notification.

## Manual UI

- **ActivityLogEditView:** "Performed" becomes date+time; "Add end time"
  toggle reveals an end picker (end ≥ start validated); computed duration
  label.
- **Start actions:** long-press/swipe "Start now" on duration-friendly
  activity types (Exercise/Grooming); routine slot long-press menu gains
  "Start walk" for those categories. Completing via session records real
  start/end.
- **Live Activity** (ActivityKit widget extension): pet name, elapsed time,
  End button routed through WalkSessionStore.
- **Routine walk notification actions:** Start walk / Mark as done / Skip /
  Snooze — same registered-category + pure string-keyed handler pattern as
  `RoutineActionHandler`.
- Timeline/Schedule rows show "5:10–5:42 PM · 32 min" when `endedAt` exists.

## Detection — `WalkDetector`

- **Home geofence:** one `CLCircularRegion` (~100 m) around a user-set home
  location (Settings map picker + "use current location"). Detection disabled
  with explanation until home is set.
- **Start path:** region exit → `CMMotionActivityManager` check → after
  ~4–5 min sustained walking, local notification "Looks like a walk with
  {pet} — log it?" [Start (backdated to exit), Not now]. "Not now" suppresses
  until next home exit. If a routine walk slot is open within ±90 min, the
  started session attaches to it; else default walk activity type.
- **End path:** region entry with an active session (manual or detected) →
  end silently at crossing time → "Walk logged — 34 min · Edit / Undo"
  notification. Undo reopens the session; Edit deep-links to the entry.
- **Prompt-rule setting** as decided; Off also stops motion checks (geofence
  kept only while a session is active, for auto-end).

## Permissions

Staged: When-In-Use first, then an explainer screen for Always ("end the walk
the moment you're home, even with the app closed") before requesting.
Degradation: manual logging never depends on location; Settings reflects the
true permission state.

## Edge cases

- App killed mid-walk: session persists in UserDefaults; geofence entry
  relaunches and ends it.
- Walk starting and ending away from home: no geofence entry — Live Activity
  End button or 4 h expiry covers it.
- Brief pauses (crossing streets, sniffing): sustained-walking filter uses a
  rolling window, not consecutive samples.
- Low Power Mode: motion throttling may delay prompts — accepted.
- Multiple pets: v1 binds sessions to the active pet profile.
- Stale notification actions must not double-log (same dedupe rule as
  `RoutineActionHandler`).

## Testing

`WalkSessionStore` and `WalkDetector` take injected clock / location / motion
/ notification-scheduler protocols (fakes in the style of
`FakeExtractionService`). Unit tests: state machine transitions, prompt-rule
gating, backdating, 4 h expiry, undo-reopen, stale-action dedupe, end≥start
validation. Detection thresholds (sustained-walk minutes, geofence radius,
slot-attach window) live in one `WalkDetectionTuning` constants struct for
TestFlight iteration.
