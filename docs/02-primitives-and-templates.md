# Primitives and Templates

This note captures the conceptual framework for the broader platform. Homepage is the first vertical, but the underlying engine (email ingestion + AI parsing + beautiful shareable web pages) could power many different template types.

## The four primitives

Through discussion, four recurring shapes emerged for "a page for a thing":

### 1. Events (bounded + collaborative)

A bounded thing happening with a group of people. Has a beginning and an end.

- Examples: Greece trip, wedding, birthday party, housewarming, baby shower, dinner party, conference attendance, family reunion, memorial
- Shape: `who / when / where / what`, plus accumulating stuff (photos, RSVPs, contributions)
- Ends naturally; archives afterwards

### 2. Profiles (living display for a thing)

An ongoing page describing a specific thing. Mostly for viewing and sharing.

- Examples: pet page, baby milestone page, house / car page, band / team page, kid's school project
- Shape: profile + timeline + photos
- No natural end; grows over time

### 3. Handoffs (reference for temporary custody)

A living reference page that gets shared on-demand when someone else is temporarily in charge of something.

- Examples: pet sitter guide, house sitter guide, babysitter info, airbnb co-host info, "how to run our podcast", substitute teacher info
- Shape: "here's everything you need to know to take over"
- Consulted rather than browsed

### 4. Collections (growing piles of related items)

A living, categorized pile of related items that grows over time. Not bounded, not a single-thing profile.

- Examples: recipe collection, reading list, wishlist, gift ideas for a person, restaurants to try, travel bucket list, "things the kids said"
- Shape: list of items that keeps expanding
- Retrieved / filtered rather than consumed in order

## Pet care as a hybrid

A pet page is interesting because it spans multiple primitives:

- **Profile** — Sandi is a 4-year-old golden retriever, here's her personality
- **Handoff** — care instructions shared with sitters and vets
- **Records archive** — ongoing accumulation of vet bills, vaccinations, insurance
- **Collection** — photos and funny moments over time

That hybrid nature is actually a *strength*: the product delivers more value than any single primitive would. But it's also why the "pet page" is more ambitious than a simple event template.

## Unifying vision (long-term)

A platform where you describe what you want, and the AI builds an appropriate page for you. The user doesn't pick a primitive or a template — they describe their goal and the system picks.

- "Plan my friend's birthday dinner" → event template
- "A page for my dog" → pet care template
- "Our kitchen remodel" → project template
- "Our family recipes" → collection template

Under the hood, all of these share:
- Email / SMS ingestion
- AI parsing and classification
- Beautiful web rendering
- Shareable URLs on a namespace
- Optional hosting via [[#App Garden connection]]

## App Garden connection

The underlying infrastructure for hosting these pages already exists: **appgardn**. It's a Cloudflare Worker router that proxies subdomain + path combinations to upstream apps, with namespace-based organization.

- `sk.appgardn.com/greece-trip` — the Greece trip page
- `sk.appgardn.com/sandi` — Sandi's pet page (hypothetically)

This means hosting and subdomain routing is a solved problem. The Homepage product can use appgardn as its hosting layer while being an independent product experience.

## Why events should come first (strategically)

Even though Homepage may be the first *product*, events is arguably the purest primitive to build the engine around:

- Simplest shape to explain
- Most universal demand
- Easiest marketing angle
- Already validated by the Greece trip page

However, the pet product has a stronger unique wedge (email ingestion of vet docs, recurring engagement, emotional stickiness) so it may be the better *first product to ship*. The platform and the first product are different decisions.

## Current working decision

Build **Homepage** as the first product. Let the engine and templating system emerge from solving a real problem for a real vertical. Keep the generic platform vision in mind but don't generalize prematurely.

## Related

- [[00-overview]]
- [[03-pet-product-spec]]
- [[13-roadmap]]
