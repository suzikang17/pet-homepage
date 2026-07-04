---
lore_type: planning
title: "Hardware Vision"
status: frozen
---

# Hardware Vision

## TL;DR

Hardware is a compelling long-term bet but a terrible place to start. Build the software-only product first, validate the thesis, use the existing user base as distribution for eventual hardware. In the meantime, integrate with existing wearables as a middle path.

## Why hardware is compelling *eventually*

The software-only product has one fundamental weakness: it relies on the user remembering to log things. Email ingestion solves half of this (vet bills and confirmations arrive in email naturally), but the daily "how is my pet doing" data is still manual.

Hardware flips that:

- **Passive, continuous data** — no forwarding, no texting, no remembering
- **Generates the signals that make AI features work** — activity trends, sleep quality, weight changes, anomaly detection
- **Creates a real moat** — software is copyable; hardware + software + cloud is harder to copy
- **Recurring revenue anchor** — pet owners happily pay subscriptions for hardware they already own
- **Physical brand presence** — the collar becomes visible proof of the product

## What hardware could eventually do

### Tier 1: table stakes (what every competitor has)

- Step / activity tracking
- Resting vs. active hours
- GPS location (#1 reason people buy pet wearables — lost pet recovery)
- Environment / temperature

### Tier 2: differentiators

- Sleep quality and patterns
- Scratching and itching detection (huge for allergy-prone dogs)
- Eating pattern detection (via movement signatures near bowl)
- Heart rate and respiratory rate trends
- Anomaly detection on motion data

### Tier 3: wild ideas

- Cough detection via audio
- Bark classification (stressed / alert / excited)
- Proximity-based social logging (near other tagged pets)

## Why NOT to do hardware first

Hardware is brutal in ways software founders don't fully appreciate:

1. **Capital intensive** — even a lean hardware MVP is $100k+ in tooling, certification, and first production
2. **Certification** — FCC (radio), battery safety, possibly FDA for health positioning. Weeks to months per cert.
3. **Supply chain risk** — chip shortages, component EOL notices, quality drift
4. **Scale is hard** — first 1000 units are fine; first 10,000 have yield issues
5. **Returns and warranty** — 5-10% of hardware units have problems
6. **Long iteration cycles** — software ships same day; hardware revisions take months
7. **Battery life expectations** — customers want multi-day battery, sensors kill batteries, compromises frustrate users
8. **Fit across breeds** — Chihuahua to Great Dane is a design problem
9. **Chewing, water, wear** — pets are rough on hardware
10. **Incumbents exist** — Fi and Tractive have years of head start and venture funding

None of these are showstoppers. All of them together are why most hardware startups fail in year 1.

## The middle path: integrate with existing wearables

Rather than building hardware, integrate with what's already out there. From [[06-competition]]:

### Easiest integration targets

- **FitBark** — has historically had a public API, the most developer-friendly player
- **Apple iCloud Shared Photo Streams / Google Photos** — pull pet photos via face detection, no hardware partnership needed
- **Tractive** — worth checking current API status (may require partnership conversation)

### Hard but high-value

- **Fi** — ecosystem locked, would require formal BD relationship
- **Tractive** — same
- **Pet insurance company APIs** (Lemonade, Trupanion, Embrace, Figo) — for claims and records
- **Online pharmacy histories** (Chewy, Petco prescription histories)

### Holy grail (years out)

- **Vet practice management software** — Covetrus, IDEXX, Cornerstone, AVImark — direct sync with vet clinic records. Requires years of BD work with conservative enterprise vendors.

## The phased hardware roadmap

If hardware is ever in the cards, the right sequence is:

1. **Year 1:** software-only product; reach ~2,000 paying users; validate the thesis
2. **Year 1.5-2:** integrate with existing trackers (FitBark first); validate that users value the data in your beautiful UX
3. **Year 2:** begin hardware product planning with a contract manufacturer; pre-order campaign to existing users as the distribution channel
4. **Year 3:** ship hardware if pre-orders are strong

## A lean "almost hardware" option

If you want physical brand presence without the hardware risk, a passive QR-code pet tag:

- Cheap, durable, customizable metal or silicone tag
- Attaches to the collar
- QR code links to the pet's emergency page (medical info, vet contact, owner contact)
- Zero electronics, zero certification, zero power
- Production runs in hundreds rather than thousands
- Sellable as a physical upsell ($10-20) for a few weeks of design work

This gives the product a tangible, giftable artifact without committing to an actual electronics product. Good "year 1" experiment if you want to dip a toe in hardware without the full commitment.

## Related

- [[06-competition]]
- [[13-roadmap]]
