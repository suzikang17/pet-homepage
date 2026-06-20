import { getAuthUserId } from '@convex-dev/auth/server'
import { v } from 'convex/values'
import { sha256Hex } from './crypto'
import { internalQuery, mutation, query } from './_generated/server'

// Per-user capability tokens for the iOS mirror push. All three functions are auth-gated
// (dashboard only). The raw token is returned exactly once from mintMirrorToken and never
// stored server-side — we keep only its salted SHA-256 hash.

/** A high-entropy opaque token (two UUIDs, ~144 bits). */
function generateRawToken(): string {
  return `${crypto.randomUUID()}-${crypto.randomUUID()}`
}

function pepper(): string {
  const value = process.env.MIRROR_TOKEN_PEPPER
  if (!value) {
    throw new Error('MIRROR_TOKEN_PEPPER is not set (npx convex env set MIRROR_TOKEN_PEPPER ...)')
  }
  return value
}

export const mintMirrorToken = mutation({
  args: { label: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) throw new Error('Not authenticated')

    const rawToken = generateRawToken()
    const tokenHash = await sha256Hex(pepper() + rawToken)
    const id = await ctx.db.insert('mirrorTokens', {
      userId,
      tokenHash,
      label: args.label,
      createdAt: Date.now(),
    })
    // rawToken is shown to the user once; it is intentionally never persisted raw.
    return { id, rawToken }
  },
})

export const revokeMirrorToken = mutation({
  args: { tokenId: v.id('mirrorTokens') },
  handler: async (ctx, args) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) throw new Error('Not authenticated')

    const token = await ctx.db.get(args.tokenId)
    if (!token || token.userId !== userId) throw new Error('Not found')
    if (token.revokedAt) return null
    await ctx.db.patch(args.tokenId, { revokedAt: Date.now() })
    return null
  },
})

export const listMirrorTokens = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) return []

    const tokens = await ctx.db
      .query('mirrorTokens')
      .withIndex('by_user', (q) => q.eq('userId', userId))
      .order('desc')
      .take(50)

    // Never leak tokenHash or raw tokens to the client.
    return tokens.map((t) => ({
      _id: t._id,
      label: t.label,
      createdAt: t.createdAt,
      revokedAt: t.revokedAt,
    }))
  },
})

// Internal: resolve a token hash to its owner, only if the token exists and is not revoked.
// Called by the /mirror/push httpAction. Returns null for unknown or revoked tokens.
export const lookupByHash = internalQuery({
  args: { tokenHash: v.string() },
  handler: async (ctx, args) => {
    const token = await ctx.db
      .query('mirrorTokens')
      .withIndex('by_token_hash', (q) => q.eq('tokenHash', args.tokenHash))
      .unique()
    if (!token || token.revokedAt) return null
    return { userId: token.userId }
  },
})
