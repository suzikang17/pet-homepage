# Pet Product Spec

## What the product actually is

A web page for your pet that lives at a URL you can share, populated by forwarding emails and texting a number, with a beautiful timeline, a records archive, and AI-generated insights.

## Core user flows

### Creating a pet

1. User signs up (magic link, no password)
2. Creates a pet: name, species, breed, DOB, adoption date, profile photo
3. Gets a dedicated ingestion email address (`sandi+abc123@pets.app`) and SMS number for that pet
4. Lands on an empty pet page with a friendly "forward your stuff here" prompt

### Forwarding an email

1. User forwards a vet bill / vaccination certificate / insurance document to the pet's email
2. Backend receives the email via inbound parse webhook
3. Claude classifies the content type (vet bill, vaccination, photo, general note) and extracts structured fields
4. The item is filed into the appropriate section of the pet page
5. User sees the new item show up on the timeline and in the relevant records view

### Texting the pet number

1. User texts the pet's SMS number: *"Sandi had diarrhea today, probably the chicken"*
2. Backend receives the inbound SMS via Twilio webhook
3. Claude parses and logs it as a wellness note
4. User gets a brief confirmation text: *"Logged. Hope she feels better 🐾"*

### Preparing for a vet visit

1. User taps "Vet visit prep" on the pet page
2. Backend generates a summary of everything that's changed since the last vet visit marker
3. Summary includes: weight changes, behavioral notes, photos of concerns, medications, questions worth asking
4. User can copy, share, or generate a one-click shareable link for the vet
5. After the appointment, user taps "mark vet visit complete" to set the new baseline

### Receiving a monthly digest

1. On the 1st of each month, cron job fires
2. Backend compiles the previous month's photos, notable moments, and logged events for each active pet
3. Beautiful HTML email is rendered and sent
4. User opens it on their phone, smiles, feels loved

### Receiving a reminder SMS

1. Backend runs a daily reminder scheduler
2. For each pet with upcoming preventatives, vaccinations, or refills, send an SMS
3. SMS includes a contextual message: *"🐾 Time for Sandi's flea med. Reply 'done' when she's had it."*
4. User replies, reply is logged, next reminder scheduled

## Data model (conceptual)

- **User** — id, email, auth info
- **Pet** — id, user_id, name, species, breed, dob, adoption_date, profile_photo, ingest_email, sms_number
- **Event** — id, pet_id, type (photo, vet_bill, vaccination, note, reminder), timestamp, source (email, sms, manual), raw_content, parsed_fields, attachments
- **Record** — normalized vet records (vaccinations with expiry dates, medications with dosages, etc.)
- **Reminder** — id, pet_id, type, next_due_at, last_sent_at, status
- **VetVisit** — id, pet_id, date, summary, marker_for_since

## Hero features (the things that sell the product)

### 1. Vet visit prep (practical retention)

The night before a vet visit, the app generates a summary of everything that's changed since the last visit:

```
Sandi's vet visit tomorrow at 2pm.

Since May:
- Weight: 48 → 51 lbs (+6%)
- 3 skin irritation photos logged (Oct 2, 14, 28)
- Started Apoquel in July, last refill 3 weeks ago (running low)
- Energy level notes mention 'lower than usual' twice this month
- Eating less than usual the past 4 days

Questions worth asking:
- Is the skin irritation related to seasonal allergies?
- Should we adjust the Apoquel schedule?
- Any concerns about the weight trend?
```

One-tap share link that the vet can open before the appointment.

### 2. Recap and memories (emotional retention)

- **Monthly digest email** — "Sandi in October" with photos and moments from the month
- **Year-in-review** — on the pet's birthday or adoption anniversary
- **"A year ago today"** — throwback emails when something funny or sweet happened last year
- **Milestone cards** — auto-generated "Sandi's first beach trip", "First time meeting Grandma's cat"

These compound over time. Year one is nice. Year three is magical.

## Secondary features

- Multi-pet support (free tier: 1 pet; paid tier: unlimited)
- Shareable sitter mode (read-only view with care instructions + emergency info)
- AI anomaly detection from logged data ("weight gain 6%, worth mentioning to vet")
- Expense tracking / "total spent on Sandi this year"
- Emergency QR code (physical sticker for collar, links to medical info)
- Lost pet poster generation
- Integration with existing wearables (FitBark API first, then Fi/Tractive partnerships later)
- Integration with pet photos from iCloud / Google Photos (face detection → auto-ingest)

## Related

- [[04-features]]
- [[07-tech-stack]]
- [[08-mvp-scope]]
