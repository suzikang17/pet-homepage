import { defineSchema, defineTable } from 'convex/server'
import { authTables } from '@convex-dev/auth/server'
import { v } from 'convex/values'

export default defineSchema({
  ...authTables,
  pets: defineTable({
    userId:          v.string(),              // Clerk user ID (added when auth is wired)
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
    occurredAt:   v.string(),                 // ISO 8601 — extracted from content, not ingestion time
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
    recordId:     v.optional(v.string()),     // ID of the normalized record
    recordType:   v.optional(v.string()),     // 'vetVisits' | 'vaccinations' | 'medications' | 'weightLogs'
    messageId:    v.optional(v.string()),     // email Message-ID header — used for deduplication
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_and_type', ['petId', 'eventType'])
    .index('by_message_id', ['messageId']),

  vetVisits: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    occurredAt:     v.string(),               // ISO date
    clinicName:     v.optional(v.string()),
    vetName:        v.optional(v.string()),
    reason:         v.optional(v.string()),
    diagnosis:      v.optional(v.string()),
    treatmentNotes: v.optional(v.string()),
    weightKg:       v.optional(v.number()),
    nextVisitDate:  v.optional(v.string()),
    isBaseline:     v.boolean(),              // true after user taps "mark visit complete"
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_baseline', ['petId', 'isBaseline']),

  vaccinations: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    vaccineName:    v.string(),
    administeredAt: v.string(),
    administeredBy: v.optional(v.string()),
    lotNumber:      v.optional(v.string()),
    nextDueAt:      v.optional(v.string()),   // source of truth for reminder scheduling
  })
    .index('by_pet_id', ['petId'])
    .index('by_pet_id_due', ['petId', 'nextDueAt']),

  medications: defineTable({
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    drugName:       v.string(),
    dosage:         v.optional(v.string()),
    frequency:      v.optional(v.string()),
    startedAt:      v.string(),
    endedAt:        v.optional(v.string()),   // undefined = currently active
    refillDueAt:    v.optional(v.string()),   // source of truth for refill reminders
    prescribingVet: v.optional(v.string()),
    notes:          v.optional(v.string()),
  })
    .index('by_pet_id', ['petId']),

  weightLogs: defineTable({
    petId:      v.id('pets'),
    eventId:    v.optional(v.id('events')),
    recordedAt: v.string(),
    weightKg:   v.number(),
    source:     v.optional(v.string()),       // 'vet_visit' | 'home' | 'groomer'
  })
    .index('by_pet_id', ['petId']),

  reminders: defineTable({
    petId:          v.id('pets'),
    sourceType:     v.string(),               // 'vaccination' | 'medication' | 'vet_visit' | 'manual'
    sourceId:       v.string(),
    reminderType:   v.string(),               // 'due_soon' | 'overdue' | 'refill'
    dueAt:          v.string(),
    lastSentAt:     v.optional(v.number()),
    nextSendAt:     v.optional(v.number()),
    status:         v.string(),               // 'pending' | 'sent' | 'acknowledged' | 'snoozed'
    acknowledgedAt: v.optional(v.number()),
  })
    .index('by_pet_id_status', ['petId', 'status'])
    .index('by_next_send_at', ['nextSendAt']),
})
