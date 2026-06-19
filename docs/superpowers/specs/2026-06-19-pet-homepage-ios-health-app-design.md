# pet-homepage v2 — iOS Health App — Design

**Date:** 2026-06-19
**Status:** Approved design, pre-implementation
**Supersedes:** the web-first, email-ingestion direction in `docs/03-pet-product-spec.md` / `docs/04-features.md`

---

## 1. Summary

`pet-homepage` pivots from a **web-first, passive ingestion** product (owner forwards
email/SMS → AI extracts → web page) to an **iOS-native, active-logging** app where a
pet owner opens the app and taps to log medications, vaccinations, vet visits, weight,
health markers, and symptoms — with **notifications** as the core habit driver.

AI extraction does not go away; it moves from being *the* interface to being one
convenient input among many (upload a vet PDF / photo of a record → Claude pulls out
structured fields).

v1 ships the **full health record**. The photo diary is deferred to v2.

### Primary user
A single pet owner tracking the health of **one pet** (single-pet in v1; the model can
grow to multi-pet later).

---

## 2. Architecture

| Concern | Choice |
| --- | --- |
| App | **iOS native, SwiftUI** (no Android in this direction — the CloudKit trade) |
| Local store / sync | **Core Data + CloudKit** (`NSPersistentCloudKitContainer`) — offline-first, auto-syncs to the user's **private** iCloud DB |
| Raw documents | **iCloud Drive** container — originals (vet PDFs, record photos) stored as real files, visible in Finder / iCloud.com, shareable via links |
| AI extraction | **Stateless Next.js `/api/extract` endpoint** running Claude (`generateObject` + existing discriminated-union Zod schema). App sends a file, gets structured fields back, writes them into Core Data. Server never touches iCloud. |
| Desktop / web | **Opt-in app→Convex mirror → Next.js read-only dashboard** (Mac + Windows) + cloud backup |
| Notifications | **On-device local notifications** (fire offline, no server cron) |

