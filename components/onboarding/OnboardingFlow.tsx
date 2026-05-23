'use client'

import { useState, useRef, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useMutation, useQuery } from 'convex/react'
import { api } from '@/convex/_generated/api'

type StepId =
  | 'welcome' | 'name' | 'species' | 'breed' | 'birthday' | 'sex' | 'weight'
  | 'photo' | 'vet' | 'meds' | 'conditions' | 'chip' | 'vax' | 'goals'
  | 'notify' | 'account' | 'done'

interface StepDef {
  id: StepId
  phase: 'intro' | 'pet' | 'care' | 'plan'
  optional: boolean
}

interface Med { id: string; name: string; dose: string }

interface OBValues {
  unit: 'kg' | 'lb'
  name?: string
  species?: 'dog' | 'cat' | 'other'
  breed?: string
  birthday?: string
  ageGuess?: string
  sex?: 'f' | 'm'
  fixed?: boolean
  weight?: string
  photo?: boolean
  clinic?: string
  clinicPhone?: string
  vet?: string
  meds?: Med[]
  conditions?: string[]
  notes?: string
  chip?: string
  chipReg?: boolean
  vax?: Record<string, boolean>
  goals?: string[]
  notify?: Record<string, boolean>
  email?: string
  password?: string
}

const STEPS: StepDef[] = [
  { id: 'welcome',    phase: 'intro', optional: false },
  { id: 'name',       phase: 'pet',   optional: false },
  { id: 'species',    phase: 'pet',   optional: false },
  { id: 'breed',      phase: 'pet',   optional: true  },
  { id: 'birthday',   phase: 'pet',   optional: false },
  { id: 'sex',        phase: 'pet',   optional: false },
  { id: 'weight',     phase: 'pet',   optional: false },
  { id: 'photo',      phase: 'pet',   optional: true  },
  { id: 'vet',        phase: 'care',  optional: true  },
  { id: 'meds',       phase: 'care',  optional: true  },
  { id: 'conditions', phase: 'care',  optional: true  },
  { id: 'chip',       phase: 'care',  optional: true  },
  { id: 'vax',        phase: 'care',  optional: true  },
  { id: 'goals',      phase: 'plan',  optional: true  },
  { id: 'notify',     phase: 'plan',  optional: false },
  { id: 'account',    phase: 'plan',  optional: false },
  { id: 'done',       phase: 'plan',  optional: false },
]

// ─── Icons ────────────────────────────────────────────────────────────────────

function ArrowR() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6"/>
    </svg>
  )
}

function ArrowL() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M19 12H5M11 6l-6 6 6 6"/>
    </svg>
  )
}

function Check({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
  )
}

function Camera() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14.5 4l1.5 2H20a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l1.5-2z"/>
      <circle cx="12" cy="13" r="4"/>
    </svg>
  )
}

// ─── Photo upload ──────────────────────────────────────────────────────────────

function PhotoStepUpload({ v, set }: { v: OBValues; set: (k: keyof OBValues, val: OBValues[keyof OBValues]) => void }) {
  const [state, setState] = useState<'idle' | 'uploading' | 'done'>(v.photo ? 'done' : 'idle')
  const [pct, setPct] = useState(0)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const start = () => {
    setState('uploading')
    setPct(0)
    let p = 0
    timerRef.current = setInterval(() => {
      p += 8 + Math.random() * 14
      if (p >= 100) {
        clearInterval(timerRef.current!)
        setPct(100)
        setTimeout(() => { set('photo', true); setState('done') }, 220)
      } else {
        setPct(p)
      }
    }, 130)
  }

  useEffect(() => () => { if (timerRef.current) clearInterval(timerRef.current) }, [])

  const R = 22, C = 50
  const circ = 2 * Math.PI * R
  const offset = circ * (1 - pct / 100)

  if (state === 'uploading') {
    return (
      <div className="ob-photo-drop circle is-uploading" style={{ margin: '8px 0 0' }}>
        <div className="progress-ring">
          <svg viewBox={`0 0 ${C} ${C}`}>
            <circle cx={C / 2} cy={C / 2} r={R} className="track" strokeWidth="3" fill="none"/>
            <circle cx={C / 2} cy={C / 2} r={R} className="fill" strokeWidth="3" fill="none"
              strokeDasharray={circ} strokeDashoffset={offset}/>
          </svg>
          <span className="pct">{Math.min(99, Math.round(pct))}%</span>
        </div>
      </div>
    )
  }

  if (state === 'done' && v.photo) {
    return (
      <div className="ob-photo-drop has-photo circle"
        style={{ backgroundImage: 'linear-gradient(135deg, oklch(85% 0.08 50), oklch(70% 0.13 30))', margin: '8px 0 0' }}>
        <div className="photo-checkmark"><Check size={12}/></div>
        <div style={{ margin: 'auto', fontSize: 80, opacity: 0.55 }}>🐕</div>
        <div className="photo-actions">
          <button type="button" className="photo-pill"
            onClick={() => { set('photo', false); setState('idle') }}>Replace</button>
        </div>
      </div>
    )
  }

  return (
    <button type="button" className="ob-photo-drop circle" onClick={start} style={{ margin: '8px 0 0' }}>
      <div className="icon"><Camera/></div>
      <div className="label">Add a photo</div>
    </button>
  )
}

