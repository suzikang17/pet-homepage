import { httpRouter } from 'convex/server'
import { auth } from './auth'
import { sha256Hex } from './crypto'
import { internal } from './_generated/api'
import { httpAction } from './_generated/server'

const http = httpRouter()
auth.addHttpRoutes(http)

// Opt-in desktop mirror push from the iOS app. Authenticated by an opaque per-user
// capability token (Approach B) — NOT ctx.auth. The token is minted in the dashboard
// (convex/mirrorTokens.ts), stored hashed, and sent here as `Authorization: Bearer <token>`.
http.route({
  path: '/mirror/push',
  method: 'POST',
  handler: httpAction(async (ctx, request) => {
    const pepper = process.env.MIRROR_TOKEN_PEPPER
    if (!pepper) {
      return new Response(JSON.stringify({ error: 'Server misconfigured' }), {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const authHeader = request.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }
    const rawToken = authHeader.slice('Bearer '.length)
    const tokenHash = await sha256Hex(pepper + rawToken)

    const record = await ctx.runQuery(internal.mirrorTokens.lookupByHash, { tokenHash })
    if (!record) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    let body: unknown
    try {
      body = await request.json()
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (
      typeof body !== 'object' ||
      body === null ||
      typeof (body as { schema_version?: unknown }).schema_version !== 'number' ||
      (body as { snapshot?: unknown }).snapshot === undefined
    ) {
      return new Response(JSON.stringify({ error: 'Missing snapshot or schema_version' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { snapshot, schema_version } = body as { snapshot: unknown; schema_version: number }
    await ctx.runMutation(internal.mirror.upsertForUser, {
      userId: record.userId,
      snapshot,
      schemaVersion: schema_version,
    })

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }),
})

export default http
