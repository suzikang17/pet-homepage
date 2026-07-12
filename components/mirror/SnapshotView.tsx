import type { MirrorSnapshot } from '@/lib/types/mirror'

// Pure presentational view of a mirrored health record. No data fetching:
// MirrorDashboard feeds it the live Convex snapshot, app/dev/preview feeds it
// the fixture. `now` is injectable so due/overdue states render deterministically.

const DAY = 86_400_000

function parse(iso?: string): Date | null {
  if (!iso) return null
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? null : d
}

function fmt(iso?: string): string {
  const d = parse(iso)
  return d
    ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
    : '—'
}

function fmtShort(iso?: string): string {
  const d = parse(iso)
  return d ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '—'
}

function daysUntil(iso: string | undefined, now: Date): number | null {
  const d = parse(iso)
  return d ? Math.round((d.getTime() - now.getTime()) / DAY) : null
}

function durationMinutes(startIso?: string, endIso?: string): number | null {
  const start = parse(startIso)
  const end = parse(endIso)
  if (!start || !end) return null
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 60_000))
}

type DueStatus = 'over' | 'soon' | 'ok' | 'none'

function dueStatus(iso: string | undefined, now: Date, soonDays: number): DueStatus {
  const days = daysUntil(iso, now)
  if (days === null) return 'none'
  if (days < 0) return 'over'
  if (days <= soonDays) return 'soon'
  return 'ok'
}

function dueCopy(iso: string | undefined, now: Date): string {
  const days = daysUntil(iso, now)
  if (days === null) return ''
  if (days < -1) return `Overdue by ${-days} days`
  if (days === -1) return 'Overdue by 1 day'
  if (days === 0) return 'Due today'
  if (days === 1) return 'Due tomorrow'
  return `Due in ${days} days`
}

function petAge(dob: string | undefined, now: Date): string | null {
  const d = parse(dob)
  if (!d) return null
  const months = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth())
  if (months < 12) return `${months} mo old`
  const years = Math.floor(months / 12)
  return `${years} year${years === 1 ? '' : 's'} old`
}

function SectionHead({ title, aside }: { title: string; aside?: string }) {
  return (
    <div className="section-h">
      <h2>{title}</h2>
      {aside && <span className="sh-aside">{aside}</span>}
    </div>
  )
}

