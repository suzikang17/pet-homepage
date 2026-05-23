# Competition

Research date: **April 2026.**

## TL;DR

The space is more crowded than initially assumed. **Fi shipped a direct competitor ("Fi Intelligence") in 2025/2026** that does AI-powered document analysis for pet records. **Whistle was acquired by Tractive in early 2025 and shut down August 31, 2025.** Multiple free pet records apps exist (PetDesk, VitusVet, VetDex). But the gap for a beautiful, hardware-agnostic, web-first pet page with email ingestion and emotional memory features is still real.

## Hardware-tied platforms

### Fi (tryfi / fitracking)

- **Product:** Smart GPS + health collar for dogs
- **Pricing:** ~$150 collar + ~$12-19/mo subscription
- **Key features:** GPS tracking, activity and sleep monitoring, scratching/licking/barking/eating/drinking behavior detection, real-time behavioral and health insights
- **Critically relevant:** Launched **"Fi Intelligence"** — an AI health companion that lets you upload vet receipts, insurance, vaccine records, and training certificates. AI analyzes uploaded documents to add context to health data. Can export health reports to your vet.
- **Gaps we can exploit:**
  - Dog-only (no cats)
  - Hardware-gated — you must buy the $150+ collar to get full value
  - Ecosystem-locked inside Fi's app, not a shareable web page
  - Document upload is manual; no email ingestion
  - Feels engineered and data-heavy, not emotionally designed
  - No memory / recap / year-in-review features
- **Threat level:** **High.** They've moved into the core territory faster than I would have guessed. The moat vs. Fi is consumer love, hardware-free accessibility, email ingestion, and emotional design.

### Tractive

- **Product:** GPS tracker with health monitoring for dogs and cats
- **Pricing:** ~$50 hardware + $5-12/mo subscription
- **Key features:** GPS, activity/sleep, heart rate and respiratory rate (from rest), scratch monitoring, AI-powered weekly health summaries in plain language
- **2026 updates:** Expanded into "comprehensive pet health and safety platform" positioning after absorbing Whistle's customer base
- **Gaps:** Hardware-gated, app-siloed, utilitarian design, no email ingestion, no memories/recap
- **Threat level:** **Medium-high.** Strong hardware + reasonable software, but same structural limits as Fi.

### Whistle (defunct)

- Acquired by Tractive in early 2025
- Services permanently shut down August 31, 2025
- Customer base absorbed into Tractive

### FitBark

- Smaller activity/sleep tracker
- Has historically offered a public API — the most developer-friendly of the wearables
- **Relevance:** Easiest integration target if we want to pull wearable data without a partnership

### PetPace

- Vet-focused, more clinical/enterprise
- Higher price point, typically sold through vet channels
- Less relevant as direct competition

## Vet-distributed records apps (free to pet owners)

### PetDesk

- **The dominant player in "apps vets recommend."**
- Free for pet owners, vet clinics pay
- Syncs with veterinary practice management software (PIMS)
- Handles reminders, appointment booking, vaccine tracking
- **Why it matters:** Already owns the "app your vet told you to download" channel. Extremely hard to dislodge on their strength. Must compete on consumer love, not distribution.

### VitusVet

- Similar positioning: vet-distributed pet records
- Profile per pet, vaccine history, lab results, medication schedules
- Free for owners, clinic-paid
- **Relevance:** Similar competitive shape as PetDesk

### Rapport / PetPro Connect / Allydvm / Vetter

- Backend practice management / client communication tools
- Not direct consumer competitors, but adjacent

## Independent records apps (consumer-facing)

### VetDex

- **Status:** Currently in free beta
- **Features:** Document storage (PDFs, photos, vet visits, lab results, x-rays), QR code sharing with vets (no login required), multi-pet management, offline access, GDPR-compliant encryption
- **Coming soon:** Vaccination reminders
- **What it lacks:** Email ingestion, vet visit prep summaries, photo memory/gallery features, SMS interaction
- **Pricing plan:** Will shift to freemium — free for individual pet owners managing up to 5 animals, premium for unlimited animals + data export + priority support
- **Threat level:** Medium. Similar core functionality but utilitarian, no emotional design, no email/SMS magic. Their QR-code-to-vet feature is genuinely good.

