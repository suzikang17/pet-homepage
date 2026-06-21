import { authTables } from '@convex-dev/auth/server'
import { defineSchema, defineTable } from 'convex/server'
import { v } from 'convex/values'

// The iOS app is the system of record (Core Data + CloudKit). Convex only backs
// the opt-in read-only desktop mirror + its auth — see ios/PetHomepage/Mirror/.
export default defineSchema({
  ...authTables,

  // Opt-in desktop mirror: the iOS app pushes a full single-pet health-record
  // snapshot (see ios/PetHomepage/Mirror/MirrorSnapshot.swift) for the read-only
  // web dashboard. One row per authenticated user; snapshot is an opaque blob.
  mirrors: defineTable({
    userId: v.id('users'),
    snapshot: v.any(), // MirrorSnapshot JSON (snake_case keys, ISO-8601 dates)
    schemaVersion: v.number(),
    updatedAt: v.number(),
  }).index('by_user', ['userId']),

  // Opaque per-user capability tokens for the iOS mirror push (Approach B). The raw
  // token is shown to the dashboard user once and stored only on the device Keychain;
  // we persist SHA-256(MIRROR_TOKEN_PEPPER + rawToken). The /mirror/push httpAction looks
  // a token up by hash and resolves the userId — it never uses ctx.auth (opaque, not a JWT).
  mirrorTokens: defineTable({
    userId: v.id('users'),
    tokenHash: v.string(), // SHA-256(pepper + rawToken), hex
    label: v.optional(v.string()),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
  })
    .index('by_token_hash', ['tokenHash'])
    .index('by_user', ['userId']),

  // Short-lived device-pairing codes. The dashboard (authed) mints one; the iOS app
  // claims it (by QR scan or by typing it) at /mirror/pair, which exchanges a valid,
  // unexpired, unclaimed code for a freshly minted mirrorToken. Single-use + expiring,
  // so the typable code can be short without weakening the long capability token.
  pairingCodes: defineTable({
    code: v.string(), // unambiguous uppercase alnum, no dashes stored
    userId: v.id('users'),
    createdAt: v.number(),
    expiresAt: v.number(),
    claimedAt: v.optional(v.number()),
  }).index('by_code', ['code']),
})
