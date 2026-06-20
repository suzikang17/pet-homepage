import { timingSafeEqual } from 'crypto'
import { type NextRequest, NextResponse } from 'next/server'
import { extractFromDocument, UnsupportedMediaTypeError } from '@/lib/ingestion/extract'
import { ExtractRequestSchema } from '@/lib/schemas/extract-request'

// Stateless AI record-extraction endpoint for the mobile app.
// Receives one uploaded document, runs Claude extraction, returns the parsed
// records. Never writes to Convex or any store — the app persists the result
// itself (into Core Data / CloudKit).
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
  const expectedSecret = process.env.EXTRACT_SECRET
  if (!expectedSecret) {
    console.error('[extract] EXTRACT_SECRET not set — rejecting all requests')
    return NextResponse.json({ error: 'Server misconfigured' }, { status: 503 })
  }
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('[extract] ANTHROPIC_API_KEY not set — cannot run extraction')
    return NextResponse.json({ error: 'Extraction not configured' }, { status: 503 })
  }

  const incomingSecret = req.headers.get('x-extract-secret') ?? ''
  if (!safeCompare(incomingSecret, expectedSecret)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const contentLength = Number(req.headers.get('content-length') ?? 0)
  if (contentLength > MAX_PAYLOAD_BYTES) {
    return NextResponse.json({ error: 'Payload too large' }, { status: 413 })
  }

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const parsed = ExtractRequestSchema.safeParse(raw)
  if (!parsed.success) {
    return NextResponse.json(
      { error: 'Invalid payload', details: parsed.error.flatten() },
      { status: 400 }
    )
  }

  try {
    const results = await extractFromDocument(parsed.data)
    return NextResponse.json({ ok: true, results })
  } catch (err) {
    if (err instanceof UnsupportedMediaTypeError) {
      return NextResponse.json({ error: err.message }, { status: 415 })
    }
    console.error('[extract] unhandled error:', err)
    return NextResponse.json({ error: 'Extraction failed' }, { status: 500 })
  }
}
