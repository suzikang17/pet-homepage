import type { ConvexHttpClient } from 'convex/browser'
import type { ExtractionResult } from '@/lib/schemas/extraction'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'

// Writes to the normalized Convex table matching event_type.
// Returns the record id and type, or null for timeline-only event types.
// With the discriminated union schema, TypeScript narrows result.fields per case.
export async function writeNormalizedRecord(
  convex: ConvexHttpClient,
  petId: Id<'pets'>,
  eventId: Id<'events'>,
  result: ExtractionResult,
): Promise<{ recordType: string; recordId: string } | null> {
  switch (result.event_type) {
    case 'vet_visit': {
      const f = result.fields
      const id = await convex.mutation(api.medical.createVetVisit, {
        petId,
        eventId,
        occurredAt:     safeDate(result.occurred_at),
        clinicName:     f.clinic_name,
        vetName:        f.vet_name,
        reason:         f.reason,
        diagnosis:      f.diagnosis,
        treatmentNotes: f.treatment_notes,
        weightKg:       f.weight_kg,
        nextVisitDate:  f.next_visit_date,
      })
      return { recordType: 'vetVisits', recordId: id }
    }

    case 'vaccination': {
      const f = result.fields
      const id = await convex.mutation(api.medical.createVaccination, {
        petId,
        eventId,
        vaccineName:    f.vaccine_name,
        administeredAt: f.administered_at,
        administeredBy: f.administered_by,
        lotNumber:      f.lot_number,
        nextDueAt:      f.next_due_at,
      })
      return { recordType: 'vaccinations', recordId: id }
    }

    case 'medication_start': {
      const f = result.fields
      const id = await convex.mutation(api.medical.createMedication, {
        petId,
        eventId,
        drugName:       f.drug_name,
        dosage:         f.dosage,
        frequency:      f.frequency,
        startedAt:      f.started_at,
        refillDueAt:    f.refill_due_at,
        prescribingVet: f.prescribing_vet,
        notes:          f.notes,
      })
      return { recordType: 'medications', recordId: id }
    }

    case 'medication_refill': {
      const f = result.fields
      const id = await convex.mutation(api.medical.updateMedicationRefill, {
        petId,
        drugName:        f.drug_name,
        refillDate:      f.refill_date,
        nextRefillDueAt: f.next_refill_due_at,
      })
      return { recordType: 'medications', recordId: id }
    }

    case 'weight': {
      const f = result.fields
      const id = await convex.mutation(api.medical.createWeightLog, {
        petId,
        eventId,
        recordedAt: safeDate(result.occurred_at),
        weightKg:   f.weight_kg,
        source:     f.source,
      })
      return { recordType: 'weightLogs', recordId: id }
    }

    // symptom_note, photo, lab_result, procedure, general — timeline only
    default:
      return null
  }
}

// Safely extract ISO date portion from a datetime string.
// Falls back to today if the string is malformed, rather than silently corrupting data.
function safeDate(datetime: string): string {
  const match = datetime.match(/^(\d{4}-\d{2}-\d{2})/)
  if (!match) {
    console.warn(`[write-records] malformed occurred_at: ${datetime}, falling back to today`)
    return new Date().toISOString().split('T')[0]
  }
  return match[1]
}
