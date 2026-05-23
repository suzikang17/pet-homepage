import { z } from 'zod'

export const AttachmentSchema = z.object({
  filename: z.string(),
  mimeType: z.string(),
  size:     z.number(),
  content:  z.string().optional(), // base64 — absent for non-supported MIME types
})

export const IngestPayloadSchema = z.object({
  to:          z.string().email(),
  from:        z.string(),
  subject:     z.string().optional(),
  text:        z.string().optional(),
  html:        z.string().optional(),
  date:        z.string().optional(), // ISO 8601 send date from the mail header
  messageId:   z.string().optional(),
  attachments: z.array(AttachmentSchema).default([]),
})

export type IngestPayload = z.infer<typeof IngestPayloadSchema>
