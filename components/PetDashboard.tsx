'use client'

import { Composer } from './Composer'
import { Hero } from './Hero'
import { RecordsSidebar } from './RecordsSidebar'
import { Timeline } from './Timeline'
import { Topbar } from './Topbar'
import { usePetData } from '@/hooks/usePetData'

export function PetDashboard() {
  const { pet, events, weightLogs, medications, vaccinations, vetVisits, loading, petId } = usePetData()

  if (loading) {
    return (
      <div style={{ minHeight: '100dvh', display: 'grid', placeItems: 'center', color: 'var(--ink-3)', fontSize: 14 }}>
        Loading…
      </div>
    )
  }

  if (!petId || !pet) return null // redirect in flight

  return (
    <>
      <Topbar pet={pet} />
      <div className="page">
        <Hero
          pet={pet}
          latestWeight={weightLogs[0] ?? null}
          medications={medications}
          vaccinations={vaccinations}
        />
        <div className="grid-main">
          <Timeline events={events} />
          <RecordsSidebar
            weightLogs={weightLogs}
            medications={medications}
            vaccinations={vaccinations}
            vetVisits={vetVisits}
          />
        </div>
        <div className="footer">
          <span className="mono">{`HOMEPAGE.PET · ${pet.name.toUpperCase()} · v.4.7.2026`}</span>
          <span>made with care</span>
        </div>
      </div>
      <Composer petId={petId} petName={pet.name} />
    </>
  )
}
