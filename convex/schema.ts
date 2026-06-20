import { defineSchema, defineTable } from 'convex/server'
import { authTables } from '@convex-dev/auth/server'
import { v } from 'convex/values'

export default defineSchema({
  ...authTables,

  // Opt-in desktop mirror: the iOS app pushes a full single-pet health-record
  // snapshot (see ios/PetHomepage/Mirror/MirrorSnapshot.swift) for the read-only
  // web dashboard. One row per authenticated user; snapshot is an opaque blob.
  mirrors: defineTable({
    userId:        v.id('users'),
    snapshot:      v.any(),     // MirrorSnapshot JSON (snake_case keys, ISO-8601 dates)
    schemaVersion: v.number(),
    updatedAt:     v.number(),
  }).index('by_user', ['userId']),

  // Opaque per-user capability tokens for the iOS mirror push (Approach B). The raw
  // token is shown to the dashboard user once and stored only on the device Keychain;
  // we persist SHA-256(MIRROR_TOKEN_PEPPER + rawToken). The /mirror/push httpAction looks
  // a token up by hash and resolves the userId — it never uses ctx.auth (opaque, not a JWT).
  mirrorTokens: defineTable({
    userId:    v.id('users'),
    tokenHash: v.string(),          // SHA-256(pepper + rawToken), hex
    label:     v.optional(v.string()),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
  })
    .index('by_token_hash', ['tokenHash'])
    .index('by_user', ['userId']),

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
    .index('by_source_type_and_source_id', ['sourceType', 'sourceId']),
})
