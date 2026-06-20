// SHA-256 hashing for opaque mirror tokens. Web Crypto (crypto.subtle) is available in
// Convex's default V8 runtime — do NOT add "use node" (this file is imported by both an
// httpAction and a mutation that must stay in the default runtime).

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}
