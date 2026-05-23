'use client'
import { useState } from 'react'
import { useMutation } from 'convex/react'
import { api } from '@/convex/_generated/api'
import { Topbar } from './Topbar'
import { Subnav } from './Subnav'
import { usePetData } from '@/hooks/usePetData'

type Tab = 'vax' | 'meds' | 'visits' | 'weight'

const TABS = [
  { key: 'vax',    label: 'Vaccines'  },
  { key: 'meds',   label: 'Meds'      },
  { key: 'visits', label: 'Visits'    },
  { key: 'weight', label: 'Weight'    },
]

function StatusBadge({ status }: { status: 'ok' | 'soon' | 'over' }) {
  const map = {
    ok:   { label: 'Up to date', color: 'var(--green)',  bg: 'var(--green-bg)'  },
    soon: { label: 'Due soon',   color: 'var(--orange)', bg: 'var(--orange-bg)' },
    over: { label: 'Overdue',    color: 'var(--red)',    bg: 'var(--red-bg)'    },
  }
  const s = map[status]
  return (
    <span style={{ background: s.bg, color: s.color, padding: '3px 9px', borderRadius: 6,
                   fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em' }}>
      {s.label}
    </span>
  )
}

function vaxStatus(nextDueAt?: string): 'ok' | 'soon' | 'over' {
  if (!nextDueAt) return 'ok'
  const diff = new Date(nextDueAt).getTime() - Date.now()
  if (diff < 0) return 'over'
  if (diff < 42 * 24 * 60 * 60 * 1000) return 'soon'
  return 'ok'
}

function fmt(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function EmptyPanel({ label }: { label: string }) {
  return (
    <div style={{ background: 'var(--paper)', border: '1px solid var(--rule)', borderRadius: 12,
                  padding: '28px 20px', color: 'var(--ink-3)', fontSize: 14, textAlign: 'center',
                  marginBottom: 16 }}>
      {label}
    </div>
  )
}

function SectionHeader({ title, count }: { title: string; count: number }) {
  return (
    <div className="section-h" style={{ marginBottom: 16 }}>
      <h2 className="serif">{title}</h2>
      <div className="sh-aside">{count} {count === 1 ? 'record' : 'records'}</div>
    </div>
  )
}

function AddVaxForm({ petId, onDone }: { petId: string; onDone: () => void }) {
  const createVaccination = useMutation(api.medical.createVaccination)
  const [name, setName]     = useState('')
  const [given, setGiven]   = useState(new Date().toISOString().slice(0, 10))
  const [nextDue, setNextDue] = useState('')
  const [saving, setSaving] = useState(false)

  const submit = async () => {
    if (!name.trim()) return
    setSaving(true)
    await createVaccination({
      petId: petId as any,
      vaccineName: name.trim(),
      administeredAt: given,
      nextDueAt: nextDue || undefined,
    })
    setName(''); setGiven(new Date().toISOString().slice(0, 10)); setNextDue('')
    setSaving(false)
    onDone()
  }

  return (
    <div style={{ background: 'var(--paper)', border: '1px solid var(--rule)', borderRadius: 12,
                  padding: '20px', marginBottom: 16 }}>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 14 }}>Add vaccine</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <input
          className="ob-input"
          placeholder="Vaccine name (e.g. Rabies, DHPP)"
          value={name}
          onChange={e => setName(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && submit()}
        />
        <div style={{ display: 'flex', gap: 10 }}>
          <label style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4, fontSize: 12, color: 'var(--ink-3)' }}>
            Date given
            <input className="ob-input" type="date" value={given} onChange={e => setGiven(e.target.value)} />
          </label>
          <label style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4, fontSize: 12, color: 'var(--ink-3)' }}>
            Next due (optional)
            <input className="ob-input" type="date" value={nextDue} onChange={e => setNextDue(e.target.value)} />
          </label>
        </div>
        <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
          <button type="button" onClick={onDone}
            style={{ padding: '8px 16px', borderRadius: 8, border: '1px solid var(--rule)',
                     background: 'none', cursor: 'pointer', fontSize: 13 }}>
            Cancel
          </button>
          <button type="button" onClick={submit} disabled={saving || !name.trim()}
            style={{ padding: '8px 16px', borderRadius: 8, border: 'none',
                     background: 'var(--blue)', color: 'white', cursor: 'pointer',
                     fontSize: 13, fontWeight: 500, opacity: saving ? 0.6 : 1 }}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  )
}

