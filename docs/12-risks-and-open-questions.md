# Risks and Open Questions

An honest inventory of what could kill this product, and the things we don't know yet. Review periodically. Update as things resolve.

## Risks (most threatening first)

### 1. Distribution risk (very high)

Consumer products live or die on distribution. Everything in this plan depends on reaching pet owners who don't know they need it. This is the single biggest reason to be humble about the idea.

- **Mitigation:** aggressive channel experimentation from day 1 (see [[09-distribution-and-launch]]); don't over-invest in product until distribution is showing signs of life
- **Signal to watch:** signups per day, virality coefficient (shares per user), time to first 100 signups

### 2. Fi Intelligence already exists (high, new)

Fi shipped "Fi Intelligence" in 2025 / expanded in early 2026. It does AI-powered document analysis for pet records, activity and health monitoring, and export to vets. They beat us to a chunk of the core idea.

- **What still makes us differentiated:** hardware-free, any pet (cats too), beautiful web-first experience, email ingestion, memory/recap, shareable URL
- **Mitigation:** lead with beauty and the emotional hook, not the "AI analyzes your documents" pitch (that's now table stakes). Position against Fi as "for people who don't want a collar."
- **Signal to watch:** Fi's continued feature expansion and marketing positioning

### 3. Free alternatives compress pricing (high)

PetDesk, VitusVet, VetDex, and others offer free pet records management. Pricing ceiling is lower than a blue-ocean market would allow.

- **Mitigation:** free tier is mandatory; paid tier must justify itself through *visibly* better features; annual pricing at $30-40 is the realistic ceiling
- **Signal to watch:** conversion rate from free to paid; willingness to pay in user interviews

### 4. Email forwarding friction (medium-high, unproven)

The entire product thesis depends on users forwarding emails. We don't know if they will.

- **Mitigation:** ship early to 5 users and measure this *first*; if the behavior doesn't form, pivot to a different ingestion model (iMessage forwarding, browser extension, Gmail OAuth auto-scan, integrations)
- **Signal to watch:** emails forwarded per user per week in the first 30 days
- **Prior art consideration:** TripIt has had exactly this model for travel since 2006. Adoption of the "forward your stuff" behavior in TripIt is modest — most of their users rely on the Gmail/Outlook auto-scan integration instead. That's a real data point suggesting manual forwarding has natural friction even in mature products. The Gmail OAuth approach may be a stronger version of this wedge.

### 4b. Pet records category user engagement (high — new research finding, April 2026)

Underneath the "will users forward emails" question is a bigger, more fundamental risk: **pet owners may not engage with records-management products at all, regardless of input mechanism.**

[VetVerifi's own blog post](https://www.vetverifi.com/blog/pet-owners-arent-using-apps-to-share-with-pet-service-providers) explicitly states that in existing pet records apps, *"the 'share my records' feature is rarely used by pet owners, and most people are not using these apps as a way to forward or share records with their groomers, boarding facilities, or daycare providers."*

If pet owners don't care enough to use a one-tap share button that already exists in their current apps, they may not care enough to forward emails to a new one either. This is a yellow-flag data point that the entire records-management consumer product category may have weak demand.

- **Mitigation:** the Homepage bet is that existing apps are ugly and clinical, and a beautiful emotionally-designed product might unlock behaviors that utilitarian apps never can (the Notion/Linear thesis — behaviors unlocked by product quality). This is plausible but unvalidated.
- **Validation priority:** this should be the *first* thing tested with real users. Not just "do they forward emails" but "do they return to the pet's page at all after day 1, and do they share it with anyone?"
- **Signals to watch:**
  - Day 1, Day 7, Day 30 active rates
  - % of users who open the page a second time after signup
  - % of users who share the page URL with anyone (sitter, vet, family)
  - Unprompted qualitative feedback — do they talk about it?
- **Kill criteria:** if after 30 days with 5 real users, the median user has opened the page < 3 times and hasn't shared it with anyone, the thesis needs a hard rethink before more building.

### 5. Retention during dormant periods (medium-high)

Pet care usage is spiky. Users might go weeks without opening the app, then question why they're subscribed.

- **Mitigation:** outbound value delivery (monthly digest emails, SMS reminders, year-in-review) that reach the user even when they don't open the app
- **Signal to watch:** 30/60/90-day active rates; open rates on digest emails; SMS reminder click-through

### 6. AI parsing edge cases (medium)

Vet emails are in hundreds of formats. PDFs are messy. Handwritten notes exist. Claude is good but not perfect.

- **Mitigation:** budget ongoing prompt engineering; add human-correctable UI; fail gracefully with "we couldn't parse this, help us understand what it is"
- **Signal to watch:** parsing accuracy rate; user edit frequency

### 7. Pet longevity and lifetime engagement (medium)

Pets live 10-15 years. Will users stay engaged that long? Probably not continuously. Churn is inevitable during quiet periods.

- **Mitigation:** annual pricing reduces monthly churn anxiety; memories and year-in-review create reasons to stay; acknowledge lifecycle naturally
- **Signal to watch:** year-over-year renewal rates (not knowable until year 2+)

### 8. Founder motivation (medium-high, personal)

Consumer products require 6-18 months of distribution grind after shipping. The product work is fun; the distribution work is uncomfortable. Solo founders frequently lose interest during this period.

- **Mitigation:** be honest with yourself about whether this is the product you want to live with for a year; start small and validate cheaply before committing
- **Signal to watch:** your own enthusiasm at months 3, 6, 9

### 9. Platform risk (low-medium)

If Apple or Google built "Pet Records" as a native feature in iOS Health or Google Home, the product could be eclipsed.

- **Mitigation:** move fast enough to build brand loyalty before this happens; the specific design taste is defensible even if features are copied
- **Signal to watch:** platform announcements, Apple WWDC, Google I/O

### 10. Legal / regulatory (low but real)

Pet medical records aren't HIPAA (that's humans), but storing medical data still has liability implications. Data breach could be damaging.

- **Mitigation:** talk to a lawyer before growing past a few thousand users; implement proper encryption at rest and in transit from day 1; clear terms of service
- **Signal to watch:** state-by-state pet-data regulations; emerging "animal welfare data" laws

### 11. SMS compliance (low but annoying)

US carriers require 10DLC registration for business SMS. Getting registered takes weeks and has ongoing compliance requirements. Failure means deliverability collapses.

- **Mitigation:** start the 10DLC process early; use Twilio which handles most of the compliance
- **Signal to watch:** deliverability rates; carrier filtering changes

### 12. SMS cost scaling (low)

Heavy users could eat margin through high SMS usage.

- **Mitigation:** hard caps on paid tier (e.g., 200 SMS/month); clear messaging about what's included
- **Signal to watch:** SMS cost per paying user

## Open questions (not yet resolved)

### Product questions

- ~~What do we name this?~~ **Resolved:** brand is **Homepage** at `homepage.pet`. Pet pages live at `<petname>.homepage.pet`.
- What's the ideal ratio of "recap/memory" content vs "practical/records" content on the pet page?
- How do we handle multi-user collaboration on a single pet (spouses, family)?
- Should sitters get a special restricted view?
- How do we handle pet loss / memorial mode?
- What's the onboarding "aha moment" — how do we get users to that moment in under 2 minutes?

### Business questions

- Is the real wedge pets, or is there a broader "personal page for a thing you care about" product hiding here? (See [[02-primitives-and-templates]].)
- Should we monetize from day 1 or grow the user base first?
- Is there a vet-first business (B2B) hiding inside this that's bigger than the consumer version?
- Could this be bootstrapped or does it eventually need capital?

### Technical questions

- How long to keep raw email data? (Privacy vs debugging tradeoff)
- How do we handle very large accounts (hundreds of records, thousands of photos)?
- Build on Supabase or self-host the DB? (Supabase for speed, self-host for control)
- What's the right queue / background job architecture for AI processing?

### Distribution questions

- Is there an influencer / micro-celebrity who'd genuinely love this and could kickstart word of mouth?
- Which subreddit resonates first? Which posts drive actual signups?
- Does the product go viral through the shareable URL (sitter, vet, family) or does that never really happen?

## Things to validate cheaply before building more

1. **Will users forward emails?** Ship to 5 people, measure for 2 weeks.
2. **Do users care about the vet prep feature?** Show a mockup, ask directly.
3. **Is the memory/recap emotionally meaningful?** Show a fake year-in-review, measure reaction.
4. **Is $30-40/year acceptable?** Ask directly in user interviews; watch for price objections.

## Related

- [[00-overview]]
- [[06-competition]]
- [[08-mvp-scope]]
- [[13-roadmap]]
