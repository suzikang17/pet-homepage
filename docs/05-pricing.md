# Pricing

## Strategy summary

- **Free tier** is now mandatory, not optional, because of competitive pressure from free alternatives
- **Annual subscription** is the hero paid tier (less churny than monthly for this category)
- **Lifetime deal** at launch for validation + buzz, capped at first 500 users
- **Monthly** exists only as a try-it-out on-ramp, de-emphasized in the pricing page

## Why not monthly as the primary tier

Pet care usage is spiky, not continuous:

- Spikes around vet visits, travel, new symptoms, new pets
- Long dormant stretches in between
- Monthly billing during dormant periods creates a churn trigger: *"Wait, I'm paying for something I haven't opened in 3 weeks?"*

Annual pricing decouples from this anxiety — one decision per year, feels more like pet insurance or a wellness plan.

## Why a free tier is now mandatory

The competitive research in [[06-competition]] revealed several **free** alternatives:

- **PetDesk** — free for pet owners (clinics pay)
- **VitusVet** — free for pet owners (clinics pay)
- **VetDex** — free during beta, planning freemium (free for up to 5 pets)
- **PetLog Pro, PetNoter** — free or very cheap

Without a free tier, the first question every prospective user asks is *"why not use PetDesk?"* The free tier is the acquisition mechanism that gets users into the product, and the paid tier has to justify itself through visibly better features — not storage limits.

## Proposed pricing tiers

### Free

- 1 pet
- Basic profile and timeline
- Manual entry + email ingestion (capped at ~20 items/month)
- 6-month history cap
- Shareable public page

### Pro — $30-40/year (or $4/month)

- Unlimited pets
- Unlimited email ingestion with AI parsing
- SMS interaction and reminders (with reasonable monthly caps)
- **AI vet visit prep summaries**
- **Monthly recap digests and year-in-review**
- **Memory features** ("a year ago today", milestone cards)
- Full history retention
- Priority support

### Launch Lifetime — $80 one-time (first 500 users only)

- Everything in Pro, forever
- Early-adopter badge on the pet page
- Limited to first 500 signups for validation and buzz
- Retired after initial launch period

## Pricing analysis

### Why $30-40/year and not higher

- Free competitors compress the ceiling
- Fi/Tractive charge ~$12-19/month but include hardware value we don't
- $30-40 feels like "pet insurance adjacent" — pet owners are comfortable with annual pet-related charges at this level
- Annual ARPU of $30-40 still works economically (see [[08-mvp-scope]] cost analysis)

### Why not higher (e.g. $60-80/year)

- Hard to justify against free alternatives without strong word-of-mouth
- Churn risk: if users don't feel the value in year 2, they don't renew
- Price can always go up after product-market-fit; hard to come down

### Why not lower (e.g. $15/year)

- Cheapens perception of the product
- Compresses unit economics beyond comfort
- The emotional positioning ("we remember your pet's life for you") supports a modest premium

## Unit economics at proposed pricing

Rough per-user monthly costs at steady state:

- SMS (Twilio): $0.30–$1.00
- Claude API: $0.05–$0.30
- Database + hosting: negligible
- Photo storage: negligible
- Total marginal cost: ~$0.80–$1.50/user/month

At $35/year → ~$2.92/month revenue. Gross margin ~50-70%.

Not as healthy as a pure B2B SaaS, but reasonable for consumer with the free tier dragging the blended ARPU down. Heavy users need caps to prevent margin erosion.

## Pricing tests to consider

Once the product is shipped and has users:

- A/B test free tier limits (20 items/month vs 50 vs unlimited)
- A/B test annual price ($30 vs $40 vs $50)
- Test gift subscriptions ("give a pet life page to your friend who just adopted")
- Test per-pet pricing (free 1, $20/yr per additional pet) vs flat pro tier
- Test promotional discounts for referrals

## Related

- [[06-competition]]
- [[08-mvp-scope]]
- [[09-distribution-and-launch]]