export function SnapshotView({
  snapshot,
  updatedAt,
  now = new Date(),
}: {
  snapshot: MirrorSnapshot
  updatedAt?: number
  now?: Date
}) {
  const snap = snapshot
  const activeMeds = snap.medications.filter((m) => !m.ended_at)
  const pastMeds = snap.medications.filter((m) => m.ended_at)
  const vaccines = [...snap.vaccinations].sort((a, b) => {
    const da = daysUntil(a.next_due_at, now) ?? Number.POSITIVE_INFINITY
    const db = daysUntil(b.next_due_at, now) ?? Number.POSITIVE_INFINITY
    return da - db
  })
  const visits = [...snap.vet_visits].sort(
    (a, b) => (parse(b.occurred_at)?.getTime() ?? 0) - (parse(a.occurred_at)?.getTime() ?? 0)
  )
  const nextVisit = snap.vet_visits
    .map((v) => v.next_visit_date)
    .filter((d): d is string => (daysUntil(d, now) ?? -1) >= 0)
    .sort()[0]

  // Attention pills: only genuinely actionable states earn color.
  const attention: Array<{ tone: 'red' | 'orange'; text: string }> = []
  for (const v of vaccines) {
    const s = dueStatus(v.next_due_at, now, 45)
    if (s === 'over')
      attention.push({
        tone: 'red',
        text: `${v.vaccine_name} ${dueCopy(v.next_due_at, now).toLowerCase()}`,
      })
    else if (s === 'soon')
      attention.push({
        tone: 'orange',
        text: `${v.vaccine_name} ${dueCopy(v.next_due_at, now).toLowerCase()}`,
      })
  }
  for (const m of activeMeds) {
    const s = dueStatus(m.refill_due_at, now, 14)
    if (s === 'over' || s === 'soon')
      attention.push({
        tone: s === 'over' ? 'red' : 'orange',
        text: `${m.drug_name} refill ${dueCopy(m.refill_due_at, now).toLowerCase()}`,
      })
  }

  // Health markers grouped by type, newest first; weight-style history with deltas.
  const markerGroups = new Map<string, typeof snap.health_markers>()
  for (const hm of snap.health_markers) {
    const list = markerGroups.get(hm.marker_type) ?? []
    list.push(hm)
    markerGroups.set(hm.marker_type, list)
  }
  for (const list of markerGroups.values())
    list.sort(
      (a, b) => (parse(b.recorded_at)?.getTime() ?? 0) - (parse(a.recorded_at)?.getTime() ?? 0)
    )

  const meta = [
    snap.pet.species,
    snap.pet.breed,
    petAge(snap.pet.dob, now),
    snap.pet.dob ? `born ${fmt(snap.pet.dob)}` : null,
  ].filter(Boolean) as string[]

  return (
    <>
      <header className="rec-head">
        <h1>
          {snap.pet.name}
          <span className="punct">.</span>
        </h1>
        <p className="rec-meta">
          {meta.map((m, i) => (
            <span key={m}>
              {i > 0 && <span className="sep">·</span>}
              {m}
            </span>
          ))}
        </p>
        {updatedAt && (
          <p className="rec-sync" style={{ marginTop: 6 }}>
            Synced from the iOS app · {fmt(new Date(updatedAt).toISOString())}
          </p>
        )}
        {attention.length > 0 && (
          <div className="attention">
            {attention.map((a) => (
              <span key={a.text} className={`pill ${a.tone}`}>
                <span className="dot" />
                {a.text}
              </span>
            ))}
          </div>
        )}
      </header>

      {activeMeds.length + pastMeds.length > 0 && (
        <section>
          <SectionHead title="Medications" aside={`${activeMeds.length} active`} />
          {activeMeds.map((m) => {
            const last = m.dose_logs
              .map((d) => d.given_at)
              .sort()
              .at(-1)
            const refill = dueStatus(m.refill_due_at, now, 14)
            return (
              <div
                key={m.id}
                className="med"
                style={{ background: 'var(--paper)', border: '1px solid var(--rule)' }}
              >
                <div className="med-top">
                  <div>
                    <div className="med-name">
                      {m.drug_name} <small>{m.dosage}</small>
                    </div>
                    <div className="med-dose">
                      {m.frequency}
                      {m.schedule_time ? ` · ${m.schedule_time}` : ''}
                      {m.veterinarian ? ` · ${m.veterinarian}` : ''}
                    </div>
                  </div>
                  {(refill === 'over' || refill === 'soon') && (
                    <span className={`pill ${refill === 'over' ? 'red' : 'orange'}`}>
                      <span className="dot" />
                      refill {fmtShort(m.refill_due_at)}
                    </span>
                  )}
                </div>
                <div className="med-ref">
                  Last given <b>{fmt(last)}</b> · {m.dose_logs.length} dose
                  {m.dose_logs.length === 1 ? '' : 's'} logged
                </div>
              </div>
            )
          })}
          {pastMeds.length > 0 && (
            <details className="past-meds panel" style={{ marginTop: 6 }}>
              <summary>Past medications ({pastMeds.length})</summary>
              {pastMeds.map((m) => (
                <div key={m.id} className="row">
                  <span>
                    {m.drug_name} · {m.dosage}
                  </span>
                  <span className="d">
                    {fmtShort(m.started_at)} – {fmtShort(m.ended_at)}
                  </span>
                </div>
              ))}
            </details>
          )}
        </section>
      )}

      {vaccines.length > 0 && (
        <section>
          <SectionHead title="Vaccinations" aside={`${vaccines.length} on record`} />
          <div className="panel">
            <div className="rpanel">
              {vaccines.map((v) => {
                const s = dueStatus(v.next_due_at, now, 45)
                const cls = s === 'over' ? 'over' : s === 'soon' ? 'soon' : 'ok'
                const statusText =
                  s === 'over' || s === 'soon'
                    ? `${dueCopy(v.next_due_at, now)} · next due ${fmt(v.next_due_at)}`
                    : v.next_due_at
                      ? `Next due ${fmt(v.next_due_at)}`
                      : 'No due date on record'
                return (
                  <div key={v.id} className={`vrow ${cls}`} style={{ cursor: 'default' }}>
                    <span className="dot" />
                    <div>
                      <div className="n">{v.vaccine_name}</div>
                      <div className="s">
                        {statusText}
                        {v.administered_by || v.veterinarian
                          ? ` · ${v.administered_by ?? v.veterinarian}`
                          : ''}
                      </div>
                    </div>
                    <div className="d">given {fmtShort(v.administered_at)}</div>
                  </div>
                )
              })}
            </div>
          </div>
        </section>
      )}

      {visits.length > 0 && (
        <section>
          <SectionHead title="Vet visits" aside={`${visits.length} on record`} />
          <div className="panel">
            {nextVisit && (
              <div className="next-visit-bar">
                <div>
                  <div className="nv-lab">Next visit</div>
                  <div className="nv-d">
                    {fmt(nextVisit)} · {dueCopy(nextVisit, now).replace('Due ', '')}
                  </div>
                </div>
              </div>
            )}
            <div className="rpanel">
              {visits.map((vv) => (
                <div key={vv.id} className="visit" style={{ cursor: 'default' }}>
                  <div className="vd">{fmtShort(vv.occurred_at)}</div>
                  <div>
                    <div className="vn">
                      {vv.reason || 'Visit'}
                      {vv.clinic_name ? ` · ${vv.clinic_name}` : ''}
                    </div>
                    {vv.diagnosis && <div className="vw">{vv.diagnosis}</div>}
                    {vv.recommendations.length > 0 && (
                      <ul className="sym-entries" style={{ marginTop: 6 }}>
                        {vv.recommendations.map((r) => (
                          <li key={r.id} style={{ gridTemplateColumns: '1fr' }}>
                            <span>{r.text}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
      )}

      {snap.symptom_episodes.length > 0 && (
        <section>
          <SectionHead title="Symptoms" />
          <div className="panel">
            {snap.symptom_episodes.map((ep) => (
              <div key={ep.id} className="sym">
                <div className="sym-top">
                  <h3>{ep.title || ep.category}</h3>
                  <span className={`pill ${ep.status === 'resolved' ? 'green' : 'orange'}`}>
                    <span className="dot" />
                    {ep.status}
                  </span>
                </div>
                <div className="sym-meta">
                  {ep.category} · started {fmt(ep.started_at)}
                  {ep.resolved_at ? ` · resolved ${fmt(ep.resolved_at)}` : ''}
                </div>
                {ep.entries.length > 0 && (
                  <ul className="sym-entries">
                    {ep.entries.map((e) => (
                      <li key={e.id}>
                        <span className="sd">{fmtShort(e.date)}</span>
                        <span>
                          <b>{e.severity}</b>
                          {e.note ? ` — ${e.note}` : ''}
                          {e.suspected_cause ? ` (suspected: ${e.suspected_cause})` : ''}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      {markerGroups.size > 0 && (
        <section>
          <SectionHead title="Health markers" />
          <div className="panel">
            {[...markerGroups.entries()].map(([type, list]) => {
              const latest = list[0]
              return (
                <div key={type} className="mgroup">
                  <div className="wt-big">
                    <div>
                      <div
                        className="s"
                        style={{ fontSize: 12, color: 'var(--ink-3)', marginBottom: 4 }}
                      >
                        {type}
                      </div>
                      <div className="wt-num" style={{ color: 'var(--ink)', fontSize: 36 }}>
                        {latest.value}
                        <small>{latest.unit}</small>
                      </div>
                    </div>
                  </div>
                  {list.length > 1 && (
                    <div className="wt-rows">
                      {list.map((hm, i) => {
                        const prev = list[i + 1]
                        const delta = prev ? hm.value - prev.value : null
                        return (
                          <div key={hm.id} className="row">
                            <span className="d">{fmt(hm.recorded_at)}</span>
                            <b>
                              {hm.value}
                              {hm.unit ? ` ${hm.unit}` : ''}
                            </b>
                            <span className="delta">
                              {delta === null
                                ? ''
                                : `${delta > 0 ? '+' : ''}${Math.round(delta * 10) / 10}`}
                            </span>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </section>
      )}

      {(snap.activity_logs?.length ?? 0) > 0 && (
        <section>
          <SectionHead title="Routine care" />
          <div className="panel">
            <div className="rpanel">
              {(snap.activity_logs ?? []).map((a) => {
                const s = dueStatus(a.next_due_at, now, 3)
                return (
                  <div
                    key={a.id}
                    className={`vrow ${s === 'over' ? 'soon' : 'ok'}`}
                    style={{ cursor: 'default' }}
                  >
                    <span
                      className="dot"
                      style={
                        s === 'ok' || s === 'none' ? { background: 'var(--ink-4)' } : undefined
                      }
                    />
                    <div>
                      <div className="n">{a.type_name}</div>
                      <div className="s">
                        {a.category} · last {fmt(a.performed_at)}
                        {durationMinutes(a.performed_at, a.ended_at) !== null
                          ? ` · ${durationMinutes(a.performed_at, a.ended_at)} min`
                          : ''}
                        {a.note ? ` · ${a.note}` : ''}
                      </div>
                    </div>
                    {a.next_due_at && <div className="d">next {fmtShort(a.next_due_at)}</div>}
                  </div>
                )
              })}
            </div>
          </div>
        </section>
      )}

      {(snap.diary?.length ?? 0) > 0 && (
        <section>
          <SectionHead title="Diary" aside="latest entries" />
          <div className="panel">
            {(snap.diary ?? []).map((e) => (
              <div key={e.id} className="drow">
                <span className="dd">{fmtShort(e.date)}</span>
                <div>
                  {e.note && <div className="dn">{e.note}</div>}
                  {e.photo_count > 0 && (
                    <div className="dp">
                      {e.photo_count} photo{e.photo_count === 1 ? '' : 's'} in the app
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {(snap.care_team?.length ?? 0) > 0 && (
        <section>
          <SectionHead title="Care team" />
          <div className="panel">
            {(snap.care_team ?? []).map((vet) => (
              <div key={vet.id} className="crow">
                <div className="cn">
                  {vet.name}
                  {vet.clinic && <small>{vet.clinic}</small>}
                </div>
                <div className="cc">
                  {vet.phone && <a href={`tel:${vet.phone.replace(/[^+\d]/g, '')}`}>{vet.phone}</a>}
                  {vet.phone && vet.email && ' · '}
                  {vet.email && <a href={`mailto:${vet.email}`}>{vet.email}</a>}
                  {vet.address && ` · ${vet.address}`}
                </div>
                {vet.notes && <div className="cc">{vet.notes}</div>}
              </div>
            ))}
          </div>
        </section>
      )}
    </>
  )
}

export function SnapshotFooter({ snapshot }: { snapshot: MirrorSnapshot }) {
  return (
    <footer className="footer">
      <span>Mirrored read-only from the iOS app</span>
      <span className="mono">
        snapshot v{snapshot.schema_version} · {fmt(snapshot.generated_at)}
      </span>
    </footer>
  )
}
