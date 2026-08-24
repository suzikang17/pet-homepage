# External events — logging a feeding from outside the phone

**Date:** 2026-08-24
**Status:** draft, awaiting review
**Scope:** phase 2 of [Home Assistant buttons](README.md). Phases 1 and 3 need no application code.

## Problem

A wall button by the food bin should log a feeding. Every existing path into the
health record goes through the app's UI, so today that means: dry hands, unlock
phone, open app, Schedule tab, tap the slot, confirm the sheet. The button exists
precisely because none of that is possible with a scoop in your hand.

Two constraints make this harder than it sounds, and both are load-bearing.

**iOS apps cannot receive inbound requests.** There is no entitlement that lets a
pet-tracking app listen on a port; apps are suspended shortly after
backgrounding. Home Assistant has nothing it could call. This rules out the
obvious design — "give pet-homepage an API" — and it is why the existing mirror
is push-only.

**Core Data must stay the single writer.** `convex/schema.ts:6` states plainly
that the iOS app is the system of record and Convex backs only a read-only
mirror. A second writer would mean either reverse-engineering the
`NSPersistentCloudKitContainer` schema from a server, or splitting truth across
two stores. Both are worse than the latency this design accepts instead.

So: Convex holds an *intent to log*. The phone converts intents into `LogEntry`
rows. Convex never writes health data, and the mirror keeps meaning exactly what
it means today.

## Non-goals

- Editing or deleting existing entries remotely. Write-only, append-only.
- Any event kind other than feedings. The table is general, the drain is not.
- Real-time guarantees. Phase 2b makes it fast; nothing makes it certain.
- Changing how the mirror or CloudKit sync work.

## Architecture

```
Home Assistant ──POST /events/push──► Convex.pendingEvents
                   Bearer <token>            │
                                             │ (2b) silent APNs push
                                             ▼
                                       iPhone wakes
                                             │
                          GET /events/drain  │  Bearer <token>
                                             ▼
                              RoutineStore.logFeeding(...)
                                             │
                                        Core Data
                                       ╱          ╲
                                 CloudKit      /mirror/push
```

Note the loop closes: the resulting entry reaches Convex anyway, via the existing
mirror snapshot. The queue and the mirror stay separate concerns — one is inbound
intent, the other outbound truth.

## Auth — nothing new required

`mirrorTokens` is already exactly the primitive this needs: an opaque per-user
capability token stored as `SHA-256(MIRROR_TOKEN_PEPPER + rawToken)`, resolved to
a `userId` by hash lookup, with a `label` and `revokedAt`. `/mirror/push` in
`convex/http.ts` already demonstrates the full validation path, and the new
endpoints copy it verbatim.

Two consequences worth stating:

- **HA gets its own token**, minted from the dashboard with `label: "Home
  Assistant"`. Because `mirrorTokens` supports per-token revocation, compromising
  the HA box can be contained without unpairing the phone.
- **The phone already holds a token** in the Keychain from pairing, so drain and
  ack need no new credential. The same bearer works in both directions.

## Data model

```ts
pendingEvents: defineTable({
  userId: v.id('users'),
  eventId: v.string(),        // client-supplied UUID; the idempotency key
  kind: v.string(),           // "feeding" today; the table stays open
  occurredAt: v.number(),     // epoch ms of the BUTTON PRESS, not of receipt
  payload: v.optional(v.any()),
  createdAt: v.number(),
})
  .index('by_event_id', ['eventId'])
  .index('by_user', ['userId'])
```

`occurredAt` is the whole reason the design tolerates latency. The entry is
stamped with when the feeding happened, so a phone that syncs three hours late
still produces a correct history — it is late, not wrong.

## Endpoints

All three live in `convex/http.ts` and share the bearer-token check, factored out
of the existing `/mirror/push` handler rather than duplicated.

| Route | Caller | Body | Behaviour |
|---|---|---|---|
| `POST /events/push` | HA | `{event_id, kind, occurred_at}` | Insert; ignore if `event_id` already present. Returns `{ok: true}` either way. |
| `GET /events/drain` | app | — | Returns undrained events for the token's user, oldest first. |
| `POST /events/ack` | app | `{event_ids: [...]}` | Deletes those events for that user. |

Each validates, then delegates to an internal query or mutation — the same split
`/mirror/push` uses when it calls `internal.mirror.upsertForUser`.

Push must be idempotent on `event_id` because HA's `rest_command` retries on
network failure and has no way to know whether the first attempt landed.

## iOS drain

New: `ExternalEventDrain`, sitting alongside `Mirror/`. Runs on app launch and
foreground (phase 2a), plus on silent push (2b).

For each `kind == "feeding"` event:

1. **Pet** — `PetStore.currentPet()`. The active pet is a persisted
   `activePetID` in `UserDefaults`, so a bare button follows whatever pet the app
   is currently showing. See Decision 2.
