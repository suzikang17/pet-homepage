import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'
import { internalMutation } from './_generated/server'

export const syncReminderRecords = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now    = new Date(Date.now()).toISOString()
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
        .withIndex('by_source_type_and_source_id', q =>
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
        .withIndex('by_source_type_and_source_id', q =>
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
        .withIndex('by_source_type_and_source_id', q =>
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