### VetVault

- Positioned as a professional Personal Health Record system with veterinary standards
- AI-powered insights, medical-grade data security
- Likely more premium and clinical in feel

### PetLog Pro

- Described as a "centralized hub for digital pet records"
- Supports photo uploads with timestamps
- Good for documentation passed to vets

### PetNoter

- Secure digital vault for pet medical records
- Microchip and insurance document storage
- Designed for instant access during emergencies

### Others

- Apple Health Records, Google Keep, Notion — generic tools people cobble together
- Various small native apps

## The gap (what nobody does well)

After all this research, the real gap is:

1. **Beautiful, emotionally designed web pages** (not siloed apps) — everyone else feels utilitarian or clinical
2. **Email ingestion as the primary magic** — zero friction document onboarding
3. **AI vet prep summaries** generated from accumulated data — Fi is the only one doing anything like this, and theirs is hardware-gated
4. **Memories, recap, year-in-review** — nobody serves the emotional side of pet ownership
5. **Hardware-agnostic** — no collar required, works for any pet
6. **Shareable URLs** — send the page to your vet, sitter, or grandma without them installing an app
7. **Works for cats too** — Fi is dog-only; Tractive has a cat version but the experience still leans dog

## Competitive positioning statement

> **Homepage** is the beautiful, hardware-free living page for your pet. Forward vet emails and text in updates — we'll remember everything, send you reminders, and make sure every vet visit goes well. Every pet gets their own URL at `<petname>.homepage.pet`. Works for any pet. No collar required. Shareable with anyone who cares about them.

## Wedge and defensibility

See [[14-wedge-and-moat]] for the full honest argument. Quick summary:

- **Wedge:** email ingestion is the specific thing nobody else in the space has made the primary input mechanism. Fi has manual document upload. Tractive has manual data entry. PetDesk doesn't even do records ingestion. This is a 6-18 month head start before a well-funded competitor could copy it.
- **Moat:** distribution. Shareable URLs, SEO compounding, late-game vet referrals. Product moats are rare in consumer; the real defensibility comes from reaching users before anyone else does.
- **Delayed moat:** compound memory data. Year 1 retention matters enormously because every user who stays through year 1 becomes exponentially harder to lose once their pet's memory data has compounded.

## Sources (April 2026)

- Fi Intelligence launch: https://www.businesswire.com/news/home/20260317091481/en/Fi-Launches-Fi-Intelligence-the-First-of-Its-Kind-AI-Health-Companion-for-Dogs
- Fi AI Collar launch 2025: https://www.businesswire.com/news/home/20250529695114/en/Fi-Unleashes-the-Worlds-First-AI-Powered-Smart-Dog-Collar-Built-for-Real-Time-Health-and-Behavior-Detection
- Fi website: https://fitracking.com/
- Fi app: https://fitracking.com/theapp
- Tractive health intelligence: https://tractive.com/blog/en/press/tractive-launches-new-cat-and-dog-trackers-and-features
- Tractive homepage: https://tractive.com/
- Whistle shutdown coverage: https://www.dogster.com/lifestyle/whistle-dog-tracker-reviews
- Top pet health apps roundup: https://pickles.co/post/top-8-pet-health-apps-for-modern-pet-parents
- Vet tech review of pet health trackers: https://guidemypet.com/pet-health-tracking-system-review
- VetDex: https://www.vetdex.app/
- VitusVet: https://vitusvet.com/pet-owners/
- PetDesk: https://petdesk.com/download-app-for-pet-health

## Related

- [[00-overview]]
- [[05-pricing]]
- [[09-distribution-and-launch]]
- [[11-vet-partnerships]]
