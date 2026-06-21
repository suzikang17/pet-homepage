import { Password } from '@convex-dev/auth/providers/Password'
import { convexAuth } from '@convex-dev/auth/server'
import { ConvexError } from 'convex/values'

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [
    Password({
      // Relaxed for a personal app: only require a minimum length.
      // (Default policy demands 8+ chars with upper/lower/digit.)
      validatePasswordRequirements: (password: string) => {
        if (password.length < 6) {
          throw new ConvexError('Password must be at least 6 characters.')
        }
      },
    }),
  ],
})
