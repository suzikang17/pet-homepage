import { generateObject } from 'ai'
import { anthropic } from '@ai-sdk/anthropic'
import { ExtractionResultArraySchema, type ExtractionResult } from '@/lib/schemas/extraction'
import type { IngestPayload } from '@/lib/schemas/ingest'

type TextPart  = { type: 'text'; text: string }
type ImagePart = { type: 'image'; image: string; mimeType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' }
type FilePart  = { type: 'file'; data: string; mediaType: 'application/pdf' }
type ContentPart = TextPart | ImagePart | FilePart

const SUPPORTED_ATTACHMENT_TYPES = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
])

export async function extractFromEmail(payload: IngestPayload): Promise<ExtractionResult[]> {
  const bodyText = payload.text?.trim()
  const body = bodyText || (payload.html ? stripHtml(payload.html) : '(no body)')

  const content: ContentPart[] = [
    {
      type: 'text',
      text: [
        `From: ${payload.from}`,
        `Subject: ${payload.subject ?? '(no subject)'}`,
        payload.date ? `Date: ${payload.date}` : null,
        '',
        body,
      ].filter(Boolean).join('\n'),
    },
  ]

  for (const attachment of payload.attachments) {
    if (!SUPPORTED_ATTACHMENT_TYPES.has(attachment.mimeType)) continue
    if (!attachment.content) continue
    if (attachment.mimeType === 'application/pdf') {
      content.push({ type: 'file', data: attachment.content, mediaType: 'application/pdf' })
    } else {
      content.push({
        type: 'image',
        image: attachment.content,
        mimeType: attachment.mimeType as 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif',
      })
    }
  }

  const { object } = await generateObject({
    model: anthropic('claude-sonnet-4-6'),
    schema: ExtractionResultArraySchema,
    messages: [{ role: 'user', content }],
    system: SYSTEM_PROMPT,
  })

  return object.results
}

const SYSTEM_PROMPT = `You extract structured pet health records from forwarded emails and documents.

Rules:
- occurred_at: use the date from the document content, NOT today's date. ISO 8601 with time if available, otherwise noon UTC (e.g. "2026-03-15T12:00:00Z").
- title: short and specific, e.g. "Rabies booster", "Apoquel refill", "Annual wellness exam"
- notes: 1-2 sentence plain-text summary suitable for a timeline
- fields: extract only what is clearly stated. Omit fields that are ambiguous or absent — never guess.
- warnings: note anything ambiguous, conflicting, or worth human review.
- Multiple records: if a document contains multiple distinct health events (e.g. a vet visit that also includes a vaccination and a new medication), return one result object per event. Do not collapse them into one.`

function stripHtml(html: string): string {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/\s+/g, ' ')
    .trim()
}
