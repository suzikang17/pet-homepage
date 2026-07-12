'use client'
import { useAuthActions } from '@convex-dev/auth/react'
import { useMutation, useQuery } from 'convex/react'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { DevicesPanel, type PairState } from '@/components/mirror/DevicesPanel'
import { SnapshotFooter, SnapshotView } from '@/components/mirror/SnapshotView'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'
import type { MirrorSnapshot } from '@/lib/types/mirror'

// Dashboard container: fetches the signed-in user's mirror + device tokens from
// Convex and renders the read-only record (SnapshotView) with pairing management
// (DevicesPanel). Presentation lives in those two components so /dev/preview can
// render them from fixtures.

export function MirrorDashboard() {
  const mirror = useQuery(api.mirror.get)
  const tokens = useQuery(api.mirrorTokens.listMirrorTokens)
  const mint = useMutation(api.mirrorTokens.mintMirrorToken)
  const revoke = useMutation(api.mirrorTokens.revokeMirrorToken)
  const createPair = useMutation(api.pairing.createPairingCode)
  const { signOut } = useAuthActions()
  const router = useRouter()

  const [freshToken, setFreshToken] = useState<string | null>(null)
  const [mintBusy, setMintBusy] = useState(false)
  const [pair, setPair] = useState<PairState | null>(null)
  const [pairBusy, setPairBusy] = useState(false)

  async function handleMint(label: string) {
    setMintBusy(true)
    try {
      const { rawToken } = await mint({ label: label.trim() || undefined })
      setFreshToken(rawToken)
    } finally {
      setMintBusy(false)
    }
  }

  async function handlePair() {
    setPairBusy(true)
    try {
      const p = await createPair()
      setPair({
        ...p,
        // Fall back to the build-time site URL if the server env didn't return one.
        endpoint: p.endpoint || process.env.NEXT_PUBLIC_CONVEX_SITE_URL || '',
      })
    } finally {
      setPairBusy(false)
    }
  }

  const devices = (
    <DevicesPanel
      tokens={tokens}
      pair={pair}
      pairBusy={pairBusy}
      freshToken={freshToken}
      mintBusy={mintBusy}
      prominent={mirror === null}
      onPair={handlePair}
      onMint={handleMint}
      onRevoke={(tokenId) => revoke({ tokenId: tokenId as Id<'mirrorTokens'> })}
    />
  )

  return (
    <>
      <Topbar
        onSignOut={async () => {
          await signOut()
          router.replace('/sign-in')
        }}
      />
      <main className="page-rec">
        {mirror === undefined ? (
          <LoadingSkeleton />
        ) : mirror === null ? (
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
              snapshot={mirror.snapshot as MirrorSnapshot}
              updatedAt={mirror.updatedAt}
            />
            <section>
              <div className="section-h">
                <h2>Devices</h2>
                <span className="sh-aside">phones allowed to sync this record</span>
              </div>
              {devices}
            </section>
            <SnapshotFooter snapshot={mirror.snapshot as MirrorSnapshot} />
          </>
        )}
      </main>
    </>
  )
}

function Topbar({ onSignOut }: { onSignOut: () => void }) {
  return (
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
        <button type="button" className="btn-quiet sm" onClick={onSignOut}>
          Sign out
        </button>
      </nav>
    </div>
  )
}

function LoadingSkeleton() {
  return (
    <div role="status" aria-busy="true" aria-label="Loading your pet’s record">
      <div className="skel" style={{ height: 54, width: 240, marginBottom: 12 }} />
      <div className="skel" style={{ height: 16, width: 320, marginBottom: 40 }} />
      <div className="skel" style={{ height: 96, marginBottom: 12 }} />
      <div className="skel" style={{ height: 96, marginBottom: 40 }} />
      <div className="skel" style={{ height: 220 }} />
    </div>
  )
}
