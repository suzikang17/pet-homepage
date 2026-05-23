# Pet Homepage — Connect the Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Composer to Convex, add "mark done" to reminder cards, scaffold the reminders cron, and clean up the onboarding account step — so the app actually saves data and the daily care loop works end to end.

**Architecture:** All writes go through Convex mutations via `useMutation`. The Composer already has type/text state and a submit handler — it needs mutations injected and `handleSubmit` made async. Reminder acknowledgement needs three new mutations in `convex/medical.ts` (one per record type) plus action buttons in `RemindersPage`. The cron adds four schema indexes and a new `convex/crons.ts` file that upserts `reminders` table entries from medical records on a 6-hour interval. Biome is added as a dev tool with no impact on runtime behavior.

**Tech Stack:** Next.js 16 App Router, Convex 1.37 (mutations/crons), React 19, TypeScript 5.9, Biome 2.x (new)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `biome.json` | Create | Biome lint/format config |
| `package.json` | Modify | Add `lint` and `format` scripts |
| `convex/schema.ts` | Modify | Add 4 indexes (3 date indexes + reminders by_source), fix stale comment |
| `convex/medical.ts` | Modify | Add 3 acknowledge mutations |
| `convex/crons.ts` | Create | Daily cron: upsert reminder records from medical data |
| `components/Composer.tsx` | Modify | Wire note/symptom/med/weight types to Convex; async submit |
| `components/RemindersPage.tsx` | Modify | Add Mark done button + useMutation calls per reminder type |

---

## Task 1: Add Biome

**Files:**
- Create: `biome.json`
- Modify: `package.json`

- [ ] **Step 1: Install Biome**

```bash
npm install --save-dev @biomejs/biome
```

Expected: `@biomejs/biome` appears in `package.json` devDependencies.

- [ ] **Step 2: Create `biome.json`**

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "organizeImports": {
    "enabled": true
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": {
        "noExplicitAny": "warn"
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "semicolons": "asNeeded",
      "trailingCommas": "es5"
    }
  },
  "files": {
    "ignore": [
      "node_modules",
      ".next",
      "convex/_generated",
      "tsconfig.tsbuildinfo"
    ]
  }
}
```

- [ ] **Step 3: Add lint/format scripts to `package.json`**

Add to the `scripts` block (the existing dev/build/start keys stay):

```json
"lint": "biome check .",
"format": "biome format . --write"
```

- [ ] **Step 4: Run lint to confirm it works**

```bash
npx biome check .
```

Expected: Output with warnings (no errors blocking). Exit 0 or 1 with warning messages — not a crash.

- [ ] **Step 5: Commit**

```bash
git add biome.json package.json package-lock.json
git commit -m "chore: add biome linting"
```

---

## Task 2: Add schema indexes + fix stale comment

**Files:**
- Modify: `convex/schema.ts`

The cron (Task 4) needs to query vaccinations/medications/vetVisits by due date across all pets. The `reminders` table needs a `by_source` index for deduplication. The `userId` comment is stale (says "Clerk" but this project uses Convex Auth).

- [ ] **Step 1: Update `convex/schema.ts`**

Replace the full file contents with:

```typescript
import { defineSchema, defineTable } from 'convex/server'
import { authTables } from '@convex-dev/auth/server'
import { v } from 'convex/values'