2. **Day** — the calendar day of `occurredAt`.
3. **Slot** — `RoutineStore.slots(for: day)`, filtered to `isMeal && !isCompleted
   && !isSkipped`, taking the earliest by `(hour, minute)`.
4. **Amount** — `max(0, task.mealAllotment - slot.fedTotal)`, the same remaining
   figure `MealFeedingSheet` prefills.
5. **Write** — `RoutineStore.logFeeding(task, on: day, now: occurredAt, amount:)`
   (`RoutineStore.swift:414`). Passing `occurredAt` as `now` is what backdates
   the entry.
6. **Ack** — only after `context.save()` succeeds. An event that fails to write
   stays queued and retries next drain.

Ack-after-save means a crash mid-drain re-delivers rather than loses. Combined
with step 3, a re-delivery after a successful save is harmless: the slot is now
complete, so the event falls through to Decision 1 instead of double-feeding.

## Decisions

**1. A press with no open meal slot is recorded, not dropped.**

The button asserts that a feeding *happened*. Discarding that because the
schedule disagrees loses real information silently, which is the worse failure.
But the button carries no amount, and inventing one corrupts the allotment maths
that `mealProgress` and `isCompleted` depend on.

So: write a diary entry via `LogStore.createDiary(performedAt: occurredAt, note:)`
noting that a feeding was logged remotely with no open slot. It appears in the
Timeline, it is honest about what is known, and it invents nothing.

*This is the decision most likely to be wrong.* The alternative — an extra
feeding on the nearest slot at full allotment — keeps it in the feeding UI but
overstates the amount. Worth arguing about before implementation.

**2. Multi-pet resolves to the active pet.**

A bare button has no pet. `currentPet()` is what every other surface in the app
already follows, so the button behaving differently would be the surprise. The
failure mode is real but recoverable: switch pets in the app, press the button,
log lands on the wrong pet, delete it.

If that turns out to bite, phase 3 has a natural fix — BILRESA has two buttons,
and HA can send `payload.pet_id` per button. The schema already allows it.

**3. Fixed amount, no prompt.**

One press fills the open slot's remaining allotment. A prompt would mean UI on
the phone, which defeats the entire purpose. `MealFeedingSheet` already lists the
day's feedings with removal, so a wrong amount is correctable in the app.

**4. Events expire after 48 hours.**

A phone offline for a week should not log Tuesday's dinner on Friday. Expired
events are dropped server-side during drain.

## Phase 2b — silent push

`project.yml:65` already declares `UIBackgroundModes: remote-notification` for
CloudKit, so the background mode exists. Still needed: an `aps-environment`
entitlement, an APNs auth key, device-token registration, storing tokens per
user in Convex, and a Convex action that signs a JWT and posts to APNs on insert.

Delivery is best-effort — iOS throttles silent pushes aggressively and suppresses
them in Low Power Mode. Drain-on-launch stays as the backstop permanently; push
is an optimisation, never the mechanism.

Ship 2a first and use it for a week. If drain-on-launch turns out to be good
enough in practice, 2b may not be worth the entitlement churn.

## Failure modes

| Failure | Behaviour |
|---|---|
| HA retries after a timeout | Same `event_id`, insert ignored. No double log. |
| Push throttled or undelivered | Drain-on-launch catches it. Late, not lost. |
| Phone offline for days | Events queue, then expire at 48h (Decision 4). |
| Crash mid-drain | Not acked, retried; re-delivery hits Decision 1, not a double feed. |
| Convex unreachable from HA | `rest_command` fails; the press is lost. Accepted — the alternative is a queue on the HA box, which is not worth it for a feeding. |
| HA token leaked | Revoke that token alone via `revokedAt`; phone pairing unaffected. |

## Testing

Convex, against the existing suite's patterns:

- Push with a valid token inserts; invalid and revoked tokens 401.
- Duplicate `event_id` inserts once.
- Drain returns only the caller's events; ack deletes only the caller's.

iOS, extending `RoutineStoreTests` / a new `ExternalEventDrainTests`:

- A feeding event backdates `performedAt` to `occurredAt`, not to now.
- Amount equals the slot's remaining allotment; a partially-fed slot tops up.
- Two events for one slot fill it and then fall through to a diary entry.
- An event on a day with no open meal slot writes a diary entry.
- A failed save leaves the event unacked.
- An event older than 48h is dropped.

End-to-end proof before this is called done: press the HA dashboard button,
launch the app, screenshot the entry in the Timeline with the correct
backdated time.

## Open questions

- Decision 1 is a genuine coin-flip. Diary entry, or extra feeding at full
  allotment?
- Should the dashboard grow a token-minting UI labelled for HA, or is reusing the
  existing pairing flow enough?
