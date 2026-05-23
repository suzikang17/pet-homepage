import { NextRequest, NextResponse } from 'next/server'
import { timingSafeEqual } from 'crypto'
import { IngestPayloadSchema } from '@/lib/schemas/ingest'
import { createConvexClient } from '@/lib/convex/client'
import { extractFromEmail } from '@/lib/ingestion/extract'
import { writeNormalizedRecord } from '@/lib/ingestion/write-records'
import { api } from '@/convex/_generated/api'

const MAX_PAYLOAD_BYTES = 25 * 1024 * 1024 // 25 MB

function safeCompare(a: string, b: string): boolean {
  try {
    const ab = Buffer.from(a)
    const bb = Buffer.from(b)
    if (ab.length !== bb.length) return false
    return timingSafeEqual(ab, bb)
  } catch {
    return false
  }
}

export async function POST(req: NextRequest) {
  if (!process.env.NEXT_PUBLIC_CONVEX_URL) {
    return NextResponse.json({ error: 'Convex not configured' }, { status: 503 })
  }

  const expectedSecret = process.env.INGEST_SECRET
  if (!expectedSecret) {
    console.error('[ingest] INGEST_SECRET not set — rejecting all requests')
    return NextResponse.json({ error: 'Server misconfigured' }, { status: 503 })
  }

  const incomingSecret = req.headers.get('x-ingest-secret') ?? ''
  if (!safeCompare(incomingSecret, expectedSecret)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const contentLength = Number(req.headers.get('content-length') ?? 0)
  if (contentLength > MAX_PAYLOAD_BYTES) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413 })
  }

  try {
    const raw = await req.json()
    const parsed = IngestPayloadSchema.safeParse(raw)
    if (!parsed.success) {
      return NextResponse.json(
        { error: 'Invalid payload', details: parsed.error.flatten() },
        { status: 400 },
      )
    }
    const payload = parsed.data

    const convex = createConvexClient()

    const pet = await convex.query(api.pets.getByIngestEmail, { email: payload.to })
    if (!pet) return NextResponse.json({ error: 'Pet not found' }, { status: 404 })

    const results = await extractFromEmail(payload)
    const eventIds: string[] = []

    for (const result of results) {
      const eventId = await convex.mutation(api.events.create, {
        petId:       pet._id,
        occurredAt:  result.occurred_at,
        source:      'email',
        eventType:   result.event_type,
        title:       result.title,
        notes:       result.notes,
        rawContent:  payload.text ?? payload.html,
        attachments: payload.attachments.map((a) => ({
          filename: a.filename,
          mimeType: a.mimeType,
          size:     a.size,
        })),
        parsedFields: result.fields,
        messageId:    payload.messageId,
      })

      const normalized = await writeNormalizedRecord(convex, pet._id, eventId, result)
      if (normalized) {
        await convex.mutation(api.events.linkRecord, {
          eventId,
          recordId:   normalized.recordId,
          recordType: normalized.recordType,
        })
      }

      eventIds.push(eventId)
    }

    return NextResponse.json({ ok: true, eventIds })
  } catch (err) {
    console.error('[ingest] unhandled error:', err)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