export default defineSchema({
  ...authTables,
  pets: defineTable({
    userId:          v.string(),              // Convex auth tokenIdentifier
    name:            v.string(),
    species:         v.string(),              // 'dog' | 'cat' | 'other'
    breed:           v.optional(v.string()),
    dob:             v.optional(v.string()),  // ISO date
    adoptionDate:    v.optional(v.string()),
    profilePhotoUrl: v.optional(v.string()),
    ingestEmail:     v.string(),              // sandy+abc123@homepage.pet
    smsNumber:       v.optional(v.string()),
  })
    .index('by_user_id', ['userId'])
    .index('by_ingest_email', ['ingestEmail']),

  events: defineTable({
    petId:        v.id('pets'),
    occurredAt:   v.string(),                 // ISO 8601
    ingestedAt:   v.number(),                 // Date.now()
    source:       v.union(v.literal('email'), v.literal('sms'), v.literal('manual')),
    eventType:    v.string(),
    title:        v.optional(v.string()),
    notes:        v.optional(v.string()),
    rawContent:   v.optional(v.string()),
    attachments:  v.array(v.object({
      filename: v.string(),
      mimeType: v.string(),
      size:     v.number(),
    })),
    parsedFields: v.any(),
    recordId:     v.optional(v.string()),
    recordType:   v.optional(v.string()),
    messageId:    v.optional(v.string()),
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_and_type', ['petId', 'eventType'])
    .index('by_message_id', ['messageId']),

  vetVisits: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    occurredAt:     v.string(),
    clinicName:     v.optional(v.string()),
    vetName:        v.optional(v.string()),
    reason:         v.optional(v.string()),
    diagnosis:      v.optional(v.string()),
    treatmentNotes: v.optional(v.string()),
    weightKg:       v.optional(v.number()),
    nextVisitDate:  v.optional(v.string()),
    isBaseline:     v.boolean(),
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_baseline', ['petId', 'isBaseline'])
    .index('by_next_visit_date', ['nextVisitDate']),

  vaccinations: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    vaccineName:    v.string(),
    administeredAt: v.string(),
    administeredBy: v.optional(v.string()),
    lotNumber:      v.optional(v.string()),
    nextDueAt:      v.optional(v.string()),
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_due', ['petId', 'nextDueAt'])
    .index('by_next_due_at', ['nextDueAt']),

  medications: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    drugName:       v.string(),
    dosage:         v.optional(v.string()),
    frequency:      v.optional(v.string()),
    startedAt:      v.string(),
    endedAt:        v.optional(v.string()),
    refillDueAt:    v.optional(v.string()),
    prescribingVet: v.optional(v.string()),
    notes:          v.optional(v.string()),
  })
    .index('by_pet_id', ['petId'])
    .index('by_refill_due_at', ['refillDueAt']),

  weightLogs: defineTable({
    petId:      v.id('pets'),
    eventId:    v.optional(v.id('events')),
    recordedAt: v.string(),
    weightKg:   v.number(),
    source:     v.optional(v.string()),
  })
    .index('by_pet_id', ['petId']),

  reminders: defineTable({
    petId:          v.id('pets'),
    sourceType:     v.string(),               // 'vaccination' | 'medication' | 'vet_visit'
    sourceId:       v.string(),
    reminderType:   v.string(),               // 'due_soon' | 'overdue' | 'refill'
    dueAt:          v.string(),
    lastSentAt:     v.optional(v.number()),
    nextSendAt:     v.optional(v.number()),
    status:         v.string(),               // 'pending' | 'sent' | 'acknowledged' | 'snoozed'
    acknowledgedAt: v.optional(v.number()),
  })
    .index('by_pet_id_status', ['petId', 'status'])
    .index('by_next_send_at', ['nextSendAt'])
    .index('by_source', ['sourceType', 'sourceId']),
})
```

- [ ] **Step 2: Verify type check passes**

```bash
npx tsc --noEmit
```

Expected: Exit 0, no errors.

- [ ] **Step 3: Commit**

```bash
git add convex/schema.ts
git commit -m "feat: add date indexes for cron queries, fix userId comment"
```

---

## Task 3: Add acknowledge mutations to `convex/medical.ts`

**Files:**
- Modify: `convex/medical.ts`

Three new mutations — one per record type. Acknowledging clears the due date field so the reminder disappears from the derived list in `RemindersPage`. Each also inserts a manual event for the timeline.

- [ ] **Step 1: Append mutations to `convex/medical.ts`**

Add these three exports after the existing `listVetVisits` export:

```typescript
export const acknowledgeVaccinationReminder = mutation({
  args: { vaccinationId: v.id('vaccinations') },
  handler: async (ctx, { vaccinationId }) => {
    const vax = await ctx.db.get(vaccinationId)
    if (!vax) throw new Error('Vaccination not found')
    await ctx.db.patch(vaccinationId, { nextDueAt: undefined })
    await ctx.db.insert('events', {
      petId: vax.petId,
      occurredAt: new Date().toISOString(),
      ingestedAt: Date.now(),
      source: 'manual',
      eventType: 'reminder_acknowledged',
      notes: `${vax.vaccineName} vaccine reminder marked done`,
      attachments: [],
      parsedFields: {},
    })
  },
})

