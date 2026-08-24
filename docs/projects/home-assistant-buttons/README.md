# Home Assistant buttons

Fire real actions from outside the phone: a wall button that starts the robot
vacuum on a delay, and a wall button that logs a meal into pet-homepage.

**Status:** designed, not started. Phase 1 needs no code.

## The two ideas

| | What it does | Touches the app? |
|---|---|---|
| **Vacuum** | One press → vacuum starts in 30 min | No |
| **Meal** | One press → a feeding lands in the health record | Yes — see the spec |

They look like one project but only share a control plane. The vacuum is pure
Home Assistant configuration. The meal button is the engineering.

## Hardware

- **MOVA P10 Pro Ultra** — no Matter, no HomeKit. Alexa/Google only for native
  voice, which is useless for automation. Controlled instead via Home Assistant
  and [Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum), which
  lists this exact model (`mova.vacuum.r2491a`, `mova.vacuum.r2570`). MOVA is a
  Dreame sub-brand, so it rides the same protocol. Cloud-backed, so firmware or
  app updates can break it.
- **IKEA BILRESA dual button** — $17.99, Matter over Thread, with a Zigbee
  fallback mode that pairs to HA over ZHA. Needs a Thread border router; the
  HomePod mini already on hand is one.
- **HomePod mini** — Thread border router. Note it can *not* run the meal
  automation: Apple Home automations execute on the hub, and the hub has no copy
  of pet-homepage to invoke. This is why the meal path routes through a server.

### Rejected

- **NFC tags** (~$1) — need the phone in hand, which defeats the point. The
  whole scenario is hands full at the food bin.
- **Flic 2** ($35) — works, but needs the phone in Bluetooth range, and BILRESA
  does the same job for half the price once HA exists.
- **Bluetooth shutter remotes** ($6) — present as a BLE keyboard; iOS has no
  supported way to bind a keystroke to a Shortcut. Untested, likely a dead end.
- **Writing to CloudKit directly from HA** — `NSPersistentCloudKitContainer`
  mangles the schema into `CD_`-prefixed record types and keeps private sync
  bookkeeping. Reverse-engineering that from a server risks corrupting sync for
  a shortcut that saves one endpoint. Not worth it.

## Architecture

Home Assistant is the control plane. Every trigger — dashboard button, physical
button, companion-app widget — calls the same two HA scripts.

```
   HA dashboard              BILRESA (phase 3)
   [Vacuum] [Fed]              (1) (2)
        |                        |
        +-----------+------------+
                    v
            Home Assistant
       script.vacuum_delayed / script.log_meal
              |               |
      delay 30m|               |rest_command POST
     vacuum.start|              |
              v               v
        Mova P10          Convex  (pendingEvents)
                              |
                              v  push / launch
                        iPhone drains -> Core Data
```

The vacuum branch ends at HA. The meal branch has to cross into the app, and
that crossing is the whole design problem.

## Why the meal button needs a server

Two constraints, both immovable:

1. **iOS apps cannot receive inbound requests.** No app can host an API — apps
   are suspended shortly after backgrounding. HA has nothing to call. Traffic
   only ever flows outward from the phone.
2. **Core Data stays the single writer.** `convex/schema.ts:6` states the iOS
   app is the system of record and Convex only backs a read-only mirror. Nothing
   here changes that.

So Convex holds an *intent to log*, and the phone converts it into a `LogEntry`.
Convex never writes health data.

## Phases

**Phase 1 — vacuum. No code.**
Install HA, add the `dreame-vacuum` integration, one script, one dashboard
button. The vacuum idea is finished and pet-homepage is untouched.

**Phase 2 — the meal path.** See
[`2026-08-24-external-events-design.md`](2026-08-24-external-events-design.md).
Split in two so the risky half is isolated:

- **2a** — Convex inbox + drain on app launch. No APNs, no entitlement work.
  Proves the queue, dedupe, slot resolution, and backdated timestamps.
- **2b** — silent push, so it lands in seconds instead of at next launch. This
  is where iOS background-wake reliability gets tested for real.

**Phase 3 — BILRESA.** ~$18. Binds to the two scripts that already exist.
Touches no application code.

Each phase is independently useful. Phase 2 carries all the risk.

## Home Assistant sketch

```yaml
rest_command:
  pethomepage_log_feeding:
    url: https://<deployment>.convex.site/events/push
    method: POST
    headers:
      Authorization: !secret pethomepage_token
    content_type: application/json
    payload: >-
      {"event_id":"{{ event_id }}",
       "kind":"feeding",
       "occurred_at":"{{ now().isoformat() }}"}

script:
  vacuum_delayed:
    sequence:
      - delay: "00:30:00"
      - action: vacuum.start
        target:
          entity_id: vacuum.mova_p10_pro_ultra
```

The token is an existing mirror token minted from the dashboard — see the spec.
