import { getAuthUserId } from '@convex-dev/auth/server'
import { v } from 'convex/values'
import { mutation, query } from './_generated/server'

// Opt-in desktop mirror. The iOS app pushes a full single-pet health-record
// snapshot for the read-only web dashboard. Auth-gated: each user has exactly
// one mirror row, readable only by that same authenticated user.
//
// The `snapshot` is stored opaquely (v.any()); its shape is the contract defined
// by ios/PetHomepage/Mirror/MirrorSnapshot.swift (snake_case keys, ISO-8601 dates).

export const push = mutation({
  args: {
    snapshot: v.any(),
    schemaVersion: v.number(),
  },
  handler: async (ctx, args) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) throw new Error('Not authenticated')

    const existing = await ctx.db
      .query('mirrors')
      .withIndex('by_user', (q) => q.eq('userId', userId))
      .unique()

    const fields = {
      snapshot: args.snapshot,
      schemaVersion: args.schemaVersion,
      updatedAt: Date.now(),
    }

    if (existing) {
      await ctx.db.patch(existing._id, fields)
      return existing._id
    }
    return await ctx.db.insert('mirrors', { userId, ...fields })
  },
})

export const get = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) return null

    return await ctx.db
      .query('mirrors')
      .withIndex('by_user', (q) => q.eq('userId', userId))
      .unique()
  },
})