export const acknowledgeMedicationRefill = mutation({
  args: { medicationId: v.id('medications') },
  handler: async (ctx, { medicationId }) => {
    const med = await ctx.db.get(medicationId)
    if (!med) throw new Error('Medication not found')
    await ctx.db.patch(medicationId, { refillDueAt: undefined })
    await ctx.db.insert('events', {
      petId: med.petId,
      occurredAt: new Date().toISOString(),
      ingestedAt: Date.now(),
      source: 'manual',
      eventType: 'reminder_acknowledged',
      notes: `${med.drugName} refill marked done`,
      attachments: [],
      parsedFields: {},
    })
  },
})

export const acknowledgeVetVisitReminder = mutation({
  args: { vetVisitId: v.id('vetVisits') },
  handler: async (ctx, { vetVisitId }) => {
    const visit = await ctx.db.get(vetVisitId)
    if (!visit) throw new Error('Vet visit not found')
    await ctx.db.patch(vetVisitId, { nextVisitDate: undefined })
    await ctx.db.insert('events', {
      petId: visit.petId,
      occurredAt: new Date().toISOString(),
      ingestedAt: Date.now(),
      source: 'manual',
      eventType: 'reminder_acknowledged',
      notes: 'Vet visit reminder marked done',
      attachments: [],
      parsedFields: {},
    })
  },
})
```

- [ ] **Step 2: Type check**

```bash
npx tsc --noEmit
```

Expected: Exit 0.

- [ ] **Step 3: Commit**

```bash
git add convex/medical.ts
git commit -m "feat: add acknowledge mutations for reminder cards"
```

---

## Task 4: Add Mark Done to RemindersPage

**Files:**
- Modify: `components/RemindersPage.tsx`

The `Reminder` interface needs two new fields — `sourceType` and `sourceRecordId` — so the card knows which mutation to call. `ReminderCard` gets an `onDone` prop.

- [ ] **Step 1: Replace `components/RemindersPage.tsx`**

```typescript
'use client'
import { Topbar } from './Topbar'
import { usePetData } from '@/hooks/usePetData'
import { useMutation } from 'convex/react'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'

type ReminderSourceType = 'vaccination' | 'medication' | 'vet_visit'

interface Reminder {
  id: string
  icon: string
  title: string
  subtitle: string
  dueAt: string
  daysAway: number
  urgency: 'over' | 'soon' | 'upcoming'
  sourceType: ReminderSourceType
  sourceRecordId: string
}

function daysFromNow(iso: string): number {
  return Math.ceil((new Date(iso).getTime() - Date.now()) / (24 * 60 * 60 * 1000))
}

function fmt(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function urgency(days: number): 'over' | 'soon' | 'upcoming' {
  if (days < 0)    return 'over'
  if (days <= 30)  return 'soon'
  return 'upcoming'
}

const urgencyStyles = {
  over:     { border: 'var(--red)',    bg: 'var(--red-bg)',    label: 'Overdue',  labelColor: 'var(--red)'    },
  soon:     { border: 'var(--orange)', bg: 'var(--orange-bg)', label: 'Due soon', labelColor: 'var(--orange)' },
  upcoming: { border: 'var(--rule)',   bg: 'var(--paper)',     label: 'Upcoming', labelColor: 'var(--ink-3)'  },
}

function ReminderCard({ r, onDone }: { r: Reminder; onDone: () => void }) {
  const s = urgencyStyles[r.urgency]
  const dayLabel = r.daysAway < 0
    ? `${Math.abs(r.daysAway)} day${Math.abs(r.daysAway) !== 1 ? 's' : ''} overdue`
    : r.daysAway === 0 ? 'Today'
    : `In ${r.daysAway} day${r.daysAway !== 1 ? 's' : ''}`

  return (
    <div style={{
      background: s.bg, border: `1px solid ${s.border}`, borderRadius: 13,
      padding: '16px 18px', display: 'flex', alignItems: 'center', gap: 16, marginBottom: 8,
    }}>
      <div style={{ fontSize: 28, flexShrink: 0 }}>{r.icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 600, fontSize: 15, color: 'var(--ink)', marginBottom: 2 }}>{r.title}</div>
        <div style={{ fontSize: 13, color: 'var(--ink-3)' }}>{r.subtitle}</div>
      </div>
      <div style={{ textAlign: 'right', flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: s.labelColor, textTransform: 'uppercase',
                      letterSpacing: '0.05em' }}>{s.label}</div>
        <div style={{ fontSize: 13, color: 'var(--ink-2)', fontWeight: 500 }}>{dayLabel}</div>
        <div style={{ fontSize: 11, color: 'var(--ink-3)' }}>{fmt(r.dueAt)}</div>
        <button
          type="button"
          onClick={onDone}
          style={{
            marginTop: 4, padding: '4px 12px', fontSize: 12, fontWeight: 600,
            borderRadius: 8, border: '1px solid var(--rule)', background: 'var(--paper)',
            color: 'var(--ink-2)', cursor: 'pointer',
          }}
        >
          Mark done
        </button>
      </div>
    </div>
  )
}

