'use client'
import { notFound, useSearchParams } from 'next/navigation'
import { Suspense, useState } from 'react'
import { DevicesPanel, type PairState } from '@/components/mirror/DevicesPanel'
import { SnapshotFooter, SnapshotView } from '@/components/mirror/SnapshotView'
import {
  FIXTURE_NOW,
  fixtureSnapshot,
  fixtureTokens,
  fixtureUpdatedAt,
} from '@/lib/fixtures/mirrorSnapshot'

// Fixture-driven preview of the dashboard so it can be designed and QA'd in a
// browser without a paired iPhone pushing a real mirror. Dev-only.
// States: /dev/preview (full record), ?state=empty (onboarding), ?state=pair
// (pairing code open).

function Preview() {
  const params = useSearchParams()
  const state = params.get('state')
  const [pair, setPair] = useState<PairState | null>(
    state === 'pair'
      ? {
          code: '48219307',
          expiresAt: fixtureUpdatedAt + 10 * 60_000,
          endpoint: 'https://example.convex.site',
        }
      : null
  )
  const [freshToken, setFreshToken] = useState<string | null>(null)

  const devices = (
    <DevicesPanel
      tokens={fixtureTokens}
      pair={pair}
      pairBusy={false}
      freshToken={freshToken}
      mintBusy={false}
      prominent={state === 'empty'}
      onPair={() =>
        setPair({
          code: '48219307',
          expiresAt: fixtureUpdatedAt + 10 * 60_000,
          endpoint: 'https://example.convex.site',
        })
      }
      onMint={() => setFreshToken('mtk_9f2c4e8a1b7d6f3a5c0e2d4b6a8f1c3e5d7b9a0c2e4f6a8b')}
      onRevoke={() => {}}
    />
  )

  return (
    <>
      <div className="topbar">
        <div className="brand">
          <div className="brand-mark" aria-hidden>
            h
          </div>
          <div className="brand-text">
            <div className="brand-name">Homepage</div>
            <div className="brand-url">homepage.pet</div>
          </div>
        </div>
        <nav className="nav">
          <button type="button" className="btn-quiet sm">
            Sign out
          </button>
        </nav>
      </div>
      <main className="page-rec">
        {state === 'empty' ? (
          <div className="onboard">
            <div className="brand-mark" aria-hidden>
              h
            </div>
            <h1>Bring your pet’s record here.</h1>
            <p>
              Pair your iPhone and the app will mirror your pet’s health record — medications,
              vaccinations, visits and diary — to this page, read-only.
            </p>
            <div style={{ textAlign: 'left' }}>{devices}</div>
          </div>
        ) : (
          <>
            <SnapshotView
              snapshot={fixtureSnapshot}
              updatedAt={fixtureUpdatedAt}
              now={FIXTURE_NOW}
            />
            <section>
              <div className="section-h">
                <h2>Devices</h2>
                <span className="sh-aside">phones allowed to sync this record</span>
              </div>
              {devices}
            </section>
            <SnapshotFooter snapshot={fixtureSnapshot} />
          </>
        )}
      </main>
    </>
  )
}

export default function PreviewPage() {
  if (process.env.NODE_ENV === 'production') notFound()
  return (
    <Suspense>
      <Preview />
    </Suspense>
  )
}