### Why CloudKit
Offline-first for free (local store is source of truth, Apple syncs it), zero backend
cost, maximally private (data in the user's own iCloud), no auth to build (Apple ID),
multi-device included.

### The core tension (acknowledged)
You cannot simultaneously have *no backend*, *data only in private iCloud*, and a
*smooth Windows web dashboard*. Resolution: the **app** is private/offline-first on
CloudKit; the **web dashboard** is served by an **opt-in mirror** to a small backend
(a copy of data leaves iCloud, mitigated by opt-in / minimal fields / optional
client encryption). Raw documents reach the web via iCloud Drive links with no mirror.

### What is retired vs reused
- **Retired:** Convex as the *app's* primary data store (CloudKit replaces it). The
  Cloudflare email-ingest worker and the email/SMS passive-ingestion flow are **not**
  in v1 scope.
- **Reused:** the AI extraction lib (`lib/ingestion/extract.ts`) and the Zod record
  schemas (`lib/schemas/extraction.ts`) — they back `/api/extract` and serve as the
  blueprint for the Core Data model. Convex returns in a smaller role as the **mirror
  sink + dashboard source**.

---

## 3. Project structure (one repo)

```
pet-homepage/
  ios/      ← NEW Xcode SwiftUI project (the app)
  web/      ← slimmed Next.js: /api/extract + CloudKit-mirror dashboard (Convex-backed)
  shared/   ← record schema as single source of truth (Zod, mirrored into Swift models)
  docs/     ← existing Obsidian vault (this spec lives in docs/superpowers/specs/)
```

`shared/` is the canonical record definition. Swift models are mirrored from it; keep
them in sync deliberately (see Risks).

---

## 4. Data model (Core Data entities)

Mapped from the existing Convex schema (`convex/schema.ts`) plus new entities for
dose logging, symptoms, generic markers, recommendations, and attachments.

- **Pet** (single in v1): name, species, breed, dob, adoptionDate, photo
- **Medication**: drugName, dosage, frequency, schedule (drives reminders), startedAt,
  endedAt, refillDueAt
- **DoseLog** *(new)*: medicationID, givenAt — powers "when did I last give the
  preventative"
- **Vaccination**: vaccineName, administeredAt, nextDueAt, lotNumber, administeredBy
- **VetVisit**: occurredAt, clinic, vetName, reason, diagnosis, treatmentNotes,
  nextVisitDate; links to attachments
- **VetRecommendation** *(new)*: vetVisitID?, date, text — "logging recommendations
  from vets"
- **HealthMarker** *(new, generic; absorbs weight)*: type (weight, appetite, energy,
  water, …), value, unit, recordedAt
- **SymptomEpisode** *(new)*: category (digestive, skin, behavior, diet, energy,
  other), startedAt, resolvedAt?, status — the container for "start tracking a
  digestive issue"
- **SymptomEntry** *(new)*: episodeID, date, severity (mild/moderate/severe), note,
  suspectedCause — daily logs under an episode
- **Attachment**: fileName, type, iCloud Drive path, linked record — the originals

---

## 5. v1 feature modules & screens

1. **Pet profile** — create/edit the single pet
2. **Medications** — list, tap-to-log a dose, "last given," refill tracking, reminder
   schedule
3. **Vaccinations** — records, "last / next," due reminders
4. **Vet visits** — log a visit; **upload a record → AI extract** fields; **log vet
   recommendations**
5. **Weight & health markers** — log values, view trend
6. **Symptoms** — start an episode → add daily entries with severity + suspected cause

Deferred to **v2:** photo diary (upload, browse over time, albums/backgrounds/year
exports).

---

## 6. Notifications

On-device **local notifications**, scheduled by the app, so they fire offline with no
server dependency:

- **Medications** — "give the meds at 6pm" per the med's schedule
- **Vaccinations** — due/overdue based on `nextDueAt`
- **Vet visits** — a **configurable cadence** ("see vet every N months"), set up front

---

## 7. Desktop / web layer (phase 5)

- **Documents:** originals live in iCloud Drive → shareable links, viewable in Finder
  and on iCloud.com on **Mac and Windows**, no app needed. Covers "grab the bloodwork
  on my laptop."
- **Dashboard:** when online (and **opt-in**), the iOS app mirrors records to **Convex**;
  a **Next.js read-only dashboard** reads Convex and renders the pet's health record on
  any browser. Doubles as **cloud backup**.
- **Privacy mitigation:** mirror is opt-in; consider mirroring minimal/non-sensitive
  fields and/or client-side encryption of sensitive notes.

---

## 8. Build sequence (phased within v1 — each phase shippable)

1. **Foundation** — Xcode SwiftUI project, Core Data + CloudKit, Pet profile, iCloud
   Drive plumbing
2. **Meds + notifications** — the core habit loop (log doses, "last given," reminders)
3. **Vaccinations + vet visits** (incl. recommendations) + **AI record-upload endpoint**
   (`/api/extract`)
4. **Weight/markers + symptom tracking**
5. **Desktop** — iCloud Drive document links + app→Convex mirror + Next.js dashboard

Optional leaner first release: ship phases 1–3, fold 4–5 into a fast-follow.

---

## 9. Risks / open questions

- **CloudKit JS avoided**, but the **opt-in mirror** means a copy of health data leaves
  iCloud — confirm the privacy posture (opt-in default, field scope, encryption).
- **No Android** in this direction.
- **Schema duplication** (Zod ↔ Swift Core Data) — `shared/` is canonical; needs a
  deliberate sync discipline (and ideally a check).
- **CloudKit schema migrations** are constrained (additive-friendly, deletes are
  painful) — design entities with growth in mind.
- **Apple Developer Program** membership required for CloudKit + device builds.
- **Single-pet → multi-pet** later will touch navigation and every screen's "which
  pet" context — keep that seam clean even while v1 is single-pet.
