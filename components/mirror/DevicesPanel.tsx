'use client'
import { QRCodeSVG } from 'qrcode.react'
import { useState } from 'react'

// Presentational pairing/devices UI. The dashboard container wires it to Convex;
// app/dev/preview wires it to fixtures. `prominent` renders the pairing action
// as the primary CTA (used in the no-mirror onboarding state).

export type TokenRow = {
  _id: string
  label?: string
  createdAt: number
  revokedAt?: number
}

export type PairState = { code: string; expiresAt: number; endpoint: string }

function fmt(ms?: number): string {
  if (!ms) return '—'
  return new Date(ms).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

export function DevicesPanel({
  tokens,
  pair,
  pairBusy,
  freshToken,
  mintBusy,
  prominent = false,
  onPair,
  onMint,
  onRevoke,
}: {
  tokens: TokenRow[] | undefined
  pair: PairState | null
  pairBusy: boolean
  freshToken: string | null
  mintBusy: boolean
  prominent?: boolean
  onPair: () => void
  onMint: (label: string) => void
  onRevoke: (tokenId: string) => void
}) {
  const [label, setLabel] = useState('')
  const activeTokens = (tokens ?? []).filter((t) => !t.revokedAt)
  const revokedTokens = (tokens ?? []).filter((t) => t.revokedAt)

  return (
    <div className="panel">
      <div style={{ padding: '16px 16px 14px' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            gap: 12,
            flexWrap: 'wrap',
          }}
        >
          <p className="devices-note">
            In the app:{' '}
            <b style={{ color: 'var(--ink)', fontWeight: 600 }}>Settings → Pair a device</b>. Scan
            the QR or type the code.
          </p>
          <button
            type="button"
            className={prominent ? 'btn' : 'btn-quiet sm'}
            onClick={onPair}
            disabled={pairBusy}
          >
            {pairBusy ? 'Generating…' : pair ? 'New code' : 'Pair a device'}
          </button>
        </div>

        {pair && (
          <div
            style={{
              marginTop: 16,
              display: 'flex',
              gap: 20,
              alignItems: 'center',
              flexWrap: 'wrap',
            }}
          >
            <div className="qr-box">
              <QRCodeSVG value={JSON.stringify({ e: pair.endpoint, c: pair.code })} size={124} />
            </div>
            <div>
              <p style={{ margin: '0 0 4px', fontSize: 12, color: 'var(--ink-3)' }}>
                Or enter this code:
              </p>
              <div className="pair-code">
                {pair.code.slice(0, 4)} {pair.code.slice(4)}
              </div>
              <p style={{ margin: '6px 0 0', fontSize: 12, color: 'var(--ink-3)' }}>
                Expires{' '}
                {new Date(pair.expiresAt).toLocaleTimeString('en-US', {
                  hour: 'numeric',
                  minute: '2-digit',
                })}{' '}
                · one-time use
              </p>
            </div>
          </div>
        )}

        <details style={{ marginTop: 14 }}>
          <summary style={{ fontSize: 12.5, color: 'var(--ink-3)', cursor: 'pointer' }}>
            Prefer a manual token?
          </summary>
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            <label
              htmlFor="device-label"
              style={{
                position: 'absolute',
                width: 1,
                height: 1,
                overflow: 'hidden',
                clip: 'rect(0 0 0 0)',
              }}
            >
              Device label
            </label>
            <input
              id="device-label"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="Device label (e.g. iPhone 15)"
              className="ob-input"
              style={{ flex: 1, padding: '8px 12px', fontSize: 14 }}
            />
            <button
              type="button"
              className="btn-quiet sm"
              disabled={mintBusy}
              onClick={() => {
                onMint(label)
                setLabel('')
              }}
            >
              {mintBusy ? 'Minting…' : 'Mint token'}
            </button>
          </div>
          {freshToken && (
            <div className="token-reveal">
              <p>
                Copy this token now — it will not be shown again. Paste it into the app’s Settings.
              </p>
              <code>{freshToken}</code>
            </div>
          )}
        </details>
      </div>

      {(tokens === undefined || activeTokens.length + revokedTokens.length > 0) && (
        <div style={{ borderTop: '1px solid var(--rule)' }}>
          {tokens === undefined ? (
            <div className="trow">
              <div className="skel" style={{ height: 16, width: 180 }} />
            </div>
          ) : (
            <>
              {activeTokens.map((t) => (
                <div key={t._id} className="trow">
                  <span className="tn">
                    {t.label || 'Unlabeled device'}
                    <small>paired {fmt(t.createdAt)}</small>
                  </span>
                  <button type="button" className="btn-danger sm" onClick={() => onRevoke(t._id)}>
                    Revoke
                  </button>
                </div>
              ))}
              {revokedTokens.map((t) => (
                <div key={t._id} className="trow" style={{ opacity: 0.65 }}>
                  <span className="tn">
                    {t.label || 'Unlabeled device'}
                    <small>paired {fmt(t.createdAt)}</small>
                  </span>
                  <span className="revoked">revoked {fmt(t.revokedAt)}</span>
                </div>
              ))}
            </>
          )}
        </div>
      )}
    </div>
  )
}
