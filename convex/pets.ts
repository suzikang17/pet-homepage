import { query, mutation } from './_generated/server'
import { v } from 'convex/values'

export const getByIngestEmail = query({
  args: { email: v.string() },
  handler: async (ctx, { email }) => {
    return ctx.db
      .query('pets')
      .withIndex('by_ingest_email', (q) => q.eq('ingestEmail', email))
      .unique()
  },
})

export const listByUserId = query({
  args: { userId: v.string() },
  handler: async (ctx, { userId }) => {
    return ctx.db
      .query('pets')
      .withIndex('by_user_id', (q) => q.eq('userId', userId))
      .collect()
  },
})

export const create = mutation({
  args: {
    userId:          v.string(),
    name:            v.string(),
    species:         v.string(),
    breed:           v.optional(v.string()),
    dob:             v.optional(v.string()),
    adoptionDate:    v.optional(v.string()),
    profilePhotoUrl: v.optional(v.string()),
    ingestEmail:     v.string(),
    smsNumber:       v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Enforce uniqueness on ingestEmail — Convex indexes don't do this automatically
    const existing = await ctx.db
      .query('pets')
      .withIndex('by_ingest_email', (q) => q.eq('ingestEmail', args.ingestEmail))
      .unique()
    if (existing) throw new Error(`Ingest email already assigned: ${args.ingestEmail}`)
    return ctx.db.insert('pets', args)
  },
})

export const getById = query({
  args: { petId: v.id('pets') },
  handler: async (ctx, { petId }) => ctx.db.get(petId),
})
