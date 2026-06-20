import { z } from 'zod'

// Request body for POST /api/extract — the mobile app uploads a single
// record document (image or PDF) and receives structured records back.
export const ExtractRequestSchema = z.object({
  fileName: z.string().min(1),
  mimeType: z.enum(['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  content: z.string().min(1), // base64-encoded file bytes
  note: z.string().optional(),
  date: z.string().optional(), // ISO 8601 hint, if the app knows the record date
})

export type ExtractRequest = z.infer<typeof ExtractRequestSchema>
