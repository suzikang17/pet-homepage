'use client'
import { useMutation, useQuery } from 'convex/react'
import { useState } from 'react'
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
              Copy this token now — it will not be shown again. Paste it into the app's Settings.
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
