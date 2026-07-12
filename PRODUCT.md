# Product

## Register

product

## Users

Devoted pet owners (often multi-caretaker households) who track a pet's health
in the native iOS app — medications, vaccinations, vet visits, symptoms,
weight, diary. They open the web dashboard on a desktop for two jobs:
1. **Pairing** — mint/scan a token so the phone can mirror its record to the web.
2. **Reviewing** — a calm, readable read-only view of the pet's health record,
   e.g. while on the phone with a vet or preparing for a visit.

The iOS app is the daily driver; the web is the companion reference surface.

## Product Purpose

"A homepage for your pet." One trustworthy place for a pet's whole health
story, replacing records scattered across inboxes, camera rolls and paper
folders. Success: the owner walks into a vet visit prepared, nothing lapses,
and the record reads like a well-kept journal — not an admin database.

## Brand Personality

Warm-editorial, calm, trustworthy. The record is a *journal about a loved
companion*, not a CRUD table. Serif display headings (DM Serif Display) give
it the feel of a well-set pet "homepage"; blue-tinted ink neutrals keep it
clinical-clean without being cold. Three words: **caring, legible, composed**.

## Anti-references

- Generic Tailwind-gray admin panels (gray-500 text on white cards, system-ui
  everywhere) — the record must not feel like an internal tool.
- Pet-brand kitsch: paw-print wallpaper, bouncy mascots, emoji-heavy copy.
- Dashboard-SaaS clichés: hero metrics with gradient accents, glassmorphism.

## Design Principles

1. **The record is the interface.** Content-first layout; chrome recedes.
   Every screen should read top-to-bottom like a well-organized medical
   journal.
2. **One design system, everywhere.** The tokens in `app/globals.css`
   (ink/rule/paper neutrals, blue accent, DM Serif display) are the single
   vocabulary. No inline hex palettes.
3. **Status is semantic, not decorative.** Green/orange/red only ever mean
   ok/due-soon/overdue. Blue means action or selection. Nothing else gets
   saturated color.
4. **Calm confidence over density.** Generous line-height, clear day/section
   grouping, tabular numerals for dates and doses.
5. **Trust states are first-class.** Loading, empty ("no mirror yet"),
   error, and revoked/expired states are designed, not fallbacks.

## Accessibility & Inclusion

WCAG 2.1 AA: 4.5:1 body contrast, visible focus rings on all interactive
elements, real labels on form fields, ≥44px touch targets on mobile,
`prefers-reduced-motion` honored. Household users span ages; 15px+ body type.
