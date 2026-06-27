'use client'
import { useQuery } from 'convex/react'
import { api } from '@/convex/_generated/api'

// Read-only desktop dashboard rendering the pet health-record snapshot the iOS
// app mirrors to Convex (see ios/PetHomepage/Mirror/MirrorSnapshot.swift for the
// contract). Auth-gated by middleware.ts; useQuery returns the signed-in user's
// own mirror or null.

type Snapshot = {
  schema_version: number
  generated_at: string
  pet: {
    id: string
    name: string
    species: string
    breed?: string
    dob?: string
    adoption_date?: string
  }
  medications: Array<{
    id: string
    drug_name: string
    dosage: string
    frequency: string
    schedule_time: string
    started_at: string
    ended_at?: string
    refill_due_at?: string
    dose_logs: Array<{ id: string; given_at: string }>
    veterinarian?: string
  }>
  vaccinations: Array<{
    id: string
    vaccine_name: string
    administered_at?: string
    next_due_at?: string
    lot_number?: string
    administered_by?: string
    veterinarian?: string
  }>
  vet_visits: Array<{
    id: string
    occurred_at: string
    clinic_name?: string
    vet_name?: string
    reason?: string
    diagnosis?: string
    treatment_notes?: string
    next_visit_date?: string
    recommendations: Array<{ id: string; date: string; text: string }>
    veterinarian?: string
  }>
  unlinked_recommendations: Array<{ id: string; date: string; text: string }>
  health_markers: Array<{
    id: string
    marker_type: string
    value: number
    unit?: string
    recorded_at: string
  }>
  symptom_episodes: Array<{
    id: string
    category: string
    title?: string
    started_at: string
    resolved_at?: string
    status: string
    entries: Array<{
      id: string
      date: string
      severity: string
      note?: string
      suspected_cause?: string
    }>
  }>
  care_team?: Array<{
    id: string
    name: string
    clinic?: string
    phone?: string
    email?: string
    address?: string
    website?: string
    notes?: string
  }>
  diary?: Array<{
    id: string
    date: string
    note?: string
    photo_count: number
  }>
}

function fmt(iso?: string): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function Section({
  title,
  count,
  children,
}: {
  title: string
  count: number
  children: React.ReactNode
}) {
  return (
    <section style={{ marginBottom: 28 }}>
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
        {title} <span style={{ color: '#9ca3af', fontWeight: 500 }}>({count})</span>
      </h2>
      {count === 0 ? (
        <div style={card({ color: '#9ca3af', textAlign: 'center' })}>Nothing logged</div>
      ) : (
        children
      )}
    </section>
  )
}

function card(extra: React.CSSProperties = {}): React.CSSProperties {
  return {
    background: '#ffffff',
    border: '1px solid #e5e7eb',
    borderRadius: 12,
    padding: '14px 16px',
    marginBottom: 10,
    fontSize: 14,
    color: '#111827',
    ...extra,
  }
}

const meta: React.CSSProperties = { fontSize: 12, color: '#6b7280', marginTop: 2 }

