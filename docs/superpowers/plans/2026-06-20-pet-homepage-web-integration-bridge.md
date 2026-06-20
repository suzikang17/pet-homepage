# pet-homepage — Web Integration Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the iOS app to the real backends so two flows work end-to-end (modulo live secrets/devices):

1. **Opt-in desktop mirror.** The iOS app pushes its `MirrorSnapshot` to Convex *as a specific user* via a Convex **httpAction** authenticated by an **opaque per-user capability token**. The existing read-only `/dashboard` (`components/MirrorDashboard.tsx` → `api.mirror.get`) renders that user's mirror. The app does **NOT** use Convex web auth — it carries a bearer token minted by the signed-in user from the dashboard.
2. **Record upload.** The iOS `ExtractionService` POSTs to `/api/extract` with the `x-extract-secret` header (the route is already built and expects JSON `{fileName, mimeType, content, note?, date?}`).

**Approach (research-backed):** Approach **B** from the research — an opaque capability token minted from the web dashboard (auth-gated mutation), hashed with `SHA-256(MIRROR_TOKEN_PEPPER + rawToken)` and stored in a `mirrorTokens` table indexed by hash; the iOS app stores the raw token and sends it as `Authorization: Bearer <token>` to a Convex `httpAction` at `/mirror/push` on the `.convex.site` host. The httpAction recomputes the hash, looks up the token via an `internalQuery`, resolves `userId`, and upserts that user's row in the existing `mirrors` table via an `internalMutation`. **No JWT, no OIDC, no Convex Swift SDK, no `@convex-dev/auth` on mobile.** `ctx.auth.getUserIdentity()` is deliberately NOT used inside the httpAction (it only validates JWTs from configured providers, not opaque tokens) — we do our own table lookup.

**Why not the alternatives:** The Convex Swift SDK + Auth0/Clerk OIDC (Research 1) is overkill for a one-way fire-and-forget write and would require bridging Apple identity into a Convex-recognized JWT. `@convex-dev/auth` in the app (Research 2, Approach A) is beta on React Native and irrelevant to a native Swift client. A self-minted custom JWT (Approach C) needs key management + JWKS hosting. Approach B is the smallest correct surface and is fully revocable.

**Tech Stack:** Convex (`convex/` — default V8 runtime; httpActions in `convex/http.ts`; Web Crypto `crypto.subtle` for SHA-256), Next.js (non-standard fork — read `AGENTS.md`; client components with `'use client'`, `useQuery`/`useMutation` from `convex/react`), Swift 5.9+/SwiftUI/XCTest (iOS 17+, Xcode 15+, xcodegen).

## Global Constraints

