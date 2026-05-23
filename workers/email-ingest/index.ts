import PostalMime from 'postal-mime'

const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024  // 10 MB per attachment
const MAX_TOTAL_BYTES      = 20 * 1024 * 1024  // 20 MB total payload

function toBase64(bytes: Uint8Array): string {
  const chunk = 0x8000  // 32KB chunks — avoids call-stack overflow and O(n) realloc
  let result = ''
  for (let i = 0; i < bytes.length; i += chunk) {
    result += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(result)
}

interface Env {
  INGEST_API_URL: string
  INGEST_SECRET: string
}

export default {
  async email(message: ForwardableEmailMessage, env: Env): Promise<void> {
    if (message.rawSize > MAX_TOTAL_BYTES) {
      message.setReject('Email too large')
      return
    }

    const raw = await new Response(message.raw).arrayBuffer()
    const parsed = await new PostalMime().parse(raw)

    const attachments = (parsed.attachments ?? [])
      .filter((a) => {
        const bytes = typeof a.content === 'string'
          ? new TextEncoder().encode(a.content)
          : new Uint8Array(a.content)
        return bytes.byteLength <= MAX_ATTACHMENT_BYTES
      })
      .map((a) => {
        const bytes = typeof a.content === 'string'
          ? new TextEncoder().encode(a.content)
          : new Uint8Array(a.content)
        return {
          filename: a.filename ?? 'attachment',
          mimeType: a.mimeType,
          size:     bytes.byteLength,
          content:  toBase64(bytes),
        }
      })

    const payload = {
      to:          message.to,
      from:        message.from,
      subject:     parsed.subject ?? '',
      text:        parsed.text ?? '',
      html:        parsed.html ?? '',
      date:        parsed.date ?? new Date().toISOString(),
      messageId:   parsed.messageId ?? '',   // used for deduplication
      attachments,
    }

    const res = await fetch(env.INGEST_API_URL, {
      method:  'POST',
      headers: {
        'Content-Type':    'application/json',
        'x-ingest-secret': env.INGEST_SECRET,
      },
      body: JSON.stringify(payload),
    })

    if (!res.ok) {
      message.setReject(`Ingest failed: ${res.status}`)
    }
  },
}
