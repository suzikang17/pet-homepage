import {
  convexAuthNextjsMiddleware,
  createRouteMatcher,
  nextjsMiddlewareRedirect,
} from '@convex-dev/auth/nextjs/server'

const isPublic = createRouteMatcher([
  '/sign-in(.*)',
  '/sign-up(.*)',
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
