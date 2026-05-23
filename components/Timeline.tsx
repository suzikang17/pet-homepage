'use client'

import { useState } from 'react'

type Filter = 'all' | 'vet' | 'vax' | 'med' | 'symp' | 'photo'

interface ConvexEvent {
  _id: string
  occurredAt: string
  eventType: string
  title?: string
  notes?: string
  source: string
}

const filters: { key: Filter; label: string }[] = [
  { key: 'all',   label: 'All' },
  { key: 'vet',   label: 'Vet' },
  { key: 'vax',   label: 'Vaccines' },
  { key: 'med',   label: 'Meds' },
  { key: 'symp',  label: 'Symptoms' },
  { key: 'photo', label: 'Photos' },
]

function eventColor(type: string): string {
  if (type.includes('vet') || type.includes('visit')) return 'blue'
  if (type.includes('vax') || type.includes('vacc')) return 'blue'
  if (type.includes('med') || type.includes('rx'))   return 'orange'
  if (type.includes('weight'))                        return 'gray'
  return 'green'
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

export function Timeline({ events }: { events: ConvexEvent[] }) {
  const [active, setActive] = useState<Filter>('all')

  return (
    <main>
      <div className="section-h">
        <h2 className="serif">Timeline</h2>
        <div className="sh-aside">{events.length} entries</div>
      </div>

      <div className="filters" role="tablist">
        {filters.map(f => (
          <button key={f.key}
            className={active === f.key ? 'active' : ''}
            onClick={() => setActive(f.key)}
            role="tab" aria-selected={active === f.key}>
            {f.label}
          </button>
        ))}
      </div>

      {events.length === 0 ? (
        <div style={{
          background: 'var(--paper)', border: '1px solid var(--rule)',
          borderRadius: 14, padding: '40px 24px', textAlign: 'center', color: 'var(--ink-3)',
        }}>
          <div style={{ fontSize: 32, marginBottom: 12 }}>📓</div>
          <div style={{ fontWeight: 600, color: 'var(--ink-2)', marginBottom: 6 }}>Your timeline is waiting.</div>
          <div style={{ fontSize: 14 }}>Drop a note about today using the button below.</div>
        </div>
      ) : (
        events.map(ev => (
          <div className="day-group" key={ev._id}>
            <div className="day-h">{formatDate(ev.occurredAt)}</div>
            <article className={`event ${eventColor(ev.eventType)}`}>
              <div className="event-ic">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
                  stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>
                </svg>
              </div>
              <div>
                <span className="event-tag">{ev.eventType}</span>
                <h3>{ev.title || ev.eventType}</h3>
                {ev.notes && <p>{ev.notes}</p>}
                <div className="event-meta">
                  <span>via {ev.source}</span>
                </div>
              </div>
            </article>
          </div>
        ))
      )}
    </main>
  )
}