export function RemindersPage() {
  const { pet, vaccinations, medications, vetVisits, loading } = usePetData()
  const ackVax    = useMutation(api.medical.acknowledgeVaccinationReminder)
  const ackMed    = useMutation(api.medical.acknowledgeMedicationRefill)
  const ackVisit  = useMutation(api.medical.acknowledgeVetVisitReminder)

  if (loading) {
    return <div style={{ minHeight: '100dvh', display: 'grid', placeItems: 'center', color: 'var(--ink-3)', fontSize: 14 }}>Loading…</div>
  }
  if (!pet) return null

  const reminders: Reminder[] = []

  vaccinations.forEach(v => {
    if (!v.nextDueAt) return
    const days = daysFromNow(v.nextDueAt)
    if (days > 90) return
    reminders.push({
      id: v._id, icon: '💉', urgency: urgency(days), daysAway: days, dueAt: v.nextDueAt,
      title: `${v.vaccineName} vaccine`,
      subtitle: `Last given ${new Date(v.administeredAt).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}`,
      sourceType: 'vaccination',
      sourceRecordId: v._id,
    })
  })

  medications.filter(m => !m.endedAt && m.refillDueAt).forEach(m => {
    const days = daysFromNow(m.refillDueAt!)
    if (days > 90) return
    reminders.push({
      id: m._id, icon: '💊', urgency: urgency(days), daysAway: days, dueAt: m.refillDueAt!,
      title: `${m.drugName} refill`,
      subtitle: m.dosage || 'Medication refill needed',
      sourceType: 'medication',
      sourceRecordId: m._id,
    })
  })

  vetVisits.filter(v => v.nextVisitDate).forEach(v => {
    const days = daysFromNow(v.nextVisitDate!)
    if (days > 90) return
    reminders.push({
      id: v._id + '-next', icon: '🩺', urgency: urgency(days), daysAway: days, dueAt: v.nextVisitDate!,
      title: 'Vet visit',
      subtitle: v.clinicName || 'Scheduled follow-up',
      sourceType: 'vet_visit',
      sourceRecordId: v._id,
    })
  })

  reminders.sort((a, b) => a.daysAway - b.daysAway)

  const handleDone = (r: Reminder) => {
    if (r.sourceType === 'vaccination') {
      ackVax({ vaccinationId: r.sourceRecordId as Id<'vaccinations'> })
    } else if (r.sourceType === 'medication') {
      ackMed({ medicationId: r.sourceRecordId as Id<'medications'> })
    } else {
      ackVisit({ vetVisitId: r.sourceRecordId as Id<'vetVisits'> })
    }
  }

  const overdue  = reminders.filter(r => r.urgency === 'over')
  const soon     = reminders.filter(r => r.urgency === 'soon')
  const upcoming = reminders.filter(r => r.urgency === 'upcoming')

  return (
    <>
      <Topbar pet={pet} />
      <div className="page">
        <div className="section-h">
          <h2 className="serif">Reminders</h2>
          <div className="sh-aside">{reminders.length} pending</div>
        </div>

        {reminders.length === 0 ? (
          <div style={{
            background: 'var(--paper)', border: '1px solid var(--rule)', borderRadius: 14,
            padding: '48px 24px', textAlign: 'center', color: 'var(--ink-3)',
          }}>
            <div style={{ fontSize: 36, marginBottom: 12 }}>✅</div>
            <div style={{ fontWeight: 600, color: 'var(--ink-2)', fontSize: 16, marginBottom: 6 }}>All caught up.</div>
            <div style={{ fontSize: 14 }}>Nothing due in the next 90 days.</div>
          </div>
        ) : (
          <>
            {overdue.length > 0 && (
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--red)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Overdue — {overdue.length}</div>
                {overdue.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
            {soon.length > 0 && (
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Due soon — {soon.length}</div>
                {soon.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
            {upcoming.length > 0 && (
              <div style={{ marginBottom: 48 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--ink-3)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Upcoming — {upcoming.length}</div>
                {upcoming.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
          </>
        )}
      </div>
    </>
  )
}
```

- [ ] **Step 2: Type check**

```bash
npx tsc --noEmit
```

Expected: Exit 0.

- [ ] **Step 3: Commit**

```bash
git add components/RemindersPage.tsx
git commit -m "feat: add mark done buttons to reminder cards"
```

---

## Task 5: Wire the Composer to Convex

**Files:**
- Modify: `components/Composer.tsx`

`handleSubmit` is currently fake — it shows a toast but writes nothing. This task makes it async and routes each type to the right mutation. Photo type is skipped (needs file upload infrastructure). Weight needs three state fields added for value, unit, and source.

- [ ] **Step 1: Replace `components/Composer.tsx`**

```typescript
"use client"

import { useEffect, useRef, useState } from "react"
import { useMutation } from "convex/react"
import { api } from "@/convex/_generated/api"
import { Toast } from "./Toast"
import type { Id } from "@/convex/_generated/dataModel"

type ComposerType = "note" | "weight" | "symptom" | "med" | "photo"

const placeholders: Record<ComposerType, string> = {
  note:    "What happened today?",
  weight:  "Optional note…",
  symptom: "Started limping a little after the trail…",
  med:     "Gave Apoquel with breakfast.",
  photo:   "Sun-nap on the deck. Caption?",
}

const submitMessages: Record<ComposerType, string> = {
  note:    "Note added to timeline.",
  weight:  "Weight logged — added to chart.",
  symptom: "Symptom noted. We'll surface this for the next vet visit.",
  med:     "Medication logged.",
  photo:   "Photo added to the timeline.",
}

const types: { key: ComposerType; label: string }[] = [
  { key: "note",    label: "📝 Note" },
  { key: "weight",  label: "⚖ Weight" },
  { key: "symptom", label: "🩺 Symptom" },
  { key: "med",     label: "💊 Medication" },
  { key: "photo",   label: "📷 Photo" },
]

const EVENT_TYPES: Partial<Record<ComposerType, string>> = {
  note:    "note",
  symptom: "symptom",
  med:     "medication_given",
}

export function Composer({ petId, petName }: { petId: Id<"pets">; petName: string }) {
  const [collapsed, setCollapsed]       = useState(true)
  const [type, setType]                 = useState<ComposerType>("note")
  const [text, setText]                 = useState("")
  const [weightVal, setWeightVal]       = useState("")
  const [weightUnit, setWeightUnit]     = useState<"lb" | "kg">("lb")
  const [weightSrc, setWeightSrc]       = useState<"bathroom" | "vet" | "other">("bathroom")
  const [submitting, setSubmitting]     = useState(false)
  const [toast, setToast]               = useState<{ message: string; show: boolean }>({ message: "", show: false })

  const textareaRef      = useRef<HTMLTextAreaElement>(null)
  const toastTimerRef    = useRef<ReturnType<typeof setTimeout> | null>(null)
  const collapseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const focusTimerRef    = useRef<ReturnType<typeof setTimeout> | null>(null)

  const logEvent  = useMutation(api.events.create)
  const logWeight = useMutation(api.medical.createWeightLog)

  const expand = () => {
    setCollapsed(false)
    if (focusTimerRef.current) clearTimeout(focusTimerRef.current)
    focusTimerRef.current = setTimeout(() => { textareaRef.current?.focus() }, 200)
  }

  const collapse = () => {
    setCollapsed(true)
    setText("")
    setWeightVal("")
  }

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        if (collapsed) expand()
        else textareaRef.current?.focus()
      }
      if (e.key === "Escape" && !collapsed) collapse()
    }
    window.addEventListener("keydown", handler)
    return () => window.removeEventListener("keydown", handler)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collapsed])

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
      if (collapseTimerRef.current) clearTimeout(collapseTimerRef.current)
      if (focusTimerRef.current) clearTimeout(focusTimerRef.current)
    }
  }, [])

  const showToast = (message: string) => {
    setToast({ message, show: true })
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
    toastTimerRef.current = setTimeout(() => { setToast(t => ({ ...t, show: false })) }, 2200)
  }

  const handleSubmit: React.MouseEventHandler<HTMLButtonElement> = async (e) => {
    e.stopPropagation()
    if (submitting) return
    setSubmitting(true)
    try {
      const now = new Date().toISOString()

      if (type === "weight") {
        const raw = parseFloat(weightVal)
        if (!isNaN(raw) && raw > 0) {
          const weightKg = weightUnit === "lb" ? raw * 0.453592 : raw
          await logWeight({ petId, recordedAt: now, weightKg, source: weightSrc })
        }
      } else if (type === "photo") {
        // Photo upload not yet wired — show toast only
      } else {
        const eventType = EVENT_TYPES[type]!
        if (text.trim()) {
          await logEvent({
            petId,
            occurredAt: now,
            source: "manual",
            eventType,
            notes: text.trim(),
            attachments: [],
            parsedFields: {},
          })
        }
      }

      showToast(submitMessages[type])
      if (collapseTimerRef.current) clearTimeout(collapseTimerRef.current)
      collapseTimerRef.current = setTimeout(() => collapse(), 500)
    } catch {
      showToast("Something went wrong. Try again.")
    } finally {
      setSubmitting(false)
    }
  }

  const handleClose: React.MouseEventHandler<HTMLButtonElement> = (e) => {
    e.stopPropagation()
    collapse()
  }

  const handleWrapperClick = () => { if (collapsed) expand() }

  return (
    <>
      <div className="composer-wrap">
        <div
          className={`composer ${collapsed ? "collapsed" : ""}`}
          onClick={handleWrapperClick}
        >
          <div className="composer-h">
            <div className="ic">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6">
                <path d="M12 5v14M5 12h14" />
              </svg>
            </div>
            <div className="label">Log something for {petName}</div>
            <div className="hint"><kbd>⌘</kbd> <kbd>K</kbd></div>
            <button className="close" type="button" onClick={handleClose} title="Collapse" aria-label="Collapse composer">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
                <path d="M18 6L6 18M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div className="body">
            <div className="types">
              {types.map(t => (
                <button
                  key={t.key}
                  className={type === t.key ? "active" : ""}
                  onClick={e => { e.stopPropagation(); setType(t.key) }}
                  type="button"
                >
                  {t.label}
                </button>
              ))}
            </div>
            <textarea
              ref={textareaRef}
              value={text}
              onChange={e => setText(e.target.value)}
              placeholder={placeholders[type]}
              onClick={e => e.stopPropagation()}
            />
            <div className={`extras ${type === "weight" ? "show" : ""}`}>
              <input
                type="number"
                placeholder="62.4"
                value={weightVal}
                onChange={e => setWeightVal(e.target.value)}
                onClick={e => e.stopPropagation()}
              />
              <select
                value={weightUnit}
                onChange={e => setWeightUnit(e.target.value as "lb" | "kg")}
                onClick={e => e.stopPropagation()}
              >
                <option value="lb">lb</option>
                <option value="kg">kg</option>
              </select>
              <select
                value={weightSrc}
                onChange={e => setWeightSrc(e.target.value as "bathroom" | "vet" | "other")}
                onClick={e => e.stopPropagation()}
              >
                <option value="bathroom">Bathroom scale</option>
                <option value="vet">Vet scale</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div className="composer-foot">
              <div className="composer-tools">
                <button type="button" title="Attach photo" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <path d="M21.44 11.05l-9.19 9.19a6 6 0 1 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" />
                  </svg>
                </button>
                <button type="button" title="Set date" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <rect x="3" y="4" width="18" height="18" rx="2" />
                    <path d="M16 2v4M8 2v4M3 10h18" />
                  </svg>
                </button>
                <button type="button" title="Tag" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
                  </svg>
                </button>
              </div>
              <button
                className="submit"
                type="button"
                onClick={handleSubmit}
                disabled={submitting}
              >
                {submitting ? "Saving…" : "Add to timeline"}
                {!submitting && (
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
                    <path d="M5 12h14M13 5l7 7-7 7" />
                  </svg>
                )}
              </button>
            </div>
          </div>
        </div>
      </div>
      <Toast message={toast.message} show={toast.show} />
    </>
  )
}
```

- [ ] **Step 2: Type check**

```bash
npx tsc --noEmit
```

Expected: Exit 0.

- [ ] **Step 3: Commit**

```bash
git add components/Composer.tsx
git commit -m "feat: wire Composer to Convex — note, symptom, med, weight types now save"
```

---

## Task 6: Add the reminders cron scheduler

**Files:**
- Create: `convex/crons.ts`

The cron runs every 6 hours. It scans vaccinations/medications/vetVisits for items due within 90 days and upserts entries in the `reminders` table. The `by_source` index added in Task 2 makes the deduplication query efficient.

- [ ] **Step 1: Create `convex/crons.ts`**

```typescript
import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'
import { internalMutation } from './_generated/server'
import { v } from 'convex/values'

export const syncReminderRecords = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now    = new Date().toISOString()
    const cutoff = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString()

    // ── Vaccinations ────────────────────────────────────────────────────────────
    const vaxDue = await ctx.db
      .query('vaccinations')
      .withIndex('by_next_due_at', q => q.lte('nextDueAt', cutoff))
      .take(200)

    for (const vax of vaxDue) {
      if (!vax.nextDueAt) continue
      const existing = await ctx.db
        .query('reminders')
        .withIndex('by_source', q =>
          q.eq('sourceType', 'vaccination').eq('sourceId', vax._id)
        )
        .first()
      if (existing) continue
      await ctx.db.insert('reminders', {
        petId:        vax.petId,
        sourceType:   'vaccination',
        sourceId:     vax._id,
        reminderType: vax.nextDueAt < now ? 'overdue' : 'due_soon',
        dueAt:        vax.nextDueAt,
        status:       'pending',
        nextSendAt:   Date.now(),
      })
    }

    // ── Medications ─────────────────────────────────────────────────────────────
    const medsDue = await ctx.db
      .query('medications')
      .withIndex('by_refill_due_at', q => q.lte('refillDueAt', cutoff))
      .take(200)

    for (const med of medsDue) {
      if (!med.refillDueAt || med.endedAt) continue
      const existing = await ctx.db
        .query('reminders')
        .withIndex('by_source', q =>
          q.eq('sourceType', 'medication').eq('sourceId', med._id)
        )
        .first()
      if (existing) continue
      await ctx.db.insert('reminders', {
        petId:        med.petId,
        sourceType:   'medication',
        sourceId:     med._id,
        reminderType: 'refill',
        dueAt:        med.refillDueAt,
        status:       'pending',
        nextSendAt:   Date.now(),
      })
    }

    // ── Vet visits ──────────────────────────────────────────────────────────────
    const visitsDue = await ctx.db
      .query('vetVisits')
      .withIndex('by_next_visit_date', q => q.lte('nextVisitDate', cutoff))
      .take(200)

    for (const visit of visitsDue) {
      if (!visit.nextVisitDate) continue
      const existing = await ctx.db
        .query('reminders')
        .withIndex('by_source', q =>
          q.eq('sourceType', 'vet_visit').eq('sourceId', visit._id)
        )
        .first()
      if (existing) continue
      await ctx.db.insert('reminders', {
        petId:        visit.petId,
        sourceType:   'vet_visit',
        sourceId:     visit._id,
        reminderType: visit.nextVisitDate < now ? 'overdue' : 'due_soon',
        dueAt:        visit.nextVisitDate,
        status:       'pending',
        nextSendAt:   Date.now(),
      })
    }
  },
})

