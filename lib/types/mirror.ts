// Shape of the health-record snapshot the iOS app mirrors to Convex.
// Contract: ios/PetHomepage/Mirror/MirrorSnapshot.swift (snake_case keys,
// ISO-8601 dates). Convex stores it opaquely (v.any()); the web reads it as this.

export type MirrorSnapshot = {
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
  activity_logs?: Array<{
    id: string
    type_name: string
    category: string
    icon: string
    performed_at: string
    /** Present when the activity was logged as a span (schema v5+). */
    ended_at?: string
    note?: string
    interval_days: number
    next_due_at?: string
  }>
}
