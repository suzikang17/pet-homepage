import { MirrorDashboard } from '@/components/MirrorDashboard'
import { MirrorTokensManager } from '@/components/MirrorTokensManager'

export const metadata = { title: 'Dashboard' }

export default function Dashboard() {
  return (
    <>
      <MirrorTokensManager />
      <MirrorDashboard />
    </>
  )
}
