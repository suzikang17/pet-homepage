import { query, mutation } from './_generated/server'
import { v } from 'convex/values'

export const createVetVisit = mutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('vetVisits', { ...args, isBaseline: false })
  },
})

export const createVaccination = mutation({
  args: {
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    vaccineName:    v.string(),
    administeredAt: v.string(),
    administeredBy: v.optional(v.string()),
    lotNumber:      v.optional(v.string()),
    nextDueAt:      v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('vaccinations', args)
  },
})

export const createMedication = mutation({
  args: {
    petId:          v.id('pets'),
    eventId:        v.optional(v.id('events')),
    drugName:       v.string(),
    dosage:         v.optional(v.string()),
    frequency:      v.optional(v.string()),
    startedAt:      v.string(),
    refillDueAt:    v.optional(v.string()),
    prescribingVet: v.optional(v.string()),
    notes:          v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('medications', args)
  },
})

export const updateMedicationRefill = mutation({
  args: {
    petId:           v.id('pets'),
    drugName:        v.string(),
    refillDate:      v.string(),        // when the refill happened
    nextRefillDueAt: v.optional(v.string()),
  },
  handler: async (ctx, { petId, drugName, refillDate, nextRefillDueAt }) => {
    // Try to find the active medication matching this drug name
    const existing = await ctx.db
      .query('medications')
      .withIndex('by_pet_id', (q) => q.eq('petId', petId))
      .filter((q) =>
        q.and(
          q.eq(q.field('drugName'), drugName),
          q.eq(q.field('endedAt'), undefined),
        )
      )
      .first()

    if (existing) {
      await ctx.db.patch(existing._id, { refillDueAt: nextRefillDueAt })
      return existing._id
    }

    // Drug not in system yet — create a new medication record.
    // startedAt is set to refillDate as the earliest known date.
    return ctx.db.insert('medications', {
      petId,
      drugName,
      startedAt:  refillDate,
      refillDueAt: nextRefillDueAt,
    })
  },
})

export const createWeightLog = mutation({
  args: {
    petId:      v.id('pets'),
    eventId:    v.optional(v.id('events')),
    recordedAt: v.string(),
    weightKg:   v.number(),
    source:     v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('weightLogs', args)
  },
})

export const listWeightLogs = query({
  args: { petId: v.id('pets'), limit: v.optional(v.number()) },
  handler: async (ctx, { petId, limit }) =>
    ctx.db.query('weightLogs').withIndex('by_pet_id', q => q.eq('petId', petId)).order('desc').take(limit ?? 20),
})

export const listMedications = query({
  args: { petId: v.id('pets') },
  handler: async (ctx, { petId }) =>
    ctx.db.query('medications').withIndex('by_pet_id', q => q.eq('petId', petId)).collect(),
})

export const listVaccinations = query({
  args: { petId: v.id('pets') },
  handler: async (ctx, { petId }) =>
    ctx.db.query('vaccinations').withIndex('by_pet_id', q => q.eq('petId', petId)).collect(),
})

export const listVetVisits = query({
  args: { petId: v.id('pets'), limit: v.optional(v.number()) },
  handler: async (ctx, { petId, limit }) =>
    ctx.db.query('vetVisits').withIndex('by_pet_id', q => q.eq('petId', petId)).order('desc').take(limit ?? 20),
})

export const acknowledgeVaccinationReminder = mutation({
  args: { vaccinationId: v.id('vaccinations') },
  handler: async (ctx, { vaccinationId }) => {
    const vax = await ctx.db.get(vaccinationId)
    if (!vax) throw new Error('Vaccination not found')
    const { nextDueAt: _removed, _id, _creationTime, ...rest } = vax
    await ctx.db.replace(vaccinationId, rest)
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
    const { refillDueAt: _removed, _id, _creationTime, ...rest } = med
    await ctx.db.replace(medicationId, rest)
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
    const { nextVisitDate: _removed, _id, _creationTime, ...rest } = visit
    await ctx.db.replace(vetVisitId, rest)
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