const crons = cronJobs()

crons.interval(
  'sync reminder records',
  { hours: 6 },
  internal.crons.syncReminderRecords,
  {}
)

export default crons
```

- [ ] **Step 2: Type check**

```bash
npx tsc --noEmit
```

Expected: Exit 0.

- [ ] **Step 3: Commit**

```bash
git add convex/crons.ts
git commit -m "feat: add reminders cron — syncs medical records into reminders table every 6h"
```

---

## Task 7: Clean up onboarding account step

**Files:**
- Modify: `components/onboarding/OnboardingFlow.tsx`

The `account` step collects email/password but does nothing with them — middleware already requires auth before `/onboarding` is accessible, so users arrive authenticated via `/sign-up`. The account step is dead UI. Remove it from the STEPS array and its case in the step renderer so the flow ends at `notify → done`.

- [ ] **Step 1: Remove `account` from STEPS array**

In `OnboardingFlow.tsx`, find:
```typescript
const STEPS: StepDef[] = [
  ...
  { id: 'notify',     phase: 'plan',  optional: false },
  { id: 'account',    phase: 'plan',  optional: false },
  { id: 'done',       phase: 'plan',  optional: false },
]
```

Replace with:
```typescript
const STEPS: StepDef[] = [
  { id: 'welcome',    phase: 'intro', optional: false },
  { id: 'name',       phase: 'pet',   optional: false },
  { id: 'species',    phase: 'pet',   optional: false },
  { id: 'breed',      phase: 'pet',   optional: true  },
  { id: 'birthday',   phase: 'pet',   optional: false },
  { id: 'sex',        phase: 'pet',   optional: false },
  { id: 'weight',     phase: 'pet',   optional: false },
  { id: 'photo',      phase: 'pet',   optional: true  },
  { id: 'vet',        phase: 'care',  optional: true  },
  { id: 'meds',       phase: 'care',  optional: true  },
  { id: 'conditions', phase: 'care',  optional: true  },
  { id: 'chip',       phase: 'care',  optional: true  },
  { id: 'vax',        phase: 'care',  optional: true  },
  { id: 'goals',      phase: 'plan',  optional: true  },
  { id: 'notify',     phase: 'plan',  optional: false },
  { id: 'done',       phase: 'plan',  optional: false },
]
```

- [ ] **Step 2: Remove `account` from StepId type**

Find:
```typescript
type StepId =
  | 'welcome' | 'name' | 'species' | 'breed' | 'birthday' | 'sex' | 'weight'
  | 'photo' | 'vet' | 'meds' | 'conditions' | 'chip' | 'vax' | 'goals'
  | 'notify' | 'account' | 'done'
