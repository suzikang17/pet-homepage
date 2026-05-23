"use client";

import { useState } from "react";

type Tab = "vax" | "meds" | "visits" | "weight";

interface WeightLog   { _id: string; recordedAt: string; weightKg: number }
interface Medication  { _id: string; drugName: string; dosage?: string; frequency?: string; refillDueAt?: string; endedAt?: string }
interface Vaccination { _id: string; vaccineName: string; administeredAt: string; nextDueAt?: string }
interface VetVisit    { _id: string; occurredAt: string; clinicName?: string; vetName?: string; reason?: string }

interface SidebarProps {
  weightLogs:   WeightLog[]
  medications:  Medication[]
  vaccinations: Vaccination[]
  vetVisits:    VetVisit[]
}

function vaxStatus(v: Vaccination): 'ok' | 'soon' | 'over' {
  if (!v.nextDueAt) return 'ok'
  const diff = new Date(v.nextDueAt).getTime() - Date.now()
  if (diff < 0) return 'over'
  if (diff < 42 * 24 * 60 * 60 * 1000) return 'soon' // 6 weeks
  return 'ok'
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function medRingValues(refillDueAt?: string): { remaining: number; total: number } {
  const total = 30
  if (!refillDueAt) return { remaining: total, total }
  const diff = new Date(refillDueAt).getTime() - Date.now()
  const days = Math.max(0, Math.min(total, Math.ceil(diff / (24 * 60 * 60 * 1000))))
  return { remaining: days, total }
}

function MedRing({
  remaining,
  total,
  color,
}: {
  remaining: number;
  total: number;
  color: "blue" | "green";
}) {
  const pct = (remaining / total) * 100;
  const trackColor =
    color === "blue" ? "oklch(92% 0.04 240)" : "oklch(92% 0.04 160)";
  const strokeColor = color === "blue" ? "var(--blue)" : "var(--green)";
  return (
    <div className="ring">
      <svg viewBox="0 0 36 36" width="44" height="44">
        <circle
          cx="18"
          cy="18"
          r="15"
          fill="none"
          stroke={trackColor}
          strokeWidth="3"
        />
        <circle
          cx="18"
          cy="18"
          r="15"
          fill="none"
          stroke={strokeColor}
          strokeWidth="3"
          pathLength={100}
          strokeDasharray={`${pct} 100`}
          transform="rotate(-90 18 18)"
          strokeLinecap="round"
        />
      </svg>
      <span>{remaining}</span>
    </div>
  );
}


export function RecordsSidebar({ weightLogs, medications, vaccinations, vetVisits }: SidebarProps) {
  const [tab, setTab] = useState<Tab>("vax");

  const activeMeds = medications.filter(m => !m.endedAt)

  return (
    <aside className="side">
      <div className="panel">
        <div className="rtabs" role="tablist">
          <button
            className={tab === "vax" ? "active" : ""}
            onClick={() => setTab("vax")}
            role="tab"
            aria-selected={tab === "vax"}
          >
            Vaccines
          </button>
          <button
            className={tab === "meds" ? "active" : ""}
            onClick={() => setTab("meds")}
            role="tab"
            aria-selected={tab === "meds"}
          >
            Meds
          </button>
          <button
            className={tab === "visits" ? "active" : ""}
            onClick={() => setTab("visits")}
            role="tab"
            aria-selected={tab === "visits"}
          >
            Visits
          </button>
          <button
            className={tab === "weight" ? "active" : ""}
            onClick={() => setTab("weight")}
            role="tab"
            aria-selected={tab === "weight"}
          >
            Weight
          </button>
        </div>

        {tab === "vax" && (
          <div className="rpanel">
            {vaccinations.length === 0 ? (
              <div style={{ padding: '16px', color: 'var(--ink-3)', fontSize: 14 }}>No vaccinations logged yet.</div>
            ) : (
              vaccinations.map((v) => {
                const status = vaxStatus(v)
                const dueDateStr = v.nextDueAt ? formatDate(v.nextDueAt) : '—'
                const sub = status === 'over' ? 'Overdue' : status === 'soon' ? `Due ${dueDateStr}` : 'Up to date'
                return (
                  <div className={`vrow ${status}`} key={v._id}>
                    <div className="dot"></div>
                    <div>
                      <div className="n">{v.vaccineName}</div>
                      <div className="s">{sub}</div>
                    </div>
                    <div className="d">{formatDate(v.administeredAt)}</div>
                  </div>
                )
              })
            )}
          </div>
        )}

        {tab === "meds" && (
          <div className="rpanel">
            {activeMeds.length === 0 ? (
              <div style={{ padding: '16px', color: 'var(--ink-3)', fontSize: 14 }}>No active medications logged.</div>
            ) : (
              activeMeds.map((m, i) => {
                const { remaining, total } = medRingValues(m.refillDueAt)
                const color: 'blue' | 'green' = i % 2 === 0 ? 'blue' : 'green'
                const doseStr = [m.dosage, m.frequency].filter(Boolean).join(' · ')
                return (
                  <div className="med" key={m._id}>
                    <div className="med-top">
                      <div>
                        <div className="med-name serif">
                          {m.drugName} {m.dosage && <small>{m.dosage}</small>}
                        </div>
                        {doseStr && <div className="med-dose">{doseStr}</div>}
                      </div>
                      <MedRing remaining={remaining} total={total} color={color} />
                    </div>
                    <div className="med-ref">
                      {remaining} of {total} days left
                      {m.refillDueAt && <> · refill by <b>{formatDate(m.refillDueAt)}</b></>}
                    </div>
                  </div>
                )
              })
            )}
          </div>
        )}

        {tab === "visits" && (
          <div className="rpanel flush">
            <div style={{ padding: "4px 8px 8px" }}>
              {vetVisits.length === 0 ? (
                <div style={{ padding: '16px', color: 'var(--ink-3)', fontSize: 14 }}>No vet visits logged yet.</div>
              ) : (
                vetVisits.map((v) => (
                  <div className="visit" key={v._id}>
                    <div className="vd">{formatDate(v.occurredAt)}</div>
                    <div>
                      <div className="vn">{v.reason || 'Visit'}</div>
                      <div className="vw">{[v.vetName, v.clinicName].filter(Boolean).join(' · ') || '—'}</div>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        )}

        {tab === "weight" && (
          <div className="rpanel flush">
            {weightLogs.length === 0 ? (
              <div style={{ padding: '16px', color: 'var(--ink-3)', fontSize: 14 }}>No weight logs yet.</div>
            ) : (
              <>
                <div className="wt-big">
                  <div className="wt-num serif">
                    {weightLogs[0].weightKg.toFixed(1)}<small>kg</small>
                  </div>
                  <div className="wt-band">Latest recorded weight</div>
                </div>
                <div className="wt-rows">
                  {weightLogs.map((w) => (
                    <div className="row" key={w._id}>
                      <span className="d">{formatDate(w.recordedAt)}</span>
                      <b>{w.weightKg.toFixed(1)} kg</b>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
        )}
      </div>

    </aside>
  );
}
