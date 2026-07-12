import type { MirrorSnapshot } from '@/lib/types/mirror'

// Realistic fixture for the dev-only preview route (app/dev/preview). Dates are
// pinned relative to FIXTURE_NOW so due-soon / overdue states render stably.

export const FIXTURE_NOW = new Date('2026-07-12T09:00:00Z')

const d = (offsetDays: number) => {
  const t = new Date(FIXTURE_NOW)
  t.setDate(t.getDate() + offsetDays)
  return t.toISOString()
}

export const fixtureUpdatedAt = new Date('2026-07-11T21:42:00Z').getTime()

export const fixtureSnapshot: MirrorSnapshot = {
  schema_version: 3,
  generated_at: d(-1),
  pet: {
    id: 'pet-1',
    name: 'Sandy',
    species: 'Dog',
    breed: 'Golden Retriever',
    dob: '2021-03-14T00:00:00Z',
    adoption_date: '2021-05-30T00:00:00Z',
  },
  medications: [
    {
      id: 'med-1',
      drug_name: 'Apoquel',
      dosage: '16 mg',
      frequency: 'Twice daily',
      schedule_time: '08:00',
      started_at: d(-240),
      refill_due_at: d(9),
      veterinarian: 'Dr. Reyes',
      dose_logs: [
        { id: 'dl-1', given_at: d(-2) },
        { id: 'dl-2', given_at: d(-1) },
        { id: 'dl-3', given_at: d(0) },
      ],
    },
    {
      id: 'med-2',
      drug_name: 'Simparica Trio',
      dosage: '1 chew',
      frequency: 'Monthly',
      schedule_time: '09:00',
      started_at: d(-400),
      dose_logs: [{ id: 'dl-4', given_at: d(-18) }],
    },
    {
      id: 'med-3',
      drug_name: 'Amoxicillin',
      dosage: '250 mg',
      frequency: 'Twice daily',
      schedule_time: '08:00',
      started_at: d(-90),
      ended_at: d(-76),
      dose_logs: [{ id: 'dl-5', given_at: d(-76) }],
    },
  ],
  vaccinations: [
    {
      id: 'vax-1',
      vaccine_name: 'Rabies',
      administered_at: d(-380),
      next_due_at: d(-15),
      administered_by: 'Lakeside Animal Hospital',
    },
    {
      id: 'vax-2',
      vaccine_name: 'DHPP',
      administered_at: d(-340),
      next_due_at: d(24),
      veterinarian: 'Dr. Reyes',
    },
    {
      id: 'vax-3',
      vaccine_name: 'Bordetella',
      administered_at: d(-120),
      next_due_at: d(245),
    },
    {
      id: 'vax-4',
      vaccine_name: 'Leptospirosis',
      administered_at: d(-340),
      next_due_at: d(390),
      lot_number: 'LP-88231',
    },
  ],
  vet_visits: [
    {
      id: 'vis-1',
      occurred_at: d(-12),
      clinic_name: 'Lakeside Animal Hospital',
      vet_name: 'Dr. Reyes',
      reason: 'Itchy skin follow-up',
      diagnosis: 'Seasonal atopy, improving',
      next_visit_date: d(78),
      recommendations: [
        { id: 'rec-1', date: d(-12), text: 'Continue Apoquel through allergy season' },
        { id: 'rec-2', date: d(-12), text: 'Weekly oatmeal bath for 4 weeks' },
      ],
    },
    {
      id: 'vis-2',
      occurred_at: d(-96),
      clinic_name: 'Lakeside Animal Hospital',
      reason: 'Annual wellness exam',
      diagnosis: 'Healthy; mild tartar on upper molars',
      recommendations: [
        { id: 'rec-3', date: d(-96), text: 'Start dental chews; recheck at next annual' },
      ],
    },
  ],
  unlinked_recommendations: [],
  health_markers: [
    { id: 'hm-1', marker_type: 'Weight', value: 29.4, unit: 'kg', recorded_at: d(-5) },
    { id: 'hm-2', marker_type: 'Weight', value: 29.9, unit: 'kg', recorded_at: d(-40) },
    { id: 'hm-3', marker_type: 'Weight', value: 30.6, unit: 'kg', recorded_at: d(-96) },
    { id: 'hm-4', marker_type: 'Resting heart rate', value: 74, unit: 'bpm', recorded_at: d(-96) },
  ],
  symptom_episodes: [
    {
      id: 'sym-1',
      category: 'Skin',
      title: 'Paw licking flare',
      started_at: d(-30),
      status: 'active',
      entries: [
        { id: 'se-1', date: d(-30), severity: 'mild', note: 'Licking front paws after park' },
        {
          id: 'se-2',
          date: d(-9),
          severity: 'moderate',
          note: 'Red between toes',
          suspected_cause: 'Grass pollen',
        },
      ],
    },
    {
      id: 'sym-2',
      category: 'Digestive',
      title: 'Soft stool',
      started_at: d(-70),
      resolved_at: d(-62),
      status: 'resolved',
      entries: [
        { id: 'se-3', date: d(-70), severity: 'mild', note: 'After new treats; stopped them' },
      ],
    },
  ],
  care_team: [
    {
      id: 'ct-1',
      name: 'Dr. Maria Reyes',
      clinic: 'Lakeside Animal Hospital',
      phone: '(415) 555-0134',
      email: 'front@lakesideah.com',
      address: '2200 Shoreline Blvd, Oakland, CA',
    },
    {
      id: 'ct-2',
      name: 'PetER Emergency',
      clinic: '24h Emergency',
      phone: '(415) 555-0911',
      notes: 'Open 24/7 — nearest ER, 12 min drive',
    },
  ],
  diary: [
    { id: 'dia-1', date: d(-1), note: 'Long beach walk, zero paw licking today.', photo_count: 3 },
    {
      id: 'dia-2',
      date: d(-4),
      note: 'Met the new neighbor’s corgi. Instant best friends.',
      photo_count: 1,
    },
    {
      id: 'dia-3',
      date: d(-8),
      note: 'Refused breakfast until the tennis ball was found.',
      photo_count: 0,
    },
  ],
  activity_logs: [
    {
      id: 'act-1',
      type_name: 'Nail trim',
      category: 'Grooming',
      icon: 'scissors',
      performed_at: d(-20),
      interval_days: 30,
      next_due_at: d(10),
    },
    {
      id: 'act-2',
      type_name: 'Full groom',
      category: 'Grooming',
      icon: 'shower',
      performed_at: d(-45),
      note: 'Summer cut at Bubbles & Bows',
      interval_days: 60,
      next_due_at: d(15),
    },
    {
      id: 'act-3',
      type_name: 'Flea/tick check',
      category: 'Health',
      icon: 'magnifyingglass',
      performed_at: d(-3),
      interval_days: 7,
      next_due_at: d(4),
    },
    {
      id: 'act-4',
      type_name: 'Walk',
      category: 'Training',
      icon: 'figure.walk',
      performed_at: d(-1),
      ended_at: new Date(new Date(d(-1)).getTime() + 32 * 60_000).toISOString(),
      interval_days: 0,
    },
  ],
}

export const fixtureTokens = [
  {
    _id: 'tok-1',
    label: 'Suzi’s iPhone 15',
    createdAt: new Date('2026-06-02T18:20:00Z').getTime(),
    revokedAt: undefined as number | undefined,
  },
  {
    _id: 'tok-2',
    label: 'Old iPhone 12',
    createdAt: new Date('2026-02-11T10:05:00Z').getTime(),
    revokedAt: new Date('2026-06-02T18:25:00Z').getTime(),
  },
]