```

Replace with:
```typescript
type StepId =
  | 'welcome' | 'name' | 'species' | 'breed' | 'birthday' | 'sex' | 'weight'
  | 'photo' | 'vet' | 'meds' | 'conditions' | 'chip' | 'vax' | 'goals'
  | 'notify' | 'done'
```

- [ ] **Step 3: Remove `account` case from step renderer and `headlines`**

In the `StepContent` function, delete the `case 'account':` block entirely (the one rendering the Google/Apple/email buttons).

In the `headlines` function, delete the `account:` key from the returned object.

In `OBValues`, remove the `email` and `password` fields:
```typescript
interface OBValues {
  unit: 'kg' | 'lb'
  name?: string
  species?: 'dog' | 'cat' | 'other'
  breed?: string
  birthday?: string
  ageGuess?: string
  sex?: 'f' | 'm'
  fixed?: boolean
  weight?: string
  photo?: boolean
  clinic?: string
  clinicPhone?: string
  vet?: string
  meds?: Med[]
  conditions?: string[]
  notes?: string
  chip?: string
  chipReg?: boolean
  vax?: Record<string, boolean>
  goals?: string[]
  notify?: Record<string, boolean>
}
```

- [ ] **Step 4: Type check**

```bash
npx tsc --noEmit
```

Expected: Exit 0.

- [ ] **Step 5: Commit**

```bash
git add components/onboarding/OnboardingFlow.tsx
git commit -m "fix: remove dead account step from onboarding — auth happens at /sign-up"
```

---

## Self-Review

**Spec coverage:**
- ✅ Biome added (Task 1)
- ✅ Composer → Convex: note, symptom, med, weight wired (Task 5); photo deferred explicitly
- ✅ Reminders mark done: 3 acknowledge mutations + UI buttons (Tasks 3 + 4)
- ✅ Reminders cron: 6-hour interval upserts reminder records from medical data (Task 6)
- ✅ Onboarding account step removed (Task 7)
- ✅ Schema indexes added for cron queries (Task 2)

**Placeholder scan:** No TBDs. All code blocks are complete and runnable.

**Type consistency:** 
- `Id<'vaccinations'>`, `Id<'medications'>`, `Id<'vetVisits'>` used consistently in mutations and RemindersPage cast
- `api.medical.acknowledgeVaccinationReminder` / `acknowledgeMedicationRefill` / `acknowledgeVetVisitReminder` defined in Task 3, consumed in Task 4
- `api.events.create` and `api.medical.createWeightLog` already existed, consumed in Task 5
- `internal.crons.syncReminderRecords` defined and consumed in Task 6
