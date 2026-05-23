'use client'
import { Topbar } from './Topbar'
import { usePetData } from '@/hooks/usePetData'
import { useMutation } from 'convex/react'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'

type ReminderSourceType = 'vaccination' | 'medication' | 'vet_visit'

interface Reminder {
  id: string
  icon: string
  title: string
  subtitle: string
  dueAt: string
  daysAway: number
  urgency: 'over' | 'soon' | 'upcoming'
  sourceType: ReminderSourceType
  sourceRecordId: string
}

function daysFromNow(iso: string): number {
  return Math.ceil((new Date(iso).getTime() - Date.now()) / (24 * 60 * 60 * 1000))
}

function fmt(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

function urgency(days: number): 'over' | 'soon' | 'upcoming' {
  if (days < 0)  return 'over'
  if (days <= 30) return 'soon'
  return 'upcoming'
}

const urgencyStyles = {
  over:     { border: 'var(--red)',    bg: 'var(--red-bg)',    label: 'Overdue',    labelColor: 'var(--red)'    },
  soon:     { border: 'var(--orange)', bg: 'var(--orange-bg)', label: 'Due soon',   labelColor: 'var(--orange)' },
  upcoming: { border: 'var(--rule)',   bg: 'var(--paper)',     label: 'Upcoming',   labelColor: 'var(--ink-3)'  },
}

function ReminderCard({ r, onDone }: { r: Reminder; onDone: () => void }) {
  const s = urgencyStyles[r.urgency]
  const dayLabel = r.daysAway < 0
    ? `${Math.abs(r.daysAway)} day${Math.abs(r.daysAway) !== 1 ? 's' : ''} overdue`
    : r.daysAway === 0 ? 'Today'
    : `In ${r.daysAway} day${r.daysAway !== 1 ? 's' : ''}`

  return (
    <div style={{
      background: s.bg, border: `1px solid ${s.border}`, borderRadius: 13,
      padding: '16px 18px', display: 'flex', alignItems: 'center', gap: 16, marginBottom: 8,
    }}>
      <div style={{ fontSize: 28, flexShrink: 0 }}>{r.icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 600, fontSize: 15, color: 'var(--ink)', marginBottom: 2 }}>{r.title}</div>
        <div style={{ fontSize: 13, color: 'var(--ink-3)' }}>{r.subtitle}</div>
      </div>
      <div style={{ textAlign: 'right', flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: s.labelColor, textTransform: 'uppercase',
                      letterSpacing: '0.05em' }}>{s.label}</div>
        <div style={{ fontSize: 13, color: 'var(--ink-2)', fontWeight: 500 }}>{dayLabel}</div>
        <div style={{ fontSize: 11, color: 'var(--ink-3)' }}>{fmt(r.dueAt)}</div>
        <button
          type="button"
          onClick={onDone}
          style={{
            marginTop: 4, padding: '4px 12px', fontSize: 12, fontWeight: 600,
            borderRadius: 8, border: '1px solid var(--rule)', background: 'var(--paper)',
            color: 'var(--ink-2)', cursor: 'pointer',
          }}
        >
          Mark done
        </button>
      </div>
    </div>
  )
}

export function RemindersPage() {
  const { pet, vaccinations, medications, vetVisits, loading } = usePetData()
  const ackVax   = useMutation(api.medical.acknowledgeVaccinationReminder)
  const ackMed   = useMutation(api.medical.acknowledgeMedicationRefill)
  const ackVisit = useMutation(api.medical.acknowledgeVetVisitReminder)

  if (loading) {
    return <div style={{ minHeight: '100dvh', display: 'grid', placeItems: 'center', color: 'var(--ink-3)', fontSize: 14 }}>Loading…</div>
  }
  if (!pet) return null

  const reminders: Reminder[] = []

  vaccinations.forEach(v => {
    if (!v.nextDueAt) return
    const days = daysFromNow(v.nextDueAt)
    if (days > 90) return
    reminders.push({
      id: v._id, icon: '💉', urgency: urgency(days), daysAway: days, dueAt: v.nextDueAt,
      title: `${v.vaccineName} vaccine`,
      subtitle: `Last given ${new Date(v.administeredAt).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}`,
      sourceType: 'vaccination',
      sourceRecordId: v._id,
    })
  })

  medications.filter(m => !m.endedAt && m.refillDueAt).forEach(m => {
    const days = daysFromNow(m.refillDueAt!)
    if (days > 90) return
    reminders.push({
      id: m._id, icon: '💊', urgency: urgency(days), daysAway: days, dueAt: m.refillDueAt!,
      title: `${m.drugName} refill`,
      subtitle: m.dosage || 'Medication refill needed',
      sourceType: 'medication',
      sourceRecordId: m._id,
    })
  })

  vetVisits.filter(v => v.nextVisitDate).forEach(v => {
    const days = daysFromNow(v.nextVisitDate!)
    if (days > 90) return
    reminders.push({
      id: v._id + '-next', icon: '🩺', urgency: urgency(days), daysAway: days, dueAt: v.nextVisitDate!,
      title: 'Vet visit',
      subtitle: v.clinicName || 'Scheduled follow-up',
      sourceType: 'vet_visit',
      sourceRecordId: v._id,
    })
  })

  reminders.sort((a, b) => a.daysAway - b.daysAway)

  const handleDone = (r: Reminder) => {
    if (r.sourceType === 'vaccination') {
      ackVax({ vaccinationId: r.sourceRecordId as Id<'vaccinations'> })
    } else if (r.sourceType === 'medication') {
      ackMed({ medicationId: r.sourceRecordId as Id<'medications'> })
    } else {
      ackVisit({ vetVisitId: r.sourceRecordId as Id<'vetVisits'> })
    }
  }

  const overdue  = reminders.filter(r => r.urgency === 'over')
  const soon     = reminders.filter(r => r.urgency === 'soon')
  const upcoming = reminders.filter(r => r.urgency === 'upcoming')

  return (
    <>
      <Topbar pet={pet} />
      <div className="page">
        <div className="section-h">
          <h2 className="serif">Reminders</h2>
          <div className="sh-aside">{reminders.length} pending</div>
        </div>

        {reminders.length === 0 ? (
          <div style={{
            background: 'var(--paper)', border: '1px solid var(--rule)', borderRadius: 14,
            padding: '48px 24px', textAlign: 'center', color: 'var(--ink-3)',
          }}>
            <div style={{ fontSize: 36, marginBottom: 12 }}>✅</div>
            <div style={{ fontWeight: 600, color: 'var(--ink-2)', fontSize: 16, marginBottom: 6 }}>All caught up.</div>
            <div style={{ fontSize: 14 }}>Nothing due in the next 90 days.</div>
          </div>
        ) : (
          <>
            {overdue.length > 0 && (
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--red)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Overdue — {overdue.length}</div>
                {overdue.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
            {soon.length > 0 && (
              <div style={{ marginBottom: 24 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Due soon — {soon.length}</div>
                {soon.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
            {upcoming.length > 0 && (
              <div style={{ marginBottom: 48 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--ink-3)', textTransform: 'uppercase',
                              letterSpacing: '0.07em', marginBottom: 10 }}>Upcoming — {upcoming.length}</div>
                {upcoming.map(r => <ReminderCard key={r.id} r={r} onDone={() => handleDone(r)} />)}
              </div>
            )}
          </>
        )}
      </div>
    </>
  )
}
