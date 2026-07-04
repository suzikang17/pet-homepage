---
lore_type: planning
title: "Roadmap"
status: current
---

# Roadmap

Multi-year phased plan. Designed to be flexible — each phase gates the next based on validation signals.

## Phase 0 — Planning (current)

- [x] Brainstorm and frame the opportunity
- [x] Research the competitive landscape
- [x] Identify primitives and templates
- [x] Write the vision doc and specs
- [x] Pick a real name and claim a domain — **Homepage** at `homepage.pet`
- [ ] Set up the initial project scaffolding

## Phase 1 — MVP v0 (1-2 focused weekends)

Goal: validate the core thesis (people will forward emails, vet prep delivers value)

- [ ] Create pet profile
- [ ] Email ingestion pipeline + Claude parser
- [ ] Pet page rendering (timeline, photos, records)
- [ ] Monthly digest email
- [ ] Vet visit summary generator
- [ ] Magic-link auth
- [ ] Shareable public view
- [ ] Ship to Sandi + 5 friends' pets

See [[08-mvp-scope]] for details.

**Exit criteria:** at least 3 of 5 users are actively forwarding emails after 2 weeks; at least 1 user has used the vet prep feature.

## Phase 2 — v0.5 (months 2-3)

Goal: add the features that drive retention and prove the monetization model

- [ ] SMS inbound and outbound (Twilio + 10DLC registration)
- [ ] SMS reminders for preventatives and vaccinations
- [ ] Multi-pet support
- [ ] Memory features (year-in-review, "a year ago today")
- [ ] Basic billing (Stripe, annual only at first)
- [ ] Landing page with waitlist
- [ ] First paying customers

**Exit criteria:** ~50 paying users, retention at 30 days above 40%, monthly digest open rate above 50%

## Phase 3 — Public launch (months 3-6)

Goal: prove distribution can work

- [ ] Product Hunt launch
- [ ] 3-5 foundational SEO blog posts
- [ ] Subreddit engagement program
- [ ] Small pet influencer outreach
- [ ] First 500 paying users (lifetime deal caps out here)

**Exit criteria:** 500+ paying users, at least one working acquisition channel with positive ROI

## Phase 4 — Consolidation (months 6-12)

Goal: polish, retain, and scale distribution

- [ ] Expand feature set based on user feedback (multi-user collab, shareable sitter mode, emergency QR code, expense tracking)
- [ ] FitBark API integration as first wearable proof of concept
- [ ] Apple Photos / Google Photos integration for passive photo ingestion
- [ ] SEO content cadence established
- [ ] Email drip campaigns for dormant users
- [ ] First local vet clinic referral pilot

**Exit criteria:** 2,000+ paying users, demonstrable retention over 6 months, clear understanding of which channels work

## Phase 5 — Expansion (year 2)

Goal: broaden the product footprint and explore partnerships

- [ ] Vet referral program formalized
- [ ] Specialty hospital partnerships pilot
- [ ] Tractive / Fi API conversations
- [ ] Pet insurance API integrations
- [ ] Possibly: start of second template (events? plant care?)
- [ ] Possibly: QR pet tag as a physical product

**Exit criteria:** ~5,000+ paying users, a working sales motion for vet partnerships, clear signal on whether the platform expansion is real or a distraction

## Phase 6 — Platform or hardware (year 2.5-3)

This is where the fork happens. Two credible paths:

### Path A: platform expansion

- Launch second and third template verticals (events, collections, profiles)
- Unify under a broader "pages for your life" brand
- Leverage appgardn as the hosting layer
- Consider a plurality of products under one namespace

### Path B: pet hardware

- Begin hardware product in earnest
- Partner with a contract manufacturer
- Pre-order campaign to existing user base
- Ship a custom collar or pet tag with proprietary sensors

The choice depends on what the product has taught us and where user demand is strongest. Neither path is committed in advance.

## Cross-cutting themes

These run across all phases:

- **Design quality** — every phase should maintain the Greece-trip bar. Ugly is an existential risk given the competition.
- **Honest validation** — every phase has exit criteria. Don't advance just because time has passed; advance because the signal is there.
- **Distribution discipline** — budget mental and calendar time for distribution work, not just product work.
- **Competitive awareness** — monitor Fi, Tractive, VetDex, and the PetDesk ecosystem. Update strategy as they ship new features.
- **Cost discipline** — especially on SMS and AI usage, to preserve unit economics.

## Related

- [[00-overview]]
- [[04-features]]
- [[08-mvp-scope]]
- [[09-distribution-and-launch]]
- [[10-hardware-vision]]
- [[11-vet-partnerships]]
- [[12-risks-and-open-questions]]
