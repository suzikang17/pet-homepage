# Tech Stack

## Proposed stack

| Layer | Tool | Why |
|---|---|---|
| Frontend framework | Next.js 16 App Router | Same as Greece trip, leverages existing muscle memory, great DX |
| Language | TypeScript | Standard |
| Styling | Tailwind CSS | Fast iteration, matches the Greece trip aesthetic |
| Database | Supabase (Postgres) | Auth + DB + storage in one, generous free tier |
| Auth | Supabase magic links | No passwords, low friction |
| File storage | Supabase storage or Cloudflare R2 | Photos and document attachments |
| Email inbound | Cloudflare Email Workers | Free, already on Cloudflare for DNS, parses via postal-mime |
| Email outbound | Resend (Phase 2+) | Not needed for MVP — monthly digests deferred |
| SMS | Twilio | Industry standard, programmable SMS with 10DLC support |
| AI | Anthropic Claude API (Sonnet/Haiku) | Document parsing, extraction, vet prep summaries |
| Cron jobs | Vercel Cron | Monthly digests, reminder scheduling |
| Hosting | Vercel | Deploy pipeline we already have working |
| Analytics | Plausible or PostHog | Privacy-friendly, clean dashboards |
| Error tracking | Sentry | Standard |
| Payments | Stripe | Standard, supports subscriptions and one-time |

## Critical architectural decisions

### Email ingestion

- Each pet gets a unique email alias: `sandy+abc123@homepage.pet`
- Cloudflare Email Worker receives the inbound email, parses MIME with `postal-mime`, POSTs parsed payload to `/api/ingest/email`
- The Next.js API route validates a shared secret, looks up the pet by ingest email, calls Claude `generateObject` with the extraction schema, writes to `events` + normalized table
- Claude returns structured JSON: `{event_type, occurred_at, title, notes, fields}`
- Result is stored in the `events` table and rendered on the timeline

### SMS ingestion

- Each pet gets a dedicated Twilio number (shared number + keyword routing possible to reduce cost)
- Inbound webhook (Twilio) receives the SMS
- Handler classifies: quick log, photo (MMS), confirmation reply to a reminder
- Claude parses text content if needed
- Response SMS is sent back with a friendly confirmation

### AI parsing costs

- Claude Haiku for simple classification tasks (cheaper)
- Claude Sonnet for complex extraction and vet prep summaries
- Target: ~$0.05-$0.30/user/month in AI costs
- Cache prompts with prompt caching where applicable

### Namespace and URLs

- **Primary domain:** `homepage.pet` (acquired)
- **Marketing site:** `homepage.pet`
- **Pet pages:** `<petname>.homepage.pet` (subdomain per pet — e.g., `sandy.homepage.pet`, `max.homepage.pet`)
- **Staging / dev:** appgardn routing at `sk.appgardn.com/homepage` or similar

Subdomain-per-pet (vs path-per-pet) is the recommended structure because it gives each pet a clean, ownable URL that reads as "Sandy's homepage" rather than "Homepage's Sandy page." Requires wildcard DNS and a wildcard SSL certificate — both trivial on Vercel / Cloudflare.

### Defensive domains to grab

- `homepage.pet` — primary, **secured**
- Consider also: `pethomepage.com`, `homepage.app`, `homepage.dog`, `homepage.cat` — low-cost defensive registrations to prevent brand confusion later

## Things to defer

- Real-time features (no need for websockets)
- Mobile native apps (mobile-responsive web is enough at MVP)
- Self-hosted infrastructure (Vercel + Supabase covers everything at MVP scale)
- Complex orchestration (use simple cron + queue patterns)
- ML model hosting (Claude API is enough; don't train anything)

## Things to verify before building

- **Inbound email parse services** — confirm current pricing and feature set for Postmark vs Resend vs SendGrid
- **SMS 10DLC compliance** — current registration process and timelines for Twilio in the US
- **Claude API rate limits** — confirm tier limits for projected usage
- **Supabase storage limits** — verify free and paid tier limits for photo storage
- **Vercel function execution limits** — confirm Node runtime execution times for background AI jobs
- **Stripe subscription fees** — verify current percentages and flat fees

Always check current docs before committing — see the Vercel knowledge update: `2026-02-27`.

## Related

- [[03-pet-product-spec]]
- [[08-mvp-scope]]
