import { z } from 'zod'

// Zod counterparts to lib/types/extraction.ts.
// Used with Claude's generateObject for runtime-validated structured extraction.
// Rule: missing fields are omitted, never guessed. Ambiguity goes into warnings.

const warnings = z.array(z.string()).optional()

// Shared base fields present on every extraction result
const base = {
  occurred_at: z.string().datetime(),   // ISO 8601 — extracted from content, not ingestion time
  title:       z.string(),              // short AI-generated title e.g. "Rabies booster"
  notes:       z.string().optional(),   // brief plain-text summary for the timeline
}

export const VetVisitSchema = z.object({
  clinic_name:      z.string().optional(),
  vet_name:         z.string().optional(),
  reason:           z.string().optional(),
  diagnosis:        z.string().optional(),
  treatment_notes:  z.string().optional(),
  weight_kg:        z.number().positive().optional(),
  next_visit_date:  z.string().date().optional(),
  warnings,
})

export const VaccinationSchema = z.object({
  vaccine_name:     z.string(),
  administered_at:  z.string().date(),
  administered_by:  z.string().optional(),
  lot_number:       z.string().optional(),
  next_due_at:      z.string().date().optional(),
  warnings,
})

export const MedicationStartSchema = z.object({
  drug_name:        z.string(),
  dosage:           z.string().optional(),
  frequency:        z.string().optional(),
  started_at:       z.string().date(),
  refill_due_at:    z.string().date().optional(),
  prescribing_vet:  z.string().optional(),
  notes:            z.string().optional(),
  warnings,
})

export const MedicationRefillSchema = z.object({
  drug_name:          z.string(),
  refill_date:        z.string().date(),
  next_refill_due_at: z.string().date().optional(),
  warnings,
})

export const WeightSchema = z.object({
  weight_kg:  z.number().positive(),
  source:     z.enum(['vet_visit', 'home', 'groomer']).optional(),
  warnings,
})

export const SymptomNoteSchema = z.object({
  category:   z.enum(['digestive', 'behavior', 'skin', 'diet', 'energy', 'other']).optional(),
  severity:   z.enum(['mild', 'moderate', 'severe']).optional(),
  body_area:  z.string().optional(),
  warnings,
})

export const PhotoSchema = z.object({
  description: z.string().optional(),
  tags:        z.array(z.string()).optional(),
  warnings,
})

export const LabResultSchema = z.object({
  test_type:      z.string(),
  results:        z.array(z.object({
    name:            z.string(),
    value:           z.string(),
    unit:            z.string().optional(),
    reference_range: z.string().optional(),
    flag:            z.enum(['high', 'low', 'normal']).optional(),
  })).optional(),
  interpreted_by: z.string().optional(),
  notes:          z.string().optional(),
  warnings,
})

export const ProcedureSchema = z.object({
  procedure_type:  z.string(),
  performed_by:    z.string().optional(),
  anesthesia:      z.boolean().optional(),
  recovery_notes:  z.string().optional(),
  follow_up_date:  z.string().date().optional(),
  warnings,
})

export const GeneralSchema = z.object({
  summary:  z.string().optional(),
  warnings,
})

// ─── Discriminated union ─────────────────────────────────────────────────────
// event_type is the discriminant — Zod enforces that fields matches event_type.
// This prevents Claude from returning e.g. event_type:'vaccination' with VetVisitFields.

export const ExtractionResultSchema = z.discriminatedUnion('event_type', [
  z.object({ event_type: z.literal('vet_visit'),          ...base, fields: VetVisitSchema }),
  z.object({ event_type: z.literal('vaccination'),        ...base, fields: VaccinationSchema }),
  z.object({ event_type: z.literal('medication_start'),   ...base, fields: MedicationStartSchema }),
  z.object({ event_type: z.literal('medication_refill'),  ...base, fields: MedicationRefillSchema }),
  z.object({ event_type: z.literal('weight'),             ...base, fields: WeightSchema }),
  z.object({ event_type: z.literal('symptom_note'),       ...base, fields: SymptomNoteSchema }),
  z.object({ event_type: z.literal('photo'),              ...base, fields: PhotoSchema }),
  z.object({ event_type: z.literal('lab_result'),         ...base, fields: LabResultSchema }),
  z.object({ event_type: z.literal('procedure'),          ...base, fields: ProcedureSchema }),
  z.object({ event_type: z.literal('general'),            ...base, fields: GeneralSchema }),
])

export type ExtractionResult = z.infer<typeof ExtractionResultSchema>

// Used with generateObject — Claude returns one object per distinct health event in the email.
export const ExtractionResultArraySchema = z.object({
  results: z.array(ExtractionResultSchema).min(1),
})
