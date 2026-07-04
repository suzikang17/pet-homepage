# LogEntry Full Unification — Design

**Date:** 2026-07-04
**Status:** Approved direction (user chose "full unification"), pending spec review
**Scope:** iOS app (`ios/PetHomepage`) + `SnapshotBuilder` reads. The Convex mirror **JSON contract stays identical** (dashboard untouched beyond what already ships).

## Problem

The occurrence unification (2026-06-30) collapsed DiaryEntry/ActivityLog/DoseLog into `LogEntry`. Four record types still live as separate Core Data entities — `Vaccination`, `VetVisit`, `HealthMarker`, `SymptomEpisode` — each with its own store, editor plumbing, Timeline branch, reminder path, and mirror read. The user wants the write-side model to match the app's actual concept: *everything is a typed thing that happened on a date, maybe with a next-one-due.*

## Decisions

1. **All occurrences become `LogEntry` kinds.** Final kinds: `diary`, `activity`, `dose`, `vaccine`, `vet`, `marker`, `symptom`.
2. **Definitions and children survive.** `Medication` and `ActivityType` are definitions (a prescription is not an occurrence). `VetRecommendation` and `SymptomEntry` are child rows and stay as entities, retargeted from their old parents to `LogEntry`.
3. **Kind becomes explicit.** Today kind is derived from which ref is set; vaccine/vet/marker/symptom have no defining ref, so `LogEntry` gains `kindRaw: String` (default `"diary"`). Derivation is replaced by the stored kind everywhere; `LogStore` stamps it on create.
4. **Sparse explicit columns, not a JSON blob.** Kind-specific fields are optional attributes on `LogEntry` (CloudKit-safe, queryable). Sparse-but-explicit was chosen over a fields blob deliberately.
5. **Clean cutover, no data migration** — same call as the occurrence unification (existing local data is disposable; confirmed by the user for this same store on 2026-06-30). Old entities are deleted outright.
6. **Per-kind editors stay.** VaccinationEditView, VetVisitDetailView, MarkerEditView, EpisodeStartView keep their UIs — they just read/write `LogEntry` through `LogStore`.
7. **Capture sheet gains the new kinds** (absorbs the previously-planned "photo → vet visit/vaccine/marker" item): tagging a captured photo can now produce any occurrence kind. Vaccine/vet tags open a *prefilled editor sheet* (they have required fields); marker tag inline (value + unit fields appear in the review sheet); symptom excluded from capture v1 (episodes are spans, not snap-moments).

## Entity model after

**Deleted:** `Vaccination`, `VetVisit`, `HealthMarker`, `SymptomEpisode` (entities, model classes, stores).
**Kept:** `Pet`, `Photo`, `Medication`, `ActivityType`, `Veterinarian`, `VetRecommendation`, `SymptomEntry`, `LogEntry`. (12 → 8.)

### `LogEntry` — final shape

Existing: `id, performedAt, note?, intervalDays, nextDueAt?, pet, activityType?, medication?, photos`.

New attributes (all optional / defaulted; CloudKit rules as usual):

| attribute | type | used by |
|---|---|---|
| `kindRaw` | String, default `"diary"` | all |
| `title` | String? | vaccine (vaccineName), vet (reason), symptom (title) |
| `subtypeRaw` | String? | marker (`MarkerType` raw), symptom (category raw) |
| `value` | Double, scalar, default 0 | marker |
| `unit` | String? | marker |
| `lotNumber` | String? | vaccine |
| `administeredBy` | String? | vaccine |
| `clinicName` | String? | vet |
| `vetName` | String? | vet |
| `diagnosis` | String? | vet |
| `treatmentNotes` | String? | vet |
| `statusRaw` | String? | symptom (`active`/`resolved`) |
| `resolvedAt` | Date? | symptom |

New relationships:
- `LogEntry.veterinarian` ↔ `Veterinarian.logEntries` (vaccine + vet visits attach a vet today).
- `LogEntry.recommendations` ↔ `VetRecommendation.logEntry` (replaces `VetRecommendation.vetVisit`).
- `LogEntry.symptomEntries` ↔ `SymptomEntry.logEntry` (replaces `SymptomEntry.episode`).
- `Photo.vetVisit` and `Photo.vaccination` are deleted (photos use `Photo.logEntry`); `Photo.medication` stays (photos on the definition).
- `Veterinarian.vetVisits`/`.vaccinations` relationships are deleted (replaced by `.logEntries`).

Field mapping from the old entities: `administeredAt`/`occurredAt`/`recordedAt`/`startedAt` → `performedAt`; `nextVisitDate`/`nextDueAt` → `nextDueAt`; `vaccineName`/`reason`/`title` → `title`; `markerTypeRaw`/`categoryRaw` → `subtypeRaw`.

## LogStore — per-kind API (added; existing API unchanged)

