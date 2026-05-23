// Shapes for events.parsed_fields, keyed by event_type.
// Used by the Claude ingestion pipeline (generateObject Zod schemas)
// and by UI components for rendering event details.
//
// Rule: missing fields are omitted, never guessed. Ambiguity goes into warnings.

export type EventSource = 'email' | 'sms' | 'manual'

export type EventType =
  | 'vet_visit'
  | 'vaccination'
  | 'medication_start'
  | 'medication_refill'
  | 'weight'
  | 'symptom_note'
  | 'photo'
  | 'lab_result'
  | 'procedure'
  | 'general'

// ─── Vet visit ───────────────────────────────────────────────────────────────

export interface VetVisitFields {
  clinic_name?: string
  vet_name?: string
  reason?: string
  diagnosis?: string
  treatment_notes?: string
  weight_kg?: number
  next_visit_date?: string   // ISO date: "2026-08-01"
  warnings?: string[]
}

// ─── Vaccination ─────────────────────────────────────────────────────────────

export interface VaccinationFields {
  vaccine_name: string       // 'Rabies' | 'DHPP' | 'Bordetella' | 'Leptospirosis' | ...
  administered_at: string    // ISO date
  administered_by?: string
  lot_number?: string
  next_due_at?: string       // ISO date — source of truth for reminder scheduling
  warnings?: string[]
}

// ─── Medication start ────────────────────────────────────────────────────────

export interface MedicationStartFields {
  drug_name: string          // 'Apoquel' | 'NexGard' | 'Heartgard' | ...
  dosage?: string            // '16mg'
  frequency?: string         // 'daily' | 'monthly' | 'as needed'
  started_at: string         // ISO date
  refill_due_at?: string     // ISO date
  prescribing_vet?: string
  notes?: string
  warnings?: string[]
}

// ─── Medication refill ───────────────────────────────────────────────────────

export interface MedicationRefillFields {
  drug_name: string
  refill_date: string        // ISO date
  next_refill_due_at?: string
  warnings?: string[]
}

// ─── Weight ──────────────────────────────────────────────────────────────────

export interface WeightFields {
  weight_kg: number
  source?: 'vet_visit' | 'home' | 'groomer'
  warnings?: string[]
}

// ─── Symptom / wellness note ─────────────────────────────────────────────────

export type SymptomCategory = 'digestive' | 'behavior' | 'skin' | 'diet' | 'energy' | 'other'
export type SymptomSeverity = 'mild' | 'moderate' | 'severe'

export interface SymptomNoteFields {
  category?: SymptomCategory
  severity?: SymptomSeverity
  body_area?: string         // 'left ear' | 'paw' | etc.
  warnings?: string[]
}

// ─── Photo ───────────────────────────────────────────────────────────────────

export interface PhotoFields {
  description?: string
  tags?: string[]            // ['beach', 'swimming', 'family']
  warnings?: string[]
}

// ─── Lab result ──────────────────────────────────────────────────────────────

export interface LabResultFields {
  test_type: string          // 'CBC' | 'urinalysis' | 'thyroid panel' | ...
  results?: Array<{
    name: string
    value: string
    unit?: string
    reference_range?: string
    flag?: 'high' | 'low' | 'normal'
  }>
  interpreted_by?: string
  notes?: string
  warnings?: string[]
}

// ─── Procedure ───────────────────────────────────────────────────────────────

export interface ProcedureFields {
  procedure_type: string     // 'dental cleaning' | 'spay' | 'mass removal' | ...
  performed_by?: string
  anesthesia?: boolean
  recovery_notes?: string
  follow_up_date?: string    // ISO date
  warnings?: string[]
}

// ─── General ─────────────────────────────────────────────────────────────────

export interface GeneralFields {
  summary?: string
  warnings?: string[]
}

// ─── Discriminated union ─────────────────────────────────────────────────────
// Use this when you need to work with parsed_fields in a type-safe way.

export type ParsedFields =
  | ({ event_type: 'vet_visit' }          & VetVisitFields)
  | ({ event_type: 'vaccination' }        & VaccinationFields)
  | ({ event_type: 'medication_start' }   & MedicationStartFields)
  | ({ event_type: 'medication_refill' }  & MedicationRefillFields)
  | ({ event_type: 'weight' }             & WeightFields)
  | ({ event_type: 'symptom_note' }       & SymptomNoteFields)
  | ({ event_type: 'photo' }              & PhotoFields)
  | ({ event_type: 'lab_result' }         & LabResultFields)
  | ({ event_type: 'procedure' }          & ProcedureFields)
  | ({ event_type: 'general' }            & GeneralFields)