export function RecordsPage() {
  const { pet, weightLogs, medications, vaccinations, vetVisits, loading, petId } = usePetData()
  const [tab, setTab] = useState<Tab>('vax')
  const [addingVax, setAddingVax] = useState(false)

  if (loading) {
    return <div style={{ minHeight: '100dvh', display: 'grid', placeItems: 'center', color: 'var(--ink-3)', fontSize: 14 }}>Loading…</div>
  }
  if (!pet || !petId) return null

  const activeMeds = medications.filter(m => !m.endedAt)
  const pastMeds   = medications.filter(m => !!m.endedAt)

  return (
    <>
      <Topbar pet={pet} />
      <Subnav items={TABS} active={tab} onChange={k => { setTab(k as Tab); setAddingVax(false) }} />
      <div className="page" style={{ paddingTop: 24 }}>

        {tab === 'vax' && (
          <>
            <SectionHeader title="Vaccinations" count={vaccinations.length} />
            {addingVax
              ? <AddVaxForm petId={petId} onDone={() => setAddingVax(false)} />
              : (
                <button type="button" onClick={() => setAddingVax(true)}
                  style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 16,
                           padding: '8px 14px', borderRadius: 8, border: '1px solid var(--rule)',
                           background: 'none', cursor: 'pointer', fontSize: 13, color: 'var(--ink-2)' }}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6"><path d="M12 5v14M5 12h14"/></svg>
                  Add vaccine
                </button>
              )
            }
            {vaccinations.length === 0
              ? <EmptyPanel label="No vaccinations logged yet. Add one above or forward a vet receipt to your ingest email." />
              : (
                <div className="panel">
                  <div className="rpanel flush">
                    {vaccinations.map(v => {
                      const st = vaxStatus(v.nextDueAt)
                      return (
                        <div key={v._id} className={`vrow ${st}`} style={{ cursor: 'default' }}>
                          <div className="dot"/>
                          <div>
                            <div className="n">{v.vaccineName}</div>
                            <div className="s">Given {fmt(v.administeredAt)}</div>
                          </div>
                          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                            <StatusBadge status={st}/>
                            {v.nextDueAt && <div style={{ fontSize: 11, color: 'var(--ink-3)' }}>Due {fmt(v.nextDueAt)}</div>}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )
            }
          </>
        )}

        {tab === 'meds' && (
          <>
            <SectionHeader title="Medications" count={medications.length} />
            {activeMeds.length === 0 && pastMeds.length === 0
              ? <EmptyPanel label="No medications logged yet." />
              : (
                <>
                  {activeMeds.length > 0 && (
                    <>
                      <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--ink-3)', textTransform: 'uppercase',
                                    letterSpacing: '0.06em', marginBottom: 8 }}>Active</div>
                      {activeMeds.map(m => (
                        <div key={m._id} className="med">
                          <div className="med-top">
                            <div>
                              <div className="med-name">{m.drugName}</div>
                              {m.dosage && <div className="med-dose">{m.dosage}{m.frequency ? ` · ${m.frequency}` : ''}</div>}
                            </div>
                            {m.refillDueAt && (
                              <div style={{ fontSize: 12, color: 'var(--orange)', fontWeight: 500, textAlign: 'right' }}>
                                Refill by<br/>{fmt(m.refillDueAt)}
                              </div>
                            )}
                          </div>
                          <div className="med-ref">Started <b>{fmt(m.startedAt)}</b></div>
                        </div>
                      ))}
                    </>
                  )}
                  {pastMeds.length > 0 && (
                    <>
                      <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--ink-3)', textTransform: 'uppercase',
                                    letterSpacing: '0.06em', margin: '16px 0 8px' }}>Past</div>
                      {pastMeds.map(m => (
                        <div key={m._id} className="med" style={{ opacity: 0.65 }}>
                          <div className="med-top">
                            <div>
                              <div className="med-name">{m.drugName}</div>
                              {m.dosage && <div className="med-dose">{m.dosage}</div>}
                            </div>
                          </div>
                          <div className="med-ref">
                            <b>{fmt(m.startedAt)}</b> — <b>{m.endedAt ? fmt(m.endedAt) : ''}</b>
                          </div>
                        </div>
                      ))}
                    </>
                  )}
                </>
              )
            }
          </>
        )}

        {tab === 'visits' && (
          <>
            <SectionHeader title="Vet Visits" count={vetVisits.length} />
            {vetVisits.length === 0
              ? <EmptyPanel label="No vet visits logged yet. Forward a vet receipt to your ingest email to add one." />
              : (
                <div className="panel">
                  <div className="rpanel flush">
                    {vetVisits.map(v => (
                      <div key={v._id} className="visit">
                        <div className="vd">{fmt(v.occurredAt)}</div>
                        <div>
                          <div className="vn">{v.reason || 'Vet visit'}</div>
                          <div className="vw">
                            {[v.clinicName, v.vetName].filter(Boolean).join(' · ') || 'No clinic details'}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )
            }
          </>
        )}

        {tab === 'weight' && (
          <>
            <SectionHeader title="Weight History" count={weightLogs.length} />
            {weightLogs.length === 0
              ? <EmptyPanel label="No weight entries yet. Log one using the button below." />
              : (
                <div className="panel">
                  <div className="wt-rows">
                    {weightLogs.map((w, i) => {
                      const prev = weightLogs[i + 1]
                      const delta = prev ? w.weightKg - prev.weightKg : null
                      return (
                        <div key={w._id} className="row">
                          <div className="d">{fmt(w.recordedAt)}</div>
                          <b>{w.weightKg.toFixed(1)} kg</b>
                          <div className={`delta ${delta === null ? '' : delta > 0 ? 'up' : 'down'}`}>
                            {delta !== null ? (delta > 0 ? '+' : '') + delta.toFixed(1) : '—'}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )
            }
          </>
        )}

      </div>
    </>
  )
}
