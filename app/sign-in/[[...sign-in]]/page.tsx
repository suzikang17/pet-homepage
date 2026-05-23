'use client'
import { useAuthActions } from '@convex-dev/auth/react'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

export default function SignInPage() {
  const { signIn } = useAuthActions()
  const router = useRouter()
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    const data = new FormData(e.currentTarget)
    data.set('flow', 'signIn')
    try {
      await signIn('password', data)
      router.replace('/')
    } catch (err: any) {
      setError(err?.message ?? 'Invalid email or password.')
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100dvh', display: 'grid', placeItems: 'center',
      background: 'var(--bg)', padding: '24px',
    }}>
      <div style={{
        width: '100%', maxWidth: 400,
        background: 'var(--paper)', border: '1px solid var(--rule)',
        borderRadius: 16, padding: '36px 32px',
      }}>
        <div style={{ marginBottom: 28 }}>
          <div style={{
            width: 40, height: 40, borderRadius: 10, background: 'var(--blue)', color: 'white',
            display: 'grid', placeItems: 'center', fontFamily: 'var(--font-display), serif',
            fontSize: 22, fontStyle: 'italic', marginBottom: 16,
          }}>h</div>
          <h1 className="serif" style={{ fontSize: 24, margin: '0 0 6px' }}>Welcome back.</h1>
          <p style={{ color: 'var(--ink-3)', fontSize: 14, margin: 0 }}>Sign in to see your pet&apos;s homepage.</p>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <input name="email" type="email" placeholder="Email" required className="ob-input" style={{ width: '100%' }} />
          <input name="password" type="password" placeholder="Password" required className="ob-input" style={{ width: '100%' }} />
          {error && (
            <div style={{ fontSize: 13, color: 'var(--red)', padding: '8px 12px', background: 'var(--red-bg)', borderRadius: 8 }}>
              {error}
            </div>
          )}
          <button type="submit" disabled={loading} style={{
            padding: '12px', borderRadius: 10, border: 'none',
            background: 'var(--blue)', color: 'white',
            fontSize: 14, fontWeight: 600, cursor: loading ? 'not-allowed' : 'pointer',
            opacity: loading ? 0.7 : 1, marginTop: 4,
          }}>
            {loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>

        <div style={{ marginTop: 20, textAlign: 'center', fontSize: 13, color: 'var(--ink-3)' }}>
          Don&apos;t have an account?{' '}
          <Link href="/sign-up" style={{ color: 'var(--blue)', textDecoration: 'none', fontWeight: 500 }}>
            Sign up
          </Link>
        </div>
      </div>
    </div>
  )
}