// ─── Step content (all steps except welcome / photo / done) ───────────────────

type Setter = (k: keyof OBValues, val: OBValues[keyof OBValues]) => void

function StepContent({ stepId, v, set }: { stepId: StepId; v: OBValues; set: Setter }) {
  const defaultNotify = { meds: true, vet: true, vax: true, digest: true, walk: false }

  switch (stepId) {

    case 'name':
      return (
        <div className="ob-field">
          <input className="ob-input big" autoFocus placeholder="Sandy"
            value={v.name || ''} onChange={e => set('name', e.target.value)}/>
        </div>
      )

    case 'species':
      return (
        <div className="ob-tiles cols-3">
          {([
            { id: 'dog'   as const, emoji: '🐕', name: 'Dog',   sub: 'Woofs' },
            { id: 'cat'   as const, emoji: '🐈', name: 'Cat',   sub: 'Meows' },
            { id: 'other' as const, emoji: '🐾', name: 'Other', sub: 'Bird, bun…' },
          ]).map(o => (
            <button key={o.id} type="button"
              className={'ob-tile ' + (v.species === o.id ? 'sel' : '')}
              onClick={() => set('species', o.id)}>
              <div className="ob-tile-emoji">{o.emoji}</div>
              <div className="ob-tile-name">{o.name}</div>
              <div className="ob-tile-sub">{o.sub}</div>
            </button>
          ))}
        </div>
      )

    case 'breed':
      return (
        <div className="ob-field">
          <label className="ob-label">Breed (or mix)</label>
          <input className="ob-input" placeholder="Golden Retriever"
            value={v.breed || ''} onChange={e => set('breed', e.target.value)}/>
          <div className="ob-chips" style={{ marginTop: 8 }}>
            {['Golden Retriever','Labrador','Husky','Poodle','Mixed','Not sure'].map(b => (
              <button key={b} type="button"
                className={'ob-chip ' + (v.breed === b ? 'sel' : '')}
                onClick={() => set('breed', b)}>{b}</button>
            ))}
          </div>
        </div>
      )

    case 'birthday':
      return (
        <>
          <div className="ob-field">
            <label className="ob-label">Birthday</label>
            <input className="ob-input" type="date"
              value={v.birthday || ''} onChange={e => set('birthday', e.target.value)}/>
          </div>
          <div className="ob-meta" style={{ marginTop: -6, marginBottom: 14 }}>
            Don&apos;t know? An estimate is fine.
          </div>
          <label className="ob-label" style={{ marginBottom: 6, display: 'block' }}>Or guess by age</label>
          <div className="ob-chips">
            {['Puppy / kitten','1–3 yrs','4–7 yrs','8+ yrs'].map(g => (
              <button key={g} type="button"
                className={'ob-chip ' + (v.ageGuess === g ? 'sel' : '')}
                onClick={() => set('ageGuess', g)}>{g}</button>
            ))}
          </div>
        </>
      )

    case 'sex':
      return (
        <>
          <div className="ob-tiles cols-2" style={{ marginBottom: 8 }}>
            {([
              { id: 'f' as const, name: 'Female' },
              { id: 'm' as const, name: 'Male' },
            ]).map(o => (
              <button key={o.id} type="button"
                className={'ob-tile ' + (v.sex === o.id ? 'sel' : '')}
                onClick={() => set('sex', o.id)}
                style={{ alignItems: 'center', padding: '20px 14px' }}>
                <div className="ob-tile-name" style={{ fontSize: 15 }}>{o.name}</div>
              </button>
            ))}
          </div>
          <div className="ob-toggle-row" style={{ borderBottom: 'none' }}>
            <div>
              <div className="name">Spayed / neutered</div>
              <div className="desc">Helps tailor health reminders.</div>
            </div>
            <div className={'ob-switch ' + (v.fixed ? 'on' : '')}
              role="switch" aria-checked={!!v.fixed}
              onClick={() => set('fixed', !v.fixed)}/>
          </div>
        </>
      )

    case 'weight':
      return (
        <div className="ob-field">
          <label className="ob-label">Current weight</label>
          <div style={{ display: 'flex', gap: 8, alignItems: 'stretch' }}>
            <input className="ob-input big" inputMode="decimal" placeholder="24.5"
              value={v.weight || ''} onChange={e => set('weight', e.target.value)}
              style={{ flex: 1 }}/>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, width: 116 }}>
              {(['kg', 'lb'] as const).map(u => (
                <button key={u} type="button"
                  className={'ob-tile ' + (v.unit === u ? 'sel' : '')}
                  onClick={() => set('unit', u)}
                  style={{ padding: '0', alignItems: 'center', justifyContent: 'center' }}>
                  <div className="ob-tile-name" style={{ fontFamily: 'var(--font-mono)', fontSize: 15 }}>{u}</div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )

    case 'vet':
      return (
        <>
          <div className="ob-field">
            <label className="ob-label">Clinic name</label>
            <input className="ob-input" placeholder="Foothill Animal Hospital"
              value={v.clinic || ''} onChange={e => set('clinic', e.target.value)}/>
          </div>
          <div className="ob-field">
            <label className="ob-label">Phone</label>
            <input className="ob-input" type="tel" placeholder="(555) 010-0123"
              value={v.clinicPhone || ''} onChange={e => set('clinicPhone', e.target.value)}/>
          </div>
          <div className="ob-field">
            <label className="ob-label">Vet</label>
            <input className="ob-input" placeholder="Dr. Patel"
              value={v.vet || ''} onChange={e => set('vet', e.target.value)}/>
          </div>
        </>
      )

    case 'meds': {
      const medOptions = [
        { id: 'flea',    name: 'Flea / tick' },
        { id: 'heart',   name: 'Heartworm' },
        { id: 'allergy', name: 'Allergy' },
        { id: 'joint',   name: 'Joint' },
      ]
      return (
        <div className="ob-tiles cols-2" style={{ marginTop: 4 }}>
          {medOptions.map(c => {
            const has = (v.meds || []).some(m => m.id === c.id)
            return (
              <button key={c.id} type="button"
                className={'ob-tile ' + (has ? 'sel' : '')}
                onClick={() => {
                  const cur = v.meds || []
                  set('meds', has
                    ? cur.filter(m => m.id !== c.id)
                    : [...cur, { id: c.id, name: c.name, dose: 'Add dose' }])
                }}>
                <div className="ob-tile-name">{c.name}</div>
              </button>
            )
          })}
        </div>
      )
    }

    case 'conditions': {
      const opts = ['Hip dysplasia','Anxiety','Skin allergies','Food allergies','Arthritis','Epilepsy','None']
      return (
        <>
          <label className="ob-label">Conditions or allergies (optional)</label>
          <div className="ob-chips" style={{ marginTop: 8, marginBottom: 12 }}>
            {opts.map(c => {
              const arr = v.conditions || []
              const has = arr.includes(c)
              return (
                <button key={c} type="button"
                  className={'ob-chip ' + (has ? 'sel' : '')}
                  onClick={() => set('conditions', has ? arr.filter(x => x !== c) : [...arr, c])}>
                  {c}
                </button>
              )
            })}
          </div>
          <div className="ob-field">
            <label className="ob-label">Anything else to note?</label>
            <textarea className="ob-textarea" placeholder="e.g. doesn't tolerate grain"
              value={v.notes || ''} onChange={e => set('notes', e.target.value)}/>
          </div>
        </>
      )
    }

    case 'chip':
      return (
        <>
          <div className="ob-field">
            <label className="ob-label">Microchip ID</label>
            <input className="ob-input" inputMode="numeric"
              placeholder="985 121 000 000 000"
              style={{ fontFamily: 'var(--font-mono)', letterSpacing: '0.04em' }}
              value={v.chip || ''} onChange={e => set('chip', e.target.value)}/>
          </div>
          <div className="ob-toggle-row" style={{ borderBottom: 'none' }}>
            <div>
              <div className="name">Registered to me</div>
              <div className="desc">We&apos;ll remind you to verify yearly.</div>
            </div>
            <div className={'ob-switch ' + (v.chipReg ? 'on' : '')}
              onClick={() => set('chipReg', !v.chipReg)}/>
          </div>
        </>
      )

    case 'vax': {
      const vaxList = [
        { id: 'rabies', name: 'Rabies' },
        { id: 'dhpp',   name: 'DHPP' },
        { id: 'bord',   name: 'Bordetella' },
        { id: 'lepto',  name: 'Leptospirosis' },
      ]
      return (
        <>
          <div className="summary-rows" style={{ marginTop: 4 }}>
            {vaxList.map(vax => {
              const has = !!(v.vax || {})[vax.id]
              return (
                <div key={vax.id} className="summary-row" style={{ cursor: 'pointer' }}
                  onClick={() => set('vax', { ...(v.vax || {}), [vax.id]: !has })}>
                  <span className="k" style={{
                    textTransform: 'none', letterSpacing: 0,
                    fontSize: 14, fontWeight: 500,
                    color: has ? 'var(--blue)' : 'var(--ink-2)',
                    fontFamily: 'var(--font-body)',
                  }}>
                    {vax.name}
                  </span>
                  <span className="v">
                    <span className={'ob-switch ' + (has ? 'on' : '')}
                      style={{ display: 'inline-block', verticalAlign: 'middle' }}/>
                  </span>
                </div>
              )
            })}
          </div>
          <div className="ob-meta" style={{ marginTop: 12 }}>You can add exact dates later.</div>
        </>
      )
    }

    case 'goals': {
      const goalOptions = [
        { id: 'weight', emoji: '⚖️', name: 'Healthy weight', sub: 'Track over time' },
        { id: 'walks',  emoji: '🥾', name: 'More walks',      sub: 'Daily streaks' },
        { id: 'train',  emoji: '🎯', name: 'Training',        sub: 'Track sessions' },
        { id: 'vet',    emoji: '🩺', name: 'Stay on top of vet', sub: 'Reminders' },
      ]
      return (
        <div className="ob-tiles cols-2">
          {goalOptions.map(g => {
            const arr = v.goals || []
            const has = arr.includes(g.id)
            return (
              <button key={g.id} type="button"
                className={'ob-tile ' + (has ? 'sel' : '')}
                onClick={() => set('goals', has ? arr.filter(x => x !== g.id) : [...arr, g.id])}>
                <div className="ob-tile-emoji">{g.emoji}</div>
                <div className="ob-tile-name">{g.name}</div>
                <div className="ob-tile-sub">{g.sub}</div>
              </button>
            )
          })}
        </div>
      )
    }

    case 'notify': {
      const notifyOptions = [
        { id: 'meds',   name: 'Medication reminders', desc: 'When refills are running low.' },
        { id: 'vet',    name: 'Vet check-ups',         desc: 'Annual visits and follow-ups.' },
        { id: 'vax',    name: 'Vaccinations',          desc: "Before they're due." },
        { id: 'walk',   name: 'Walk nudges',            desc: 'Gentle daily reminder.' },
        { id: 'digest', name: 'Weekly digest',          desc: 'A short summary of the week.' },
      ]
      const current: Record<string, boolean> = v.notify || defaultNotify
      return (
        <>
          {notifyOptions.map(n => {
            const on = !!current[n.id]
            return (
              <div key={n.id} className="ob-toggle-row">
                <div>
                  <div className="name">{n.name}</div>
                  <div className="desc">{n.desc}</div>
                </div>
                <div className={'ob-switch ' + (on ? 'on' : '')}
                  role="switch" aria-checked={on}
                  onClick={() => set('notify', { ...current, [n.id]: !on })}/>
              </div>
            )
          })}
        </>
      )
    }

    case 'account':
      return (
        <>
          <button type="button" className="social-btn">
            <svg className="logo" viewBox="0 0 24 24" fill="currentColor" width="18" height="18">
              <path d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z"/>
            </svg>
            Continue with Google
          </button>
          <button type="button" className="social-btn">
            <svg className="logo" viewBox="0 0 24 24" fill="currentColor" width="18" height="18">
              <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.08zM12 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
            </svg>
            Continue with Apple
          </button>
          <div className="ob-divider">or</div>
          <div className="ob-field">
            <label className="ob-label">Email</label>
            <input className="ob-input" type="email" placeholder="you@home.com"
              value={v.email || ''} onChange={e => set('email', e.target.value)}/>
          </div>
          <div className="ob-field">
            <label className="ob-label">Password</label>
            <input className="ob-input" type="password" placeholder="••••••••"
              value={v.password || ''} onChange={e => set('password', e.target.value)}/>
          </div>
        </>
      )

    default:
      return null
  }
}

// ─── Headlines per step ────────────────────────────────────────────────────────

function headlines(petName: string): Partial<Record<StepId, { eye: string; h1: React.ReactNode; sub: string | null }>> {
  return {
    account:    { eye: 'Save your work',  h1: <>Save {petName}<br/>to an account<span className="punct">.</span></>,        sub: "So nothing's lost between phones." },
    name:       { eye: 'Their name',      h1: <>What do you call<br/>them<span className="punct">?</span></>,               sub: 'Nicknames count.' },
    species:    { eye: 'About them',      h1: <>What kind of<br/>creature<span className="punct">?</span></>,               sub: null },
    breed:      { eye: 'Optional',        h1: <>What breed<span className="punct">?</span></>,                              sub: 'A guess is fine. You can edit later.' },
    birthday:   { eye: 'Birthday',        h1: <>When was<br/>the big day<span className="punct">?</span></>,                sub: 'We use this for age-aware reminders.' },
    sex:        { eye: 'Sex',             h1: <>One more basic<span className="punct">.</span></>,                          sub: null },
    weight:     { eye: 'Weight',          h1: <>Latest weigh-in<span className="punct">?</span></>,                        sub: 'Roughly is fine — you can log more anytime.' },
    photo:      { eye: 'Optional',        h1: <>Add a photo<span className="punct">.</span></>,                             sub: 'Their page looks better with their face on it.' },
    vet:        { eye: 'Optional',        h1: <>Who&apos;s their<br/>vet<span className="punct">?</span></>,                sub: 'For quick visit logs and reminders.' },
    meds:       { eye: 'Optional',        h1: <>Any medications<span className="punct">?</span></>,                        sub: 'Tap any that apply.' },
    conditions: { eye: 'Optional',        h1: <>Anything we<br/>should know<span className="punct">?</span></>,             sub: 'Conditions, allergies, quirks.' },
    chip:       { eye: 'Optional',        h1: <>Microchip ID<span className="punct">?</span></>,                           sub: 'In case the worst happens.' },
    vax:        { eye: 'Optional',        h1: <>Vaccinations<br/>up to date<span className="punct">?</span></>,            sub: "Toggle anything they've had." },
    goals:      { eye: "What's next",     h1: <>What are you<br/>working on<span className="punct">?</span></>,            sub: "Pick what matters most. We'll surface it on their page." },
    notify:     { eye: 'Reminders',       h1: <>How should we<br/>nudge you<span className="punct">?</span></>,            sub: 'You can change these anytime.' },
  }
}

// ─── Main flow ─────────────────────────────────────────────────────────────────

export function OnboardingFlow() {
  const [stepIdx, setStepIdx]     = useState(0)
  const [direction, setDirection] = useState<'fwd' | 'back'>('fwd')
  const [v, setV]                 = useState<OBValues>({ unit: 'kg' })
  const [saving, setSaving]       = useState(false)
  const router = useRouter()
  const viewer = useQuery(api.users.viewer)

  const createPet         = useMutation(api.pets.create)
  const createWeightLog   = useMutation(api.medical.createWeightLog)
  const createVaccination = useMutation(api.medical.createVaccination)
  const createMedication  = useMutation(api.medical.createMedication)

  const set: Setter = (k, val) => setV(prev => ({ ...prev, [k]: val }))

  const total     = STEPS.length
  const step      = STEPS[stepIdx]
  const isWelcome = step.id === 'welcome'
  const isDone    = step.id === 'done'
  const petName   = v.name || 'Sandy'

  const handleFinish = async () => {
    setSaving(true)
    try {
      const slug        = (v.name || 'pet').toLowerCase().replace(/[^a-z0-9]/g, '') || 'pet'
      const suffix      = Math.random().toString(36).slice(2, 8)
      const ingestEmail = `${slug}+${suffix}@homepage.pet`
      const today       = new Date().toISOString().slice(0, 10)

      const petId = await createPet({
        userId:   viewer?.tokenIdentifier ?? 'anon',
        name:     v.name || 'Sandy',
        species:  v.species || 'dog',
        breed:    v.breed,
        dob:      v.birthday,
        ingestEmail,
      })

      if (v.weight) {
        const raw  = parseFloat(v.weight)
        const weightKg = v.unit === 'lb' ? raw * 0.453592 : raw
        if (!isNaN(weightKg)) {
          await createWeightLog({ petId, recordedAt: today, weightKg, source: 'onboarding' })
        }
      }

      if (v.vax) {
        for (const [vaccineName, has] of Object.entries(v.vax)) {
          if (has) await createVaccination({ petId, vaccineName, administeredAt: today })
        }
      }

      if (v.meds && v.meds.length > 0) {
        for (const med of v.meds) {
          await createMedication({ petId, drugName: med.name, startedAt: today })
        }
      }

      localStorage.setItem('current_pet_id', petId)
      router.push('/')
    } catch (err) {
      console.error('Failed to save pet:', err)
      setSaving(false)
    }
  }

  const goNext = () => {
    if (isDone) { handleFinish(); return }
    setDirection('fwd')
    setStepIdx(i => Math.min(i + 1, total - 1))
  }
  const goBack = () => {
    setDirection('back')
    setStepIdx(i => Math.max(i - 1, 0))
  }

  const pct = Math.round((stepIdx / (total - 1)) * 100)
  const h   = headlines(petName)[step.id]

  return (
    <div className="ob-shell">

    {/* ── Desktop branding sidebar ── */}
    <aside className="ob-aside">
      <div className="ob-aside-brand">
        <div className="ob-aside-mark">S</div>
        <span className="ob-aside-app">Pet Minder</span>
      </div>
      <div className="ob-aside-illus">
        <div className="illus-polaroid illus-polaroid-lg">
          <div className="pic p1"><div className="canvas">🐕</div></div>
          <div className="pic p2"><div className="canvas">🐾</div></div>
          <div className="pic p3"><div className="canvas">🦴</div></div>
        </div>
      </div>
      <div className="ob-aside-copy">
        <h2 className="ob-aside-h2">A diary for your<br/>best friend<span className="punct">.</span></h2>
        <p className="ob-aside-p">Walks, weigh-ins, vet trips, the funny stuff — all in one place.</p>
      </div>
      <ul className="ob-aside-features">
        <li><span className="ob-aside-ic">🩺</span> Vet visits &amp; vaccines</li>
        <li><span className="ob-aside-ic">⚖️</span> Weight over time</li>
        <li><span className="ob-aside-ic">📓</span> Daily log &amp; reminders</li>
      </ul>
    </aside>

    <div className="ob">
      {/* ── Top bar ── */}
      <div className="ob-top">
        <button className="ob-back" onClick={goBack}
          style={{ visibility: stepIdx === 0 ? 'hidden' : 'visible' }}>
          <ArrowL/>
        </button>
        <div className="ob-brand-mark">S</div>
        {step.optional
          ? <button className="ob-skip" onClick={goNext}>Skip</button>
          : <span style={{ width: 36 }}/>}
      </div>

      {/* ── Progress bar ── */}
      {!isWelcome && !isDone && (
        <div className="ob-progress-wrap">
          <div className="ob-progress-track">
            <div className="ob-progress-fill" style={{ width: pct + '%' }}/>
          </div>
        </div>
      )}

      {/* ── Scrollable body ── */}
      <div className="ob-body">
        <div className="step-stage">
          <div key={stepIdx} className={'step-pane' + (direction === 'back' ? ' back' : '')}>

            {isWelcome && (
              <div className="ob-welcome">
                {/* Polaroid — hidden on desktop where the aside already shows it */}
                <div className="illus-polaroid ob-welcome-illus">
                  <div className="pic p1"><div className="canvas">🐕</div></div>
                  <div className="pic p2"><div className="canvas">🐾</div></div>
                  <div className="pic p3"><div className="canvas">🦴</div></div>
                </div>

                <div className="ob-eye">Pet minder</div>
                <h1 className="ob-h1">A diary for your<br/>best friend<span className="punct">.</span></h1>
                <p className="ob-sub">Walks, weigh-ins, vet trips, the funny stuff. Keep it all in one warm little place.</p>
              </div>
            )}

            {isDone && (
              <div className="confetti-wrap">
                <div className="seal"><Check size={30}/></div>
                <h1 className="ob-h1">
                  <span style={{ color: 'var(--blue)' }}>{petName}</span> is all set<span className="punct">.</span>
                </h1>
                <p className="ob-sub">Their page is waiting. Let&apos;s go log something good.</p>
                <div className="summary-rows" style={{ maxWidth: 340 }}>
                  <div className="summary-row">
                    <span className="k">Pet</span>
                    <span className="v">{v.name || 'Sandy'}</span>
                  </div>
                  <div className="summary-row">
                    <span className="k">Species</span>
                    <span className="v">
                      {v.species === 'dog' ? 'Dog' : v.species === 'cat' ? 'Cat' : v.species === 'other' ? 'Other' : '—'}
                      {v.breed ? ` · ${v.breed}` : ''}
                    </span>
                  </div>
                  <div className="summary-row">
                    <span className="k">Weight</span>
                    <span className="v">{v.weight ? `${v.weight} ${v.unit}` : '—'}</span>
                  </div>
                  <div className="summary-row">
                    <span className="k">Vet</span>
                    <span className={'v' + (v.clinic ? '' : ' muted')}>{v.clinic || 'Add later'}</span>
                  </div>
                </div>
              </div>
            )}

            {!isWelcome && !isDone && h && (
              <div className={'flow-a-screen' + (step.id === 'photo' ? ' top' : '')}>
                <div className="question-area">
                  <div className="ob-eye">{h.eye}</div>
                  <h1 className="ob-h1">{h.h1}</h1>
                  {h.sub && <p className="ob-sub">{h.sub}</p>}

                  {step.id === 'photo'
                    ? <PhotoStepUpload v={v} set={set}/>
                    : <StepContent stepId={step.id} v={v} set={set}/>}
                </div>
              </div>
            )}

          </div>
        </div>
      </div>

      {/* ── Footer CTA ── */}
      <div className="ob-foot">
        {isWelcome && (
          <button className="ob-cta" onClick={goNext}>Get started <ArrowR/></button>
        )}
        {isDone && (
          <button className="ob-cta" onClick={handleFinish} disabled={saving}>
            {saving ? 'Saving…' : <>{`Open ${petName}'s page`} <ArrowR/></>}
          </button>
        )}
        {!isWelcome && !isDone && (
          <button className="ob-cta" onClick={goNext}>Continue <ArrowR/></button>
        )}
      </div>
    </div>

    </div>
  )
}