export function MirrorDashboard() {
  const mirror = useQuery(api.mirror.get)

  if (mirror === undefined) {
    return (
      <Shell>
        <p style={{ color: '#6b7280' }}>Loading…</p>
      </Shell>
    )
  }
  if (mirror === null) {
    return (
      <Shell>
        <div style={card({ textAlign: 'center', padding: '40px 20px', color: '#6b7280' })}>
          <p style={{ fontSize: 16, fontWeight: 600, color: '#111827', margin: '0 0 6px' }}>
            No mirror yet
          </p>
          <p style={{ margin: 0 }}>
            Turn on “Mirror to web” in the app’s Settings to see your pet’s record here.
          </p>
        </div>
      </Shell>
    )
  }

  const snap = mirror.snapshot as Snapshot

  return (
    <Shell>
      <header style={{ marginBottom: 24 }}>
        <h1 style={{ fontSize: 28, fontWeight: 800, margin: 0, color: '#111827' }}>
          {snap.pet.name}
        </h1>
        <p style={meta}>
          {[snap.pet.species, snap.pet.breed].filter(Boolean).join(' · ')}
          {snap.pet.dob ? ` · born ${fmt(snap.pet.dob)}` : ''}
        </p>
        <p style={meta}>
          Last synced {fmt(mirror.updatedAt ? new Date(mirror.updatedAt).toISOString() : undefined)}
        </p>
      </header>

      <Section title="Diary" count={snap.diary?.length ?? 0}>
        {(snap.diary ?? []).map((e) => (
          <div key={e.id} style={card()}>
            <strong>{fmt(e.date)}</strong>
            {e.photo_count > 0 && (
              <span style={{ color: '#6b7280' }}>
                {' '}
                · {e.photo_count} photo{e.photo_count === 1 ? '' : 's'}
              </span>
            )}
            {e.note && <div style={meta}>{e.note}</div>}
          </div>
        ))}
      </Section>

      <Section title="Care team" count={snap.care_team?.length ?? 0}>
        {(snap.care_team ?? []).map((vet) => (
          <div key={vet.id} style={card()}>
            <strong>{vet.name}</strong>
            {vet.clinic && <span style={{ color: '#6b7280' }}> · {vet.clinic}</span>}
            <div style={meta}>
              {[vet.phone, vet.email, vet.website].filter(Boolean).join(' · ') || '—'}
              {vet.address ? ` · ${vet.address}` : ''}
            </div>
            {vet.notes && <div style={meta}>{vet.notes}</div>}
          </div>
        ))}
      </Section>

      <Section title="Medications" count={snap.medications.length}>
        {snap.medications.map((m) => {
          const last = m.dose_logs
            .map((d) => d.given_at)
            .sort()
            .at(-1)
          return (
            <div key={m.id} style={card()}>
              <strong>{m.drug_name}</strong>{' '}
              {m.dosage && <span style={{ color: '#6b7280' }}>· {m.dosage}</span>}
              <div style={meta}>
                {m.frequency} · last given {fmt(last)} · {m.dose_logs.length} dose(s)
                {m.veterinarian ? ` · ${m.veterinarian}` : ''}
                {m.refill_due_at ? ` · refill ${fmt(m.refill_due_at)}` : ''}
                {m.ended_at ? ' · ended' : ''}
              </div>
            </div>
          )
        })}
      </Section>

      <Section title="Vaccinations" count={snap.vaccinations.length}>
        {snap.vaccinations.map((v) => (
          <div key={v.id} style={card()}>
            <strong>{v.vaccine_name}</strong>
            <div style={meta}>
              given {fmt(v.administered_at)} · next due {fmt(v.next_due_at)}
              {v.administered_by ? ` · by ${v.administered_by}` : ''}
              {v.veterinarian ? ` · ${v.veterinarian}` : ''}
            </div>
          </div>
        ))}
      </Section>

      <Section title="Vet visits" count={snap.vet_visits.length}>
        {snap.vet_visits.map((vv) => (
          <div key={vv.id} style={card()}>
            <strong>{fmt(vv.occurred_at)}</strong>
            {vv.clinic_name && <span style={{ color: '#6b7280' }}> · {vv.clinic_name}</span>}
            <div style={meta}>
              {[vv.reason, vv.diagnosis].filter(Boolean).join(' · ') || 'Visit'}
              {vv.veterinarian ? ` · ${vv.veterinarian}` : ''}
              {vv.next_visit_date ? ` · next ${fmt(vv.next_visit_date)}` : ''}
            </div>
            {vv.recommendations.length > 0 && (
              <ul style={{ margin: '8px 0 0', paddingLeft: 18, color: '#374151', fontSize: 13 }}>
                {vv.recommendations.map((r) => (
                  <li key={r.id}>
                    {r.text} <span style={{ color: '#9ca3af' }}>({fmt(r.date)})</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </Section>

      <Section title="Health markers" count={snap.health_markers.length}>
        {snap.health_markers.map((hm) => (
          <div key={hm.id} style={card()}>
            <strong>{hm.marker_type}</strong>: {hm.value}
            {hm.unit ? ` ${hm.unit}` : ''}
            <div style={meta}>{fmt(hm.recorded_at)}</div>
          </div>
        ))}
      </Section>

      <Section title="Symptoms" count={snap.symptom_episodes.length}>
        {snap.symptom_episodes.map((ep) => (
          <div key={ep.id} style={card()}>
            <strong>{ep.title || ep.category}</strong>
            <span
              style={{
                color: ep.status === 'resolved' ? '#059669' : '#d97706',
                fontSize: 12,
                marginLeft: 8,
              }}
            >
              {ep.status}
            </span>
            <div style={meta}>
              {ep.category} · started {fmt(ep.started_at)}
              {ep.resolved_at ? ` · resolved ${fmt(ep.resolved_at)}` : ''}
            </div>
            {ep.entries.length > 0 && (
              <ul style={{ margin: '8px 0 0', paddingLeft: 18, color: '#374151', fontSize: 13 }}>
                {ep.entries.map((e) => (
                  <li key={e.id}>
                    {fmt(e.date)} — {e.severity}
                    {e.note ? `: ${e.note}` : ''}
                    {e.suspected_cause ? ` (cause: ${e.suspected_cause})` : ''}
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </Section>
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main
      style={{
        maxWidth: 720,
        margin: '0 auto',
        padding: '40px 20px',
        fontFamily: 'system-ui, -apple-system, sans-serif',
      }}
    >
      {children}
    </main>
  )
}