Split into extensions by kind to keep the file navigable (`LogStore+Vaccine.swift`, `LogStore+Vet.swift`, `LogStore+Marker.swift`, `LogStore+Symptom.swift`):

- Vaccine: `logVaccine(name:performedAt:nextDueAt:lotNumber:administeredBy:veterinarian:)`, `updateVaccine(...)`, `vaccines()`.
- Vet: `logVetVisit(occurredAt:clinicName:vetName:reason:diagnosis:treatmentNotes:nextVisitDate:veterinarian:)`, `updateVetVisit(...)`, `vetVisits()`, `mostRecentVisitDate()`.
- Marker: `logMarker(type:value:unit:recordedAt:)`, `markers()`, `latestMarker(of:)`, `series(of:)` (oldest-first; drives the weight trend).
- Symptom: `startEpisode(category:title:startedAt:)`, `resolveEpisode(_:at:)`, `episodes()`; `SymptomEntryStore` retargets its parent to `LogEntry`.
- All creates stamp `kindRaw`; all kind queries filter on it. `diaryEntries()` changes its predicate from "no refs" to `kindRaw == diary`.

`VaccinationStore`, `VetVisitStore`, `HealthMarkerStore`, `SymptomEpisodeStore` are deleted. `VetRecommendationStore` retargets to `LogEntry`. `MarkerType`, `EpisodeStatus`, symptom category enums survive unchanged (they back `subtypeRaw`/`statusRaw`).

## Consumers

- **Timeline:** `TimelineReference` collapses to `logEntry(LogEntry)` + `medication(Medication)`; `TimelineKind` maps 1:1 from `LogEntry.kind` for filtering/tinting; `load()` = `logStore.allEntries()` + medications. `delete` branches by kind for reminder cleanup (vaccine cancel, vet-cadence resync, activity re-arm — same behaviors as today).
- **Reminders:** `DueReminderScheduler.vaccinationReminder/syncVaccination/cancelVaccination` take `LogEntry`; `syncVetCadence(lastVisit:)` fed by `logStore.mostRecentVisitDate()`. `ReminderKind` cases unchanged (identifiers stay stable).
- **Editors/VMs:** VaccinationEdit, VetVisitEdit/Detail, MarkerEdit, EpisodeStart/Detail VMs swap their store for `LogStore` and their record type for `LogEntry`. UI unchanged.
- **Home (PetProfileView):** due-soon/recent slices already flow through TimelineViewModel; weight/next-vet tiles re-source from `LogStore` marker/vet queries.
- **Extraction (`RecordIngestionService`):** writes scanned vaccines/vet visits via `LogStore` (meds unchanged).
- **Mirror (`SnapshotBuilder`):** reads vaccines/vet visits/markers/symptoms from `LogStore`; DTO structs and JSON keys byte-identical; `schemaVersion` unchanged (shape didn't change).
- **Capture sheet:** adds a "Records" chip group — Marker (inline value/unit), Vaccine and Vet visit (chip opens the prefilled editor with the photo pending). Symptom not offered in capture v1.

## Non-goals

- Multi-pet (next project, designed separately).
- Dashboard/web changes.
- Migrating existing Vaccination/VetVisit/HealthMarker/SymptomEpisode rows (clean cutover; user-confirmed disposable data).
- Unifying `SymptomEntry` into `LogEntry` (child row of an episode; deliberately kept).

## Testing

Per-kind store tests (create/query/update mapping, kind stamping, series ordering), scheduler tests retargeted to `LogEntry`, Timeline aggregation/delete-per-kind, SnapshotBuilder JSON-contract test (golden-key assertions unchanged), capture-sheet tag routing for the new kinds, ingestion-service writes. Full suite green at every step.

## kindRaw backfill (the one migration this DOES need)

Existing `LogEntry` rows (diary/activity/dose created since the occurrence unification shipped) predate `kindRaw` and would all default to `"diary"`. A tiny idempotent backfill runs once at launch (alongside `seedDefaultsIfNeeded`): fetch entries, stamp `kindRaw` from the refs (`medication != nil` → dose, `activityType != nil` → activity, else diary), save. Safe to run repeatedly; covered by a store test.

## Build sequence (same additive→narrow playbook as the occurrence unification)

1. Model: `LogEntry` new attrs/relationships (additive), `kindRaw` stamped by creates, the launch backfill, and queries switched to it.
2. Vaccine kind: LogStore+Vaccine, editor/VM, reminders, Timeline, ingestion, mirror read, tests — old entity untouched.
3. Vet kind: same shape (incl. recommendations retarget + vet cadence).
4. Marker kind: same shape (incl. series/trend + Home tile).
5. Symptom kind: same shape (incl. SymptomEntry retarget, episode detail).
6. Capture sheet: new kind tags (marker inline; vaccine/vet prefilled-editor handoff).
7. Narrow: delete the four entities + stores + dead relationships/model classes; final full-suite pass.
