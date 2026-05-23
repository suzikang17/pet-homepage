# MVP Scope

## Goal

Build the smallest version of Homepage that lets us validate two critical questions:

1. **Will users actually forward emails to their pet's page?** (Thesis test — if no, the model is wrong)
2. **Does the monthly digest and vet prep deliver enough ongoing value to justify retention?**

Everything else is gravy or can wait.

## In scope

1. **Single pet per account** — no multi-pet support in MVP
2. **Create a pet profile** — name, species, breed, DOB, adoption date, photo
3. **Unique ingestion email address** — `sandy+abc123@homepage.pet`
4. **Inbound email webhook + raw storage** — Postmark or Resend inbound parse
5. **Claude-powered classifier** — classifies inbound content into one of: photo/memory, vet record, medication, general log
6. **Structured extraction** — AI pulls relevant fields from each content type
7. **Pet page rendering** — profile at the top, timeline, photo grid, records sections
8. **Monthly digest email** — cron job runs 1st of each month, compiles last month's content, sends HTML email
9. **Vet visit summary button** — one-tap generates a shareable summary of everything since the last vet visit marker
10. **Magic-link authentication** — Supabase auth, no passwords
11. **Shareable public view** — optional read-only URL that doesn't require login

## Out of scope (for MVP)

- SMS inbound/outbound (add in v0.5)
- Multi-pet support (add in v1)
- Wearable integrations (v1.5+)
- AI Q&A features
- Emergency QR code
- Expense tracking
- Payment/billing (ship free to early users, monetize after validation)
- Mobile apps
- Multi-user collaboration on a pet

## Build order

1. **Create a pet and get a unique email address** — foundation
2. **Email ingestion pipeline** — webhook + raw storage
3. **Claude classifier and extractor** — start with a single prompt that handles all types, iterate
4. **Render the pet page** — timeline, photos, basic records
5. **Vet visit summary generator** — Claude call with all events since last marker
6. **Monthly digest email** — cron + email template + Resend
7. **Magic-link auth** — required for sharing the page without exposing everything
8. **Polish pass** — make it feel Greece-trip-quality
9. **Deploy to 5 friends with pets**

## Success criteria (validation, not revenue)

Ship to 5 pet owners (including yourself with Sandi) and watch for:

- **Forwarding activity:** do they actually forward emails? How many? Which kinds?
- **Monthly digest open rates:** do they open them? Do they smile?
- **Vet prep usage:** do they use the feature before their next vet visit?
- **Sharing:** do they share the page with anyone (sitter, vet, family)?
- **Unprompted feedback:** do they talk about the product without being asked?
- **Retention:** are they still using it 30, 60, 90 days after signup?

If yes to most of these, proceed to v0.5 (SMS + multi-pet + monetization).
If no to most, the thesis needs revisiting before more building.

## Timeline expectation

Working v0 in ~1-2 focused weekends with aggressive AI-assisted development. Longer if polish is prioritized highly (which it should be for this product — ugly is an existential risk given the competitive landscape).

Don't estimate in weeks or months — estimate in "ready to show a friend."

## Questions to answer during build

- What happens when Claude misclassifies an email? (Human correction mechanism? Re-classify button?)
- How do we handle forwarded email threads vs. single messages?
- What's the data retention story for the free tier? (6 months? 1 year? Forever?)
- How do we handle users who forward personal stuff unrelated to the pet? (Detect and warn? Filter?)
- How do we make the onboarding magical (the first "holy shit it works" moment)?

## Related

- [[03-pet-product-spec]]
- [[04-features]]
- [[07-tech-stack]]
- [[12-risks-and-open-questions]]
