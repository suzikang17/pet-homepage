import { getAuthUserId } from '@convex-dev/auth/server'
import { v } from 'convex/values'
import { internalMutation, mutation } from './_generated/server'
import { sha256Hex } from './crypto'

// Device pairing: the dashboard (authed) mints a short, single-use, expiring code; the
// iOS app claims it at /mirror/pair (by QR scan or by typing it) and gets a freshly minted
// mirror token back. The short code is safe to type because it expires fast and is one-use —
// the long-lived capability token never leaves the wire as something a human reads.

const PAIR_TTL_MS = 10 * 60 * 1000 // 10 minutes
// Unambiguous alphabet — no I, L, O, 0, 1 — so the code is painless to read off a screen.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
const CODE_LEN = 8

function generateCode(): string {
  const bytes = new Uint8Array(CODE_LEN)
  crypto.getRandomValues(bytes)
  let out = ''
  for (let i = 0; i < CODE_LEN; i++) out += ALPHABET[bytes[i] % ALPHABET.length]
  return out
}

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

/** The .site origin that serves the httpActions (/mirror/pair, /mirror/push). */
function siteOrigin(): string {
  return process.env.CONVEX_SITE_URL ?? ''
}

// Dashboard only (authed): mint a pairing code for the signed-in user.
export const createPairingCode = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx)
    if (userId === null) throw new Error('Not authenticated')

    const code = generateCode()
    const now = Date.now()
    const expiresAt = now + PAIR_TTL_MS
    await ctx.db.insert('pairingCodes', { code, userId, createdAt: now, expiresAt })

    // endpoint lets the app self-configure where to push after pairing.
    return { code, expiresAt, endpoint: siteOrigin() }
  },
})

// Internal: exchange a valid code for a freshly minted mirror token. Called by the
// /mirror/pair httpAction (the app is NOT authenticated here). Returns null for any
// missing / expired / already-claimed code — single-use by design.
export const claim = internalMutation({
  args: { code: v.string() },
  handler: async (ctx, { code }) => {
    const normalized = code.toUpperCase().replace(/[^A-Z0-9]/g, '')
    const matches = await ctx.db
      .query('pairingCodes')
      .withIndex('by_code', (q) => q.eq('code', normalized))
      .collect()
    const pairing = matches.find((p) => !p.claimedAt && p.expiresAt >= Date.now())
    if (!pairing) return null

    const rawToken = generateRawToken()
    const tokenHash = await sha256Hex(pepper() + rawToken)
    await ctx.db.insert('mirrorTokens', {
      userId: pairing.userId,
      tokenHash,
      label: 'Paired device',
      createdAt: Date.now(),
    })
    await ctx.db.patch(pairing._id, { claimedAt: Date.now() })
    return { rawToken }
  },
})
