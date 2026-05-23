import { query, mutation } from './_generated/server'
import { v } from 'convex/values'
import { paginationOptsValidator } from 'convex/server'

export const create = mutation({
  args: {
    petId:       v.id('pets'),
    occurredAt:  v.string(),
    source:      v.union(v.literal('email'), v.literal('sms'), v.literal('manual')),
    eventType:   v.string(),
    title:       v.optional(v.string()),
    notes:       v.optional(v.string()),
    rawContent:  v.optional(v.string()),
    attachments: v.array(v.object({
      filename: v.string(),
      mimeType: v.string(),
      size:     v.number(),
    })),
    parsedFields: v.any(),
    messageId:    v.optional(v.string()),  // for deduplication
  },
  handler: async (ctx, args) => {
    // Deduplicate: skip if an event with the same messageId already exists for this pet
    if (args.messageId) {
      const existing = await ctx.db
        .query('events')
        .withIndex('by_message_id', (q) => q.eq('messageId', args.messageId))
        .first()
      if (existing) return existing._id
    }

    return ctx.db.insert('events', {
      ...args,
      ingestedAt: Date.now(),
    })
  },
})

export const linkRecord = mutation({
  args: {
    eventId:    v.id('events'),
    recordId:   v.string(),
    recordType: v.string(),
  },
  handler: async (ctx, { eventId, recordId, recordType }) => {
    await ctx.db.patch(eventId, { recordId, recordType })
  },
})

// Paginated query for the timeline — use this in the UI
export const listByPetPaginated = query({
  args: {
    petId:           v.id('pets'),
    paginationOpts:  paginationOptsValidator,
  },
  handler: async (ctx, { petId, paginationOpts }) => {
    return ctx.db
      .query('events')
      .withIndex('by_pet_id', (q) => q.eq('petId', petId))
      .order('desc')
      .paginate(paginationOpts)
  },
})

// Bounded list for server-side use (vet prep, digests) — not for UI pagination
export const listByPet = query({
  args: {
    petId: v.id('pets'),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { petId, limit }) => {
    return ctx.db
      .query('events')
      .withIndex('by_pet_id', (q) => q.eq('petId', petId))
      .order('desc')
      .take(limit ?? 100)
  },
})
