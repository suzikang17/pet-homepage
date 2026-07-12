import {
  convexAuthNextjsMiddleware,
  createRouteMatcher,
  nextjsMiddlewareRedirect,
} from '@convex-dev/auth/nextjs/server'

const isPublic = createRouteMatcher([
  '/sign-in(.*)',
  '/sign-up(.*)',
  // iOS record-scan endpoint: authenticates with its own EXTRACT_SECRET bearer
  // check (see app/api/extract/route.ts), not a browser session — the session
  // gate would 307 the app's POSTs to /sign-in.
  '/api/extract(.*)',
  // Fixture-driven design/QA preview; the route itself 404s in production.
  ...(process.env.NODE_ENV !== 'production' ? ['/dev(.*)'] : []),
])

export default convexAuthNextjsMiddleware(async (request, { convexAuth }) => {
  if (!isPublic(request) && !(await convexAuth.isAuthenticated())) {
    return nextjsMiddlewareRedirect(request, '/sign-in')
  }
})

export const config = {
  matcher: ['/((?!.*\\..*|_next).*)', '/', '/(api|trpc)(.*)'],
}
