# Architecture

*Last updated 2026-07-04 (post LogEntry unification + multi-pet). Audience: anyone — PM, designer, or engineer — who needs the shape of the system without reading code. The feature-by-feature view lives in [`docs/features/`](features/index.md).*

## The system at a glance

```
┌─────────────────────────────  iPhone (system of record)  ────────────────────────────┐
│                                                                                       │
│  SwiftUI views ── ViewModels ── Stores ── Core Data ⇄ CloudKit (private iCloud sync)  │
│       │                                                                               │
│       ├─ Local notifications (meds, vaccines, vet cadence, activities)                │
│       └─ Camera / photo library / Contacts / Vision OCR (all on-device)               │
│                                                                                       │
└───────────────┬───────────────────────────────────────────────┬──────────────────────┘
                │  snapshot push (one-way, token-auth)           │  document scan (photo/PDF)
                ▼                                                ▼
┌────────────  Web (Next.js + Convex)  ────────────┐   ┌─────────────────────────┐
│  Convex: mirrors, mirrorTokens, pairingCodes     │   │  /api/extract           │
│  Dashboard: read-only render of the snapshot     │   │  (Claude vision →       │
│  Sign-in: Convex Auth · Pairing: code/QR → token │   │   parsed records)       │
└──────────────────────────────────────────────────┘   └─────────────────────────┘
```

**The iOS app owns all pet data.** iCloud (CloudKit) syncs it between the user's devices. The web side holds only: auth for the dashboard, pairing/capability tokens, and the latest opaque snapshot per user. Nothing on the web can write pet data.

## The data model: one occurrence entity

The core idea, arrived at through two unification passes: **everything that happens on a date is one row type.**

```
LogEntry  ─ the occurrence ─  kind: diary | activity | dose | vaccine | vet | marker | symptom
   ├─ always: performedAt, note?, photos[], pet
   ├─ repeatable things: intervalDays, nextDueAt   (drives "Due soon" + reminders)
   └─ kind-specific (sparse): value/unit (marker) · lotNumber/administeredBy (vaccine)
                              clinicName/vetName/diagnosis/treatmentNotes (vet)
                              statusRaw/resolvedAt (symptom) · title, subtypeRaw
```

Around it, only things that are genuinely *not* occurrences remain entities — **8 total**:

| Entity | Role |
|---|---|
| `LogEntry` | every occurrence (7 kinds above) |
| `Pet` | the animal; everything scopes to a pet |
| `Medication` | a *definition* (prescription) — doses are LogEntries pointing at it |
| `ActivityType` | a *definition* (Bath, Nail trim…) — user-editable, pre-seeded |
| `Veterinarian` | care-team contact, attachable to records |
| `VetRecommendation` | child rows of a vet-visit LogEntry |
| `SymptomEntry` | dated check-ins, child rows of a symptom LogEntry |
| `Photo` | image + caption, attached to a LogEntry, a Medication, or the Pet |

Why it's this way: the **definition vs. occurrence** split is load-bearing. Occurrences share one shape (when, what, note, photos, maybe next-due), so they share one table and one store — that's what makes the unified Timeline, "Due soon," and capture-tagging need no special cases. Definitions differ wildly (a prescription ≠ a grooming preset) and are the things users name, edit, and archive — so they stay distinct.

## Layers on the iOS side

- **Stores** (one per concern) are the only things that touch Core Data: `LogStore` (all occurrences; per-kind extensions for vaccine/vet/marker/symptom), `PetStore` (pets + the *active pet*), `MedicationStore`, `ActivityStore` (types + seeding), `VeterinarianStore`, `VetRecommendationStore`, `SymptomEntryStore`, `DiaryStore` (medication photos only).
- **Everything is pet-scoped through one choke point:** `PetStore.currentPet()` — the active pet (persisted per device). This single indirection is what made multi-pet a small feature.
- **ViewModels** (`@Observable`) own flows and side-effects; notably, **reminder scheduling is ViewModel-driven, never store-driven** — a store saves, then the ViewModel syncs notifications.
- **Notifications**: a pure, testable scheduler (`DueReminderScheduler`, `MedicationReminderScheduler`) behind a protocol; only one adapter touches the real notification center. Reminders are keyed `(kind, recordID)` so schedule/replace/cancel are idempotent.
- **Capture pipeline**: center camera tab → `CameraPicker` (full-screen) → downscale (pixel-capped JPEG) → review-and-tag sheet → the matching `LogStore` create + photo attach. Vision OCR (`TagSuggester`) suggests a tag by matching label text against the user's med/activity names — entirely on-device.
- **Mirror push**: `SnapshotBuilder` reads through the stores and emits a versioned JSON snapshot (schema v4, snake_case, ISO dates); pushed to the web with a hashed capability token from the pairing flow.

## The web side

Next.js (repo root `app/`, `components/`) + Convex (`convex/`):
- **Convex tables**: `mirrors` (one snapshot blob per user), `mirrorTokens` (SHA-256-hashed capability tokens; raw token lives only in the phone's Keychain), `pairingCodes` (short-lived, single-use codes minted by the dashboard, claimed by the phone).
- **Dashboard** (`MirrorDashboard`): renders the snapshot sections read-only; parses newer fields optionally so old snapshots never break it. `MirrorTokensManager` lists/revokes devices.
- **`/api/extract`**: the one cloud-AI endpoint — Claude vision parses a scanned document into vaccine/vet/med records the app then writes locally.

## Cross-cutting conventions

- **CloudKit rules everywhere**: every relationship optional with an inverse; enums persisted as `*Raw` strings with a safe fallback for unknown values (forward-compatible with newer app versions).
- **Additive → migrate → narrow**: model refactors land as green steps (add new shape, move consumers kind-by-kind, delete the old) with the full test suite passing at each step; data migrations so far have been clean cutovers plus one idempotent launch backfill (`kindRaw`).
- **Design system** (`DesignSystem/`): `Theme` (electric-violet brand), `HeroHeader`, `BrandFormSheet`, shared photo sections with camera + library, `BrandCard/BrandList`.
- **Testing**: ~230 unit tests over in-memory Core Data; schedulers tested against a fake notification center. Known simulator quirk: the full suite exits 65 even when green (CloudKit launch crash + auto-retry) — judge runs by pass/fail counts.

## Where things are decided

- Specs: `docs/superpowers/specs/` (activities, full unification, multi-pet).
- Day-by-day history: `docs/devlog/` (lore).
- Feature inventory: `docs/features/` (lore `feature` type — the PM-facing view).
