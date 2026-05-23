'use client'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useAuthActions } from '@convex-dev/auth/react'

interface Pet { name: string; ingestEmail: string }

export function Topbar({ pet }: { pet: Pet }) {
  const pathname = usePathname()
  const router = useRouter()
  const { signOut } = useAuthActions()
  const slug = pet.ingestEmail.split('@')[0]

  const handleSignOut = () => signOut().then(() => router.replace('/sign-in'))

  return (
    <div className="topbar">
      <div className="brand">
        <div className="brand-mark">{pet.name[0].toUpperCase()}</div>
        <div className="brand-text">
          <div className="brand-name">{pet.name}</div>
          <div className="brand-url">{slug}.homepage.pet</div>
        </div>
      </div>
      <nav className="nav">
        <Link href="/"          className={pathname === '/'          ? 'active' : ''}>Home</Link>
        <Link href="/records"   className={pathname === '/records'   ? 'active' : ''}>Records</Link>
        <Link href="/reminders" className={pathname === '/reminders' ? 'active' : ''}>Reminders</Link>
        <Link href="/share"     className={pathname === '/share'     ? 'active' : ''}>Share</Link>
        <button
          onClick={handleSignOut}
          className="me"
          title="Sign out"
          type="button"
          style={{ cursor: 'pointer', border: 'none' }}
        >
          {pet.name[0].toUpperCase()}
        </button>
      </nav>
    </div>
  )
}
