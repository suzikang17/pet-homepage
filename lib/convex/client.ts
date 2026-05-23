import { ConvexHttpClient } from 'convex/browser'

// Server-side Convex client for API routes and server actions.
// Never expose this to the browser — use the React ConvexProvider instead.
export function createConvexClient() {
  return new ConvexHttpClient(process.env.NEXT_PUBLIC_CONVEX_URL!)
}
