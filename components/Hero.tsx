interface Pet { name: string; species: string; breed?: string; dob?: string }
interface WeightLog { weightKg: number; recordedAt: string }
interface Medication { drugName: string; endedAt?: string; refillDueAt?: string }
interface Vaccination { vaccineName: string; nextDueAt?: string }

interface HeroProps {
  pet: Pet
  latestWeight: WeightLog | null
  medications: Medication[]
  vaccinations: Vaccination[]
}

function getAge(dob?: string): string {
  if (!dob) return '?'
  const ms = Date.now() - new Date(dob).getTime()
  const years = Math.floor(ms / (365.25 * 24 * 60 * 60 * 1000))
  if (years === 0) {
    const months = Math.floor(ms / (30.44 * 24 * 60 * 60 * 1000))
    return `${months} mo`
  }
  return `${years} yr${years !== 1 ? 's' : ''}`
}

export function Hero({ pet, latestWeight, medications, vaccinations }: HeroProps) {
  const speciesLabel = pet.species === 'dog' ? 'Dog' : pet.species === 'cat' ? 'Cat' : pet.species
  const age = getAge(pet.dob)
  const activeMeds = medications.filter(m => !m.endedAt)
  const overdueSoon = vaccinations.filter(v => {
    if (!v.nextDueAt) return false
    const diff = new Date(v.nextDueAt).getTime() - Date.now()
    return diff < 30 * 24 * 60 * 60 * 1000 // due within 30 days or overdue
  })

  return (
    <section className="hero">
      <div className="hero-photo">
        <div className="ph-tag">
          <span className="dot"></span>
          {overdueSoon.length > 0 ? 'Vaccine due soon' : 'Up to date'}
        </div>
      </div>
      <div className="hero-meta">
        <div className="hero-eye">
          {[speciesLabel, pet.breed, age + ' yrs'].filter(Boolean).join(' · ')}
        </div>
        <h1 className="serif">
          {pet.name}<span className="punct">.</span>
        </h1>
        <p className="hero-bio">
          Welcome to {pet.name}&apos;s page. Log walks, vet visits, medications, and anything else that matters.
        </p>
        <div className="hero-stats">
          <div className="stat">
            <div className="k">Weight</div>
            <div className="v">
              {latestWeight ? latestWeight.weightKg.toFixed(1) : '—'}
              {latestWeight && <small>kg</small>}
            </div>
            {latestWeight && <div className="d">{latestWeight.recordedAt}</div>}
          </div>
          <div className="stat">
            <div className="k">Vaccines</div>
            <div className="v">{vaccinations.length}<small> logged</small></div>
            {overdueSoon.length > 0 && <div className="d warn">{overdueSoon.length} due soon</div>}
          </div>
          <div className="stat">
            <div className="k">Active Rx</div>
            <div className="v">{activeMeds.length}</div>
            {activeMeds.length === 0 && <div className="d">None logged</div>}
          </div>
          <div className="stat">
            <div className="k">Next visit</div>
            <div className="v sm">—</div>
            <div className="d">Not scheduled</div>
          </div>
        </div>
      </div>
    </section>
  )
}