- Repo `/Users/suki/dev/pet-homepage`, branch **main**. Working tree is **clean** (the user's other web WIP is stashed — do **NOT** `git stash pop`, do not touch the stash). Branch first if the executor's protocol requires it, but commit each task as written.
- **Three stacks, three verifications:**
  - **Convex:** READ `convex/_generated/ai/guidelines.md` FIRST. Verify with BOTH `(cd /Users/suki/dev/pet-homepage && npx convex codegen)` (validates + deploys to the dev deployment) AND `(cd /Users/suki/dev/pet-homepage && npx tsc --noEmit)`. httpActions register in `convex/http.ts`. Use `getAuthUserId(ctx)` for auth-gated query/mutation. The `mirrors` table + `convex/mirror.ts` already exist — reuse them.
  - **Next.js:** READ `AGENTS.md` FIRST (this fork has breaking changes vs. training data). Verify with `(cd /Users/suki/dev/pet-homepage && npx tsc --noEmit)` and `npx biome check`. Client components start with `'use client'`; provider is `ConvexAuthNextjsProvider`; routes are auth-gated by `middleware.ts` (only `/sign-in`, `/sign-up` public). Run `npx biome check --write` on new/edited TS/TSX before committing.
  - **iOS:** Build/test with `xcodebuild -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'`. `name=iPhone 16` alone is ambiguous — always pin `OS=18.2`. Run `(cd /Users/suki/dev/pet-homepage/ios && xcodegen generate)` after adding any new file. REUSE the Phase 5 `MirrorService`/`FakeMirrorService`, `MirrorSettings`, `MirrorCoordinator` and the Phase 3 `ExtractionService`. Tests use fakes / `URLProtocol` stubs — **NO real network/CloudKit/Convex**.
- **Staging discipline:** `git add` ONLY the specific new/modified files each task touches. NEVER stage `docs/devdash`, `.serena`, `docs/.lore`, `docs/devlog`. Staging this plan file under `docs/superpowers/plans/` is fine.
- **No real secrets.** `EXTRACT_SECRET`, `MIRROR_TOKEN_PEPPER`, and mirror tokens are config. Document them in `.env.local.example` (gitignored in this repo, but keep it accurate). Convex env vars (`MIRROR_TOKEN_PEPPER`) are set with `npx convex env set` — note this in the plan, do not commit a real value.
- **LIVE end-to-end** (real iOS device + running Convex + real login + a real `ANTHROPIC_API_KEY`) is OUT OF SCOPE. Contract-test with fakes, typecheck, and `convex codegen`. Steps that need live verification are flagged **[LIVE]**.
- If a step fails on a trivial environment detail, adapt minimally to achieve its intent and record the deviation.

---

## File Structure

```
convex/
  schema.ts                         # Task 1 — add mirrorTokens table
  mirrorTokens.ts                   # Task 1 (mint/revoke/list, auth-gated) + Task 2 (internal lookup)
  mirror.ts                         # Task 2 — add internal upsertForUser mutation (existing file)
  http.ts                           # Task 3 — add POST /mirror/push httpAction (existing file)
  crypto.ts                         # Task 1 — shared sha256Hex helper (Web Crypto)
components/
  MirrorTokensManager.tsx           # Task 4 — dashboard token UI (mint/list/revoke)
app/dashboard/page.tsx              # Task 4 — mount MirrorTokensManager above MirrorDashboard
ios/PetHomepage/
  Mirror/
    MirrorService.swift             # Task 5 — Bearer token on push
    MirrorSettings.swift            # Task 6 — endpoint + token in settings
  Extraction/
    ExtractionService.swift         # Task 7 — JSON body + x-extract-secret header
ios/PetHomepageTests/
  MirrorServiceTests.swift          # Task 5 — assert Authorization header
  ExtractionServiceTests.swift      # Task 7 — assert JSON body + secret header
.env.local.example                  # Task 8 — MIRROR_TOKEN_PEPPER + notes
```

---

### Task 1: Convex `mirrorTokens` table + auth-gated mint / revoke / list

**Files:**
- Edit: `convex/schema.ts`
- Create: `convex/crypto.ts`
- Create: `convex/mirrorTokens.ts`

**Interfaces:**
- Schema: `mirrorTokens` table `{ userId: v.id('users'), tokenHash: v.string(), label: v.optional(v.string()), createdAt: v.number(), revokedAt: v.optional(v.number()) }` with index `by_token_hash` on `['tokenHash']` and `by_user` on `['userId']`.
- `convex/crypto.ts`: `export async function sha256Hex(input: string): Promise<string>` using Web Crypto (`crypto.subtle.digest`) — available in the default Convex V8 runtime, so **no `"use node"`**.
- `convex/mirrorTokens.ts` public, auth-gated: `mintMirrorToken({ label? }) → { id, rawToken }`, `revokeMirrorToken({ tokenId })`, `listMirrorTokens() → Array<{ _id, label?, createdAt, revokedAt? }>` (never returns hashes/raw tokens).

- [ ] **Step 1: Add the `mirrorTokens` table to the schema**

Insert this table into `convex/schema.ts` inside `defineSchema({ ... })`, immediately after the `mirrors` table block:

```typescript
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
```

- [ ] **Step 2: Add the shared hash helper**

```typescript
// convex/crypto.ts
// SHA-256 hashing for opaque mirror tokens. Web Crypto (crypto.subtle) is available in
// Convex's default V8 runtime — do NOT add "use node" (this file is imported by both an
// httpAction and a mutation that must stay in the default runtime).

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}
```

- [ ] **Step 3: Write the mint / revoke / list functions (auth-gated)**

```typescript
// convex/mirrorTokens.ts
import { getAuthUserId } from '@convex-dev/auth/server'
import { v } from 'convex/values'
import { sha256Hex } from './crypto'
import { mutation, query } from './_generated/server'

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
```

- [ ] **Step 4: Verify Convex codegen + typecheck**

Run: `cd /Users/suki/dev/pet-homepage && npx convex codegen && npx tsc --noEmit`
Expected: codegen succeeds (regenerates `_generated/api.d.ts` with `api.mirrorTokens.*`), `tsc` reports no errors. If codegen complains that `MIRROR_TOKEN_PEPPER` is unset, that is fine at codegen time — the env var is only read at call time; do **not** hardcode it.

- [ ] **Step 5: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add convex/schema.ts convex/crypto.ts convex/mirrorTokens.ts convex/_generated && \
git commit -m "feat(convex): add mirrorTokens table + auth-gated mint/revoke/list"
```

---

### Task 2: Internal token lookup + per-user mirror upsert

**Files:**
- Edit: `convex/mirrorTokens.ts`
- Edit: `convex/mirror.ts`

**Interfaces:**
- `convex/mirrorTokens.ts`: `internalQuery lookupByHash({ tokenHash }) → { userId } | null` — returns the owning userId only for a non-revoked token.
- `convex/mirror.ts`: `internalMutation upsertForUser({ userId, snapshot, schemaVersion })` — the same upsert logic as the existing public `push` mutation, but takes `userId` as an arg (callable from the httpAction, which has no auth identity). The existing public `push` and `get` stay unchanged.

> **Why internal:** The httpAction authenticates via the opaque token, not `ctx.auth`. It must therefore call functions that accept a server-derived `userId`. Per guidelines, `userId` is only accepted here because authorization already happened (token lookup) — these are `internal*` functions, not public API.

- [ ] **Step 1: Add the internal lookup to `convex/mirrorTokens.ts`**

Add these imports/exports to `convex/mirrorTokens.ts` (extend the existing import line and append the function):

```typescript
import { internalQuery } from './_generated/server'
```

```typescript
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
```

- [ ] **Step 2: Add the internal per-user upsert to `convex/mirror.ts`**

Extend the imports and append the internal mutation. The new import line replaces the existing one:

```typescript
import { internalMutation, mutation, query } from './_generated/server'
```

```typescript
// Internal: upsert a user's mirror given a server-derived userId. Used by the
// /mirror/push httpAction, which authenticates via an opaque token (not ctx.auth), so it
// cannot use the public `push` (which derives the user from the session). Same write shape.
export const upsertForUser = internalMutation({
  args: {
    userId: v.id('users'),
    snapshot: v.any(),
    schemaVersion: v.number(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query('mirrors')
      .withIndex('by_user', (q) => q.eq('userId', args.userId))
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
    return await ctx.db.insert('mirrors', { userId: args.userId, ...fields })
  },
})
```

- [ ] **Step 3: Verify Convex codegen + typecheck**

Run: `cd /Users/suki/dev/pet-homepage && npx convex codegen && npx tsc --noEmit`
Expected: success; `_generated/api.d.ts` now exposes `internal.mirrorTokens.lookupByHash` and `internal.mirror.upsertForUser`. No `tsc` errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add convex/mirrorTokens.ts convex/mirror.ts convex/_generated && \
git commit -m "feat(convex): add internal token lookup + per-user mirror upsert"
```

---

### Task 3: `/mirror/push` httpAction (token-authenticated)

**Files:**
- Edit: `convex/http.ts`

**Interfaces:**
- `POST /mirror/push` on the `.convex.site` host. Request: `Authorization: Bearer <rawToken>`, `Content-Type: application/json`, body `{ snapshot: <MirrorSnapshot JSON>, schema_version: number }`. Responses: `200 {"ok":true}`, `401` (missing/invalid/revoked token), `400` (bad JSON / missing fields), `503` (pepper unset).

> **Contract note:** the iOS `MirrorSnapshot.encoder` emits top-level snake_case keys including `schema_version`. The httpAction reads `body.schema_version` and forwards the whole `snapshot` object opaquely to `upsertForUser` (the `mirrors.snapshot` column is `v.any()`, and `MirrorDashboard.tsx` reads snake_case keys). Do **not** rename keys.

- [ ] **Step 1: Add the httpAction route to `convex/http.ts`**

Replace the entire contents of `convex/http.ts` with:

```typescript
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
```

- [ ] **Step 2: Verify Convex codegen + typecheck**

Run: `cd /Users/suki/dev/pet-homepage && npx convex codegen && npx tsc --noEmit`
Expected: success — the dev deployment now serves `POST <NEXT_PUBLIC_CONVEX_SITE_URL>/mirror/push`. No `tsc` errors.

- [ ] **Step 3: Set the pepper on the dev deployment (config, not a commit) [LIVE]**

Run: `cd /Users/suki/dev/pet-homepage && npx convex env set MIRROR_TOKEN_PEPPER "$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"`
This sets a real pepper on the dev deployment only. It is **not** committed. Re-run codegen is not required. (If this fails because there is no deployment configured in this environment, record the deviation — the httpAction code is still correct and verified by typecheck.)

- [ ] **Step 4: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add convex/http.ts convex/_generated && \
git commit -m "feat(convex): add token-authenticated /mirror/push httpAction"
```

---

### Task 4: Dashboard token-management UI

**Files:**
- Create: `components/MirrorTokensManager.tsx`
- Edit: `app/dashboard/page.tsx`

**Interfaces:**
- `MirrorTokensManager` (client component): lists the user's tokens via `useQuery(api.mirrorTokens.listMirrorTokens)`, mints via `useMutation(api.mirrorTokens.mintMirrorToken)` (shows the raw token once in a copyable box with a one-time warning), and revokes via `useMutation(api.mirrorTokens.revokeMirrorToken)`. Mounted above `MirrorDashboard` on `/dashboard` (auth-gated by `middleware.ts`).

> **Next.js fork note:** Read `AGENTS.md` first. This is a client component (`'use client'`) using `useQuery`/`useMutation` exactly like `components/MirrorDashboard.tsx`. Match that file's inline-style approach (no new CSS deps).

- [ ] **Step 1: Create the token manager component**

```tsx
// components/MirrorTokensManager.tsx
'use client'
import { useState } from 'react'
import { useMutation, useQuery } from 'convex/react'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'

// Dashboard UI for the opt-in iOS mirror. The signed-in user mints an opaque capability
// token (shown exactly once), pastes it into the iOS app's Settings, and can revoke it
// here. The raw token never round-trips back from the server after minting.

function fmt(ms?: number): string {
  if (!ms) return '—'
  return new Date(ms).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

const box: React.CSSProperties = {
  background: '#ffffff',
  border: '1px solid #e5e7eb',
  borderRadius: 12,
  padding: '14px 16px',
  marginBottom: 10,
  fontSize: 14,
  color: '#111827',
}

export function MirrorTokensManager() {
  const tokens = useQuery(api.mirrorTokens.listMirrorTokens)
  const mint = useMutation(api.mirrorTokens.mintMirrorToken)
  const revoke = useMutation(api.mirrorTokens.revokeMirrorToken)

  const [label, setLabel] = useState('')
  const [freshToken, setFreshToken] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function handleMint() {
    setBusy(true)
    try {
      const { rawToken } = await mint({ label: label.trim() || undefined })
      setFreshToken(rawToken)
      setLabel('')
    } finally {
      setBusy(false)
    }
  }

  return (
    <section style={{ maxWidth: 720, margin: '0 auto', padding: '0 20px 24px' }}>
      <h2
        style={{
          fontSize: 13,
          fontWeight: 700,
          textTransform: 'uppercase',
          letterSpacing: '0.05em',
          color: '#6b7280',
          margin: '0 0 10px',
        }}
      >
        Mobile mirror tokens
      </h2>

      <div style={box}>
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            placeholder="Device label (e.g. iPhone 15)"
            style={{
              flex: 1,
              padding: '8px 10px',
              border: '1px solid #d1d5db',
              borderRadius: 8,
              fontSize: 14,
            }}
          />
          <button
            type="button"
            onClick={handleMint}
            disabled={busy}
            style={{
              padding: '8px 14px',
              border: 'none',
              borderRadius: 8,
              background: '#111827',
              color: '#ffffff',
              fontSize: 14,
              fontWeight: 600,
              cursor: busy ? 'default' : 'pointer',
              opacity: busy ? 0.6 : 1,
            }}
          >
            {busy ? 'Minting…' : 'Mint token'}
          </button>
        </div>

        {freshToken && (
          <div
            style={{
              marginTop: 12,
              padding: '10px 12px',
              background: '#fef9c3',
              border: '1px solid #fde047',
              borderRadius: 8,
            }}
          >
            <p style={{ margin: '0 0 6px', fontSize: 12, color: '#854d0e', fontWeight: 600 }}>
              Copy this token now — it will not be shown again. Paste it into the app’s Settings.
            </p>
            <code
              style={{
                display: 'block',
                wordBreak: 'break-all',
                fontSize: 13,
                color: '#111827',
                background: '#ffffff',
                padding: '8px 10px',
                borderRadius: 6,
                border: '1px solid #e5e7eb',
              }}
            >
              {freshToken}
            </code>
          </div>
        )}
      </div>

      {tokens === undefined ? (
        <p style={{ color: '#6b7280', fontSize: 13 }}>Loading…</p>
      ) : tokens.length === 0 ? (
        <div style={{ ...box, color: '#9ca3af', textAlign: 'center' }}>No tokens yet</div>
      ) : (
        tokens.map((t) => (
          <div key={t._id} style={box}>
            <strong>{t.label || 'Unlabeled'}</strong>
            <span style={{ color: '#6b7280', fontSize: 12, marginLeft: 8 }}>
              created {fmt(t.createdAt)}
              {t.revokedAt ? ` · revoked ${fmt(t.revokedAt)}` : ''}
            </span>
            {!t.revokedAt && (
              <button
                type="button"
                onClick={() => revoke({ tokenId: t._id as Id<'mirrorTokens'> })}
                style={{
                  float: 'right',
                  padding: '4px 10px',
                  border: '1px solid #fca5a5',
                  borderRadius: 8,
                  background: '#ffffff',
                  color: '#b91c1c',
                  fontSize: 12,
                  fontWeight: 600,
                  cursor: 'pointer',
                }}
              >
                Revoke
              </button>
            )}
          </div>
        ))
      )}
    </section>
  )
}
```

- [ ] **Step 2: Mount it on the dashboard above the read-only mirror**

Replace the contents of `app/dashboard/page.tsx` with:

```tsx
import { MirrorDashboard } from '@/components/MirrorDashboard'
import { MirrorTokensManager } from '@/components/MirrorTokensManager'

export const metadata = { title: 'Dashboard' }

export default function Dashboard() {
  return (
    <>
      <MirrorTokensManager />
      <MirrorDashboard />
    </>
  )
}
```

- [ ] **Step 3: Format, then verify Next typecheck + biome**

Run: `cd /Users/suki/dev/pet-homepage && npx biome check --write components/MirrorTokensManager.tsx app/dashboard/page.tsx && npx tsc --noEmit && npx biome check components/MirrorTokensManager.tsx app/dashboard/page.tsx`
Expected: biome clean (auto-fixed), `tsc` no errors. (`tsc` resolves `api.mirrorTokens.*` and `Id<'mirrorTokens'>` from the codegen done in Tasks 1–2.)

- [ ] **Step 4: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add components/MirrorTokensManager.tsx app/dashboard/page.tsx && \
git commit -m "feat(web): add mirror-token management UI to the dashboard"
```

---

### Task 5: iOS `MirrorService` — send the Bearer token

**Files:**
- Edit: `ios/PetHomepage/Mirror/MirrorService.swift`
- Edit: `ios/PetHomepageTests/MirrorServiceTests.swift`

**Interfaces:**
- `MirrorConfig` gains `let token: String?`. When non-nil/non-empty, `URLSessionMirrorService.push` sets `Authorization: Bearer <token>`. The wire body becomes `{ "snapshot": <MirrorSnapshot JSON>, "schema_version": <Int> }` (the httpAction reads top-level `snapshot` + `schema_version`, not a bare snapshot). The success status becomes **200** (already the case) and the JSON envelope is wrapped server-side.

> **Wire-shape change:** Phase 5's `push` POSTed the bare `MirrorSnapshot` JSON. The httpAction expects `{ snapshot, schema_version }`. We wrap the encoded snapshot in that envelope. We reuse `MirrorSnapshot.encoder` for the inner snapshot and `JSONSerialization` to assemble the envelope so the snapshot keys stay byte-identical to the dashboard contract.

- [ ] **Step 1: Update the failing test to assert the Authorization header + envelope**

Replace `testPushPostsEncodedSnapshot` in `ios/PetHomepageTests/MirrorServiceTests.swift` and capture headers in the stub. First, extend `MirrorStubURLProtocol` with header capture — add this static and assignment:

In `MirrorStubURLProtocol`, add below `lastHTTPMethod`:

```swift
    nonisolated(unsafe) static var lastAuthorization: String?
```

In `startLoading()`, after `MirrorStubURLProtocol.lastHTTPMethod = request.httpMethod`, add:

```swift
        MirrorStubURLProtocol.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
```

In both `setUp()` and `tearDown()`, add `MirrorStubURLProtocol.lastAuthorization = nil`.

Then replace the `testPushPostsEncodedSnapshot` test with:

```swift
    func testPushPostsEnvelopeWithBearerToken() async throws {
        let service = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: URL(string: "https://example.com/mirror/push")!,
                token: "tok-abc-123"
            ),
            session: makeSession()
        )

        try await service.push(sampleSnapshot())

        XCTAssertEqual(MirrorStubURLProtocol.lastHTTPMethod, "POST")
        XCTAssertEqual(MirrorStubURLProtocol.lastAuthorization, "Bearer tok-abc-123")

        let body = MirrorStubURLProtocol.lastRequestBody ?? Data()
        let envelope = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(envelope?["schema_version"] as? Int, 1)
        let snapshot = envelope?["snapshot"] as? [String: Any]
        let pet = snapshot?["pet"] as? [String: Any]
        XCTAssertEqual(pet?["name"] as? String, "Sandy")
    }

    func testPushOmitsAuthorizationWhenTokenMissing() async throws {
        let service = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: URL(string: "https://example.com/mirror/push")!,
                token: nil
            ),
            session: makeSession()
        )
        try await service.push(sampleSnapshot())
        XCTAssertNil(MirrorStubURLProtocol.lastAuthorization)
    }
```

In `testPushThrowsOnNon200`, update the `MirrorConfig(...)` call to include `token: "tok"`:

```swift
            config: MirrorConfig(endpoint: URL(string: "https://example.com/mirror/push")!, token: "tok"),
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PetHomepageTests/MirrorServiceTests`
Expected: FAIL — `MirrorConfig` has no `token:` argument; `testPushPostsEnvelopeWithBearerToken` references missing behavior.

- [ ] **Step 3: Update `MirrorService.swift`**

Replace the `MirrorConfig` struct and the `push` method:

```swift
/// Where the opt-in mirror endpoint lives, plus the per-user capability token the dashboard
/// minted. `endpoint` is the Convex httpAction URL (`<deployment>.convex.site/mirror/push`).
/// `token` is the opaque bearer token (nil/empty until the user pastes one into Settings).
struct MirrorConfig {
    let endpoint: URL
    let token: String?
}
```

```swift
    func push(_ snapshot: MirrorSnapshot) async throws {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Envelope the snapshot as { snapshot, schema_version } for the httpAction. Encode the
        // snapshot with MirrorSnapshot.encoder so its keys/dates stay identical to the dashboard
        // contract, then wrap it without re-encoding the inner object.
        let snapshotData = try MirrorSnapshot.encoder.encode(snapshot)
        let snapshotObject = try JSONSerialization.jsonObject(with: snapshotData)
        let envelope: [String: Any] = [
            "snapshot": snapshotObject,
            "schema_version": snapshot.schemaVersion,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MirrorError.badStatus(http.statusCode)
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PetHomepageTests/MirrorServiceTests`
Expected: PASS (all MirrorService tests, including the two new ones).

- [ ] **Step 5: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add ios/PetHomepage/Mirror/MirrorService.swift ios/PetHomepageTests/MirrorServiceTests.swift && \
git commit -m "feat(ios): send Bearer token + schema envelope from MirrorService"
```

---

### Task 6: iOS `MirrorSettings` — persist endpoint + token, wire into ContentView

**Files:**
- Edit: `ios/PetHomepage/Mirror/MirrorSettings.swift`
- Edit: `ios/PetHomepage/App/ContentView.swift`
- Test: `ios/PetHomepageTests/MirrorCoordinatorTests.swift` (extend the existing `InMemoryMirrorSettings`-style coverage)

**Interfaces:**
- `MirrorSettings` protocol gains `var mirrorEndpoint: String { get set }` and `var mirrorToken: String { get set }` (both default `""`). `UserDefaultsMirrorSettings` persists them. `ContentView` builds `URLSessionMirrorService` from `mirrorSettings.mirrorEndpoint`/`.mirrorToken` (falling back to the build-time default endpoint when blank) so a user who pasted a token + their deployment URL gets a working push without rebuilding.

> **Test-support note:** `ios/PetHomepageTests/Support/InMemoryMirrorSettings.swift` conforms to `MirrorSettings`; it must gain the two new properties or it will fail to compile. Update it in the same task.

- [ ] **Step 1: Add the two properties to the protocol + production impl**

In `ios/PetHomepage/Mirror/MirrorSettings.swift`, extend the protocol:

```swift
protocol MirrorSettings: AnyObject {
    var isMirroringEnabled: Bool { get set }
    /// The Convex httpAction URL, e.g. https://<deployment>.convex.site/mirror/push. Blank = use the build default.
    var mirrorEndpoint: String { get set }
    /// The opaque bearer token minted in the dashboard. Blank until the user pastes one in.
    var mirrorToken: String { get set }
}
```

Extend `UserDefaultsMirrorSettings.Key` and add the accessors:

```swift
    private enum Key {
        static let isMirroringEnabled = "isMirroringEnabled"
        static let mirrorEndpoint = "mirrorEndpoint"
        static let mirrorToken = "mirrorToken"
    }
```

```swift
    var mirrorEndpoint: String {
        get { defaults.string(forKey: Key.mirrorEndpoint) ?? "" }
        set { defaults.set(newValue, forKey: Key.mirrorEndpoint) }
    }

    var mirrorToken: String {
        get { defaults.string(forKey: Key.mirrorToken) ?? "" }
        set { defaults.set(newValue, forKey: Key.mirrorToken) }
    }
```

- [ ] **Step 2: Update `InMemoryMirrorSettings` test helper to conform**

In `ios/PetHomepageTests/Support/InMemoryMirrorSettings.swift`, add the two stored-in-suite properties so the helper still satisfies `MirrorSettings`:

```swift
    var mirrorEndpoint: String {
        get { defaults.string(forKey: "mirrorEndpoint") ?? "" }
        set { defaults.set(newValue, forKey: "mirrorEndpoint") }
    }

    var mirrorToken: String {
        get { defaults.string(forKey: "mirrorToken") ?? "" }
        set { defaults.set(newValue, forKey: "mirrorToken") }
    }
```

- [ ] **Step 3: Add a coverage test for persistence + defaults**

Append to `MirrorCoordinatorTests`:

```swift
    func testEndpointAndTokenDefaultEmptyAndPersist() {
        let settings = UserDefaultsMirrorSettings(
            defaults: UserDefaults(suiteName: "endpoint-check-\(UUID().uuidString)")!
        )
        XCTAssertEqual(settings.mirrorEndpoint, "")
        XCTAssertEqual(settings.mirrorToken, "")
        settings.mirrorEndpoint = "https://dep.convex.site/mirror/push"
        settings.mirrorToken = "tok-xyz"
        XCTAssertEqual(settings.mirrorEndpoint, "https://dep.convex.site/mirror/push")
        XCTAssertEqual(settings.mirrorToken, "tok-xyz")
    }
```

- [ ] **Step 4: Build the production service from settings in `ContentView`**

In `ios/PetHomepage/App/ContentView.swift`, replace the mirror wiring block (the lines creating `mirrorSettings` and `mirrorService`) with:

```swift
        // Web integration bridge: build the mirror push client from the user-entered endpoint
        // + token (Settings). Blank endpoint falls back to the build-time Convex .site default.
        let mirrorSettings = UserDefaultsMirrorSettings()
        let defaultMirrorEndpoint = "https://your-deployment.convex.site/mirror/push"
        let mirrorEndpointString = mirrorSettings.mirrorEndpoint.isEmpty
            ? defaultMirrorEndpoint
            : mirrorSettings.mirrorEndpoint
        let mirrorEndpoint = URL(string: mirrorEndpointString)
            ?? URL(string: defaultMirrorEndpoint)!
        let mirrorService = URLSessionMirrorService(
            config: MirrorConfig(
                endpoint: mirrorEndpoint,
                token: mirrorSettings.mirrorToken.isEmpty ? nil : mirrorSettings.mirrorToken
            )
        )
```

- [ ] **Step 5: Run the iOS test suite slices to verify**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PetHomepageTests/MirrorCoordinatorTests -only-testing:PetHomepageTests/MirrorServiceTests`
Expected: PASS. If `ContentView` fails to build, confirm the `MirrorConfig(endpoint:token:)` call matches Task 5.

- [ ] **Step 6: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add ios/PetHomepage/Mirror/MirrorSettings.swift ios/PetHomepageTests/Support/InMemoryMirrorSettings.swift ios/PetHomepageTests/MirrorCoordinatorTests.swift ios/PetHomepage/App/ContentView.swift && \
git commit -m "feat(ios): persist mirror endpoint+token in settings and wire into push client"
```

---

### Task 7: iOS `ExtractionService` — JSON body + `x-extract-secret` header

**Files:**
- Edit: `ios/PetHomepage/Extraction/ExtractionService.swift`
- Edit: `ios/PetHomepageTests/ExtractionServiceTests.swift`

**Interfaces:**
- `ExtractionConfig` gains `let secret: String?`. `extract(fileData:mimeType:)` now POSTs **JSON** matching the route's `ExtractRequestSchema`: `{ fileName, mimeType, content (base64), note?, date? }`, with header `x-extract-secret: <secret>`. The `extract` signature gains optional `fileName`, `note`, `date` with defaults so existing call sites keep working.

> **Real contract mismatch (not cosmetic):** the existing Swift client POSTs `multipart/form-data` with only `mimeType` + `file`, but `app/api/extract/route.ts` calls `req.json()`, validates `ExtractRequestSchema` (`fileName`, `mimeType` enum, base64 `content`, optional `note`/`date`), and requires the `x-extract-secret` header. The multipart client would get a `400 Invalid JSON` / `401`. This task aligns the client to the server contract. The response shape (`{ ok, results }`) is unchanged and already handled by `ExtractionResponse` (decoded as `{ results: [...] }` — verify the existing decoder ignores the extra `ok` field, which `JSONDecoder` does by default).

- [ ] **Step 1: Rewrite the failing tests to assert JSON body + secret header**

In `ios/PetHomepageTests/ExtractionServiceTests.swift`, extend `StubURLProtocol` with a captured secret header — add below `lastRequestBody`:

```swift
    nonisolated(unsafe) static var lastSecretHeader: String?
```

In `startLoading()`, before reading the body, add:

```swift
        StubURLProtocol.lastSecretHeader = request.value(forHTTPHeaderField: "x-extract-secret")
```

Reset it in `setUp()`/`tearDown()` (`StubURLProtocol.lastSecretHeader = nil`).

Replace `testPostsAndDecodesResults` with:

```swift
    func testPostsJSONBodyWithSecretHeaderAndDecodesResults() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseData = Data("""
        {
          "ok": true,
          "results": [
            {
              "event_type": "vaccination",
              "occurred_at": "2026-03-01T10:00:00Z",
              "title": "Rabies",
              "fields": { "vaccine_name": "Rabies", "administered_at": "2026-03-01" }
            }
          ]
        }
        """.utf8)

        let service = URLSessionExtractionService(
            config: ExtractionConfig(
                endpoint: URL(string: "https://example.com/api/extract")!,
                secret: "extract-secret-123"
            ),
            session: makeSession()
        )

        let results = try await service.extract(
            fileData: Data("pdfbytes".utf8),
            mimeType: "application/pdf",
            fileName: "rabies.pdf",
            note: "from vet",
            date: "2026-03-01"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.eventType, .vaccination)
        XCTAssertEqual(StubURLProtocol.lastSecretHeader, "extract-secret-123")

        let body = StubURLProtocol.lastRequestBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["mimeType"] as? String, "application/pdf")
        XCTAssertEqual(json?["fileName"] as? String, "rabies.pdf")
        XCTAssertEqual(json?["note"] as? String, "from vet")
        XCTAssertEqual(json?["date"] as? String, "2026-03-01")
        // content is base64 of the file bytes
        XCTAssertEqual(json?["content"] as? String, Data("pdfbytes".utf8).base64EncodedString())
    }
```

Update the remaining `URLSessionExtractionService(config: ExtractionConfig(...))` constructions in `testThrowsOnNon200` and `testThrowsEmptyResultsWhenServerReturnsEmptyArray` to pass `secret: "s"`:

```swift
            config: ExtractionConfig(endpoint: URL(string: "https://example.com/api/extract")!, secret: "s"),
```

The two `FakeExtractionService` tests are unchanged (the fake's signature gains defaulted params; the calls still compile).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PetHomepageTests/ExtractionServiceTests`
Expected: FAIL — `ExtractionConfig` has no `secret:`; `extract` has no `fileName:/note:/date:`; body assertions fail (still multipart).

- [ ] **Step 3: Rewrite `ExtractionService.swift` to the JSON contract**

Replace `ExtractionConfig`, the `extract` signature/body, and the multipart helper:

```swift
/// Where the AI extraction endpoint lives, plus the shared secret the route requires.
/// `secret` is sent as the `x-extract-secret` header; nil/empty omits it (the route 401s).
struct ExtractionConfig {
    let endpoint: URL
    let secret: String?
}
```

Update the protocol signature so fakes and the prod impl agree:

```swift
protocol ExtractionService {
    func extract(
        fileData: Data,
        mimeType: String,
        fileName: String,
        note: String?,
        date: String?
    ) async throws -> [ExtractionResult]
}

extension ExtractionService {
    /// Convenience: keep existing call sites working with sensible defaults.
    func extract(fileData: Data, mimeType: String) async throws -> [ExtractionResult] {
        try await extract(fileData: fileData, mimeType: mimeType,
                          fileName: "upload", note: nil, date: nil)
    }
}
```

Replace `URLSessionExtractionService.extract(...)` and delete `multipartBody`:

```swift
    func extract(
        fileData: Data,
        mimeType: String,
        fileName: String,
        note: String?,
        date: String?
    ) async throws -> [ExtractionResult] {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = config.secret, !secret.isEmpty {
            request.setValue(secret, forHTTPHeaderField: "x-extract-secret")
        }

        // Matches lib/schemas/extract-request.ts: { fileName, mimeType, content(base64), note?, date? }
        var payload: [String: Any] = [
            "fileName": fileName,
            "mimeType": mimeType,
            "content": fileData.base64EncodedString(),
        ]
        if let note { payload["note"] = note }
        if let date { payload["date"] = date }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ExtractionError.badStatus(http.statusCode)
        }
        let decoded = try ExtractionResult.decoder.decode(ExtractionResponse.self, from: data)
        if decoded.results.isEmpty { throw ExtractionError.emptyResults }
        return decoded.results
    }
```

- [ ] **Step 4: Update `FakeExtractionService` to the new signature**

In `ios/PetHomepageTests/Support/FakeExtractionService.swift`, change `extract` to the five-arg protocol method (record the new fields; keep `lastMimeType`/`lastFileData`). Add `private(set) var lastFileName: String?`, `lastNote: String?`, `lastDate: String?` and set them in `extract`. The existing two FakeExtractionService tests call the convenience overload, so they keep compiling.

- [ ] **Step 5: Update the real call site (document upload flow)**

Search for callers: `grep -rn "\.extract(" ios/PetHomepage --include='*.swift'`. For each production caller, pass a real `fileName` (and `note`/`date` if available) or rely on the convenience overload. Update the `ExtractionConfig(...)` construction (likely in a view model or `ContentView`) to include `secret: <from settings or build default>`. If no production caller exists yet (extraction UI is deferred), record that and ensure the build still links.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:PetHomepageTests/ExtractionServiceTests`
Expected: PASS (all ExtractionService tests).

- [ ] **Step 7: Run the FULL iOS suite to catch cross-file regressions**

Run: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'`
Expected: PASS. Fix any caller that broke from the `ExtractionService`/`MirrorConfig` signature changes.

- [ ] **Step 8: Commit**

```bash
cd /Users/suki/dev/pet-homepage && git add ios/PetHomepage/Extraction/ExtractionService.swift ios/PetHomepageTests/ExtractionServiceTests.swift ios/PetHomepageTests/Support/FakeExtractionService.swift && \
git commit -m "feat(ios): align ExtractionService to /api/extract JSON contract + secret header"
```

> If Step 5 touched a production view model / `ContentView`, add those files to the same `git add` before committing.

---

### Task 8: Config documentation (`.env.local.example`) + integration notes

**Files:**
- Edit: `.env.local.example` (gitignored — keep accurate, do not commit secrets)

**Interfaces:** documents `MIRROR_TOKEN_PEPPER`, reiterates `EXTRACT_SECRET`, and notes the Convex `.site` host the iOS app targets.

- [ ] **Step 1: Append the new config keys + guidance**

Add to `.env.local.example`:

```
# Server-side pepper mixed into the SHA-256 of each mirror capability token.
# Set on the Convex deployment (NOT here): npx convex env set MIRROR_TOKEN_PEPPER <64-hex-bytes>
# Generate one: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
MIRROR_TOKEN_PEPPER=set-via-convex-env-set

# The iOS app posts mirror snapshots to the Convex httpAction host (.convex.site, NOT .convex.cloud):
#   POST $NEXT_PUBLIC_CONVEX_SITE_URL/mirror/push   with  Authorization: Bearer <minted token>
# The user mints a token on /dashboard and pastes it (plus this URL) into the app's Settings.
NEXT_PUBLIC_CONVEX_SITE_URL=https://your-deployment.convex.site
```

> `.env.local.example` is gitignored in this repo; this step keeps the developer-facing example accurate. If the file already contains `NEXT_PUBLIC_CONVEX_SITE_URL`, only add the `MIRROR_TOKEN_PEPPER` block and the comment above it.

- [ ] **Step 2: Final cross-stack verification**

Run all three:
- Convex: `cd /Users/suki/dev/pet-homepage && npx convex codegen && npx tsc --noEmit`
- Next: `cd /Users/suki/dev/pet-homepage && npx tsc --noEmit && npx biome check components/MirrorTokensManager.tsx app/dashboard/page.tsx`
- iOS: `cd /Users/suki/dev/pet-homepage/ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'`

Expected: all green.

- [ ] **Step 3: Commit (only if `.env.local.example` is actually tracked)**

`.env.local.example` is gitignored, so there is normally nothing to stage here. If `git status` shows it as tracked/modified, `git add .env.local.example` and commit `docs(config): document MIRROR_TOKEN_PEPPER + Convex .site host`. Otherwise, skip the commit and record that the file is gitignored.

---

## Live-verification checklist (OUT OF SCOPE here — flag for a human) [LIVE]

These cannot be validated in this environment and must be confirmed on a real device + running deployment:

1. **Mint → paste → push:** Sign in to `/dashboard`, mint a token, paste it + `NEXT_PUBLIC_CONVEX_SITE_URL/mirror/push` into the iOS Settings, enable mirroring, "Sync now". Confirm `200 {"ok":true}` and that `/dashboard` (`api.mirror.get`) renders the pushed snapshot for that same user.
2. **Revoke:** Revoke the token in the dashboard; confirm the next push returns `401`.
3. **Wrong/blank token:** Confirm `401` for a bogus bearer token and for a missing `Authorization` header.
4. **Pepper unset:** Confirm `503` when `MIRROR_TOKEN_PEPPER` is not set on the deployment.
5. **Extract:** With a real `ANTHROPIC_API_KEY` + `EXTRACT_SECRET` set, upload a PDF/image from the app; confirm `200 { ok, results }` and that a wrong/blank `x-extract-secret` returns `401`, oversized payload `413`, unsupported MIME `415`.

## Notes

- **Why an envelope for the mirror push (Task 5):** the httpAction reads `{ snapshot, schema_version }`. The public `mirror.push` mutation (used by any future Convex-auth client) takes `{ snapshot, schemaVersion }` and stays as-is — the two paths converge on the same `mirrors` row via `upsertForUser`.
- **`getAuthUserId` vs. `getUserIdentity`:** mint/revoke/list use `getAuthUserId(ctx)` (the `@convex-dev/auth` helper already used by `convex/mirror.ts`). The httpAction does NOT use auth at all — it resolves the user from the opaque token, per the research's explicit caveat.
- **No `"use node"`:** `convex/crypto.ts` uses Web Crypto, available in the default V8 runtime, so it can be imported by both the httpAction and the (default-runtime) mutation.
