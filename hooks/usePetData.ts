'use client'
import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useQuery, useConvexAuth } from 'convex/react'
import { api } from '@/convex/_generated/api'
import type { Id } from '@/convex/_generated/dataModel'

export function usePetData() {
  const [petId, setPetId] = useState<string | null>(null)
  const [ready, setReady] = useState(false)
  const router = useRouter()
  const { isAuthenticated, isLoading: authLoading } = useConvexAuth()

  // Read active pet from localStorage once auth is confirmed
  useEffect(() => {
    if (authLoading || !isAuthenticated) return
    const id = localStorage.getItem('current_pet_id')
    if (id) {
      setPetId(id)
      setReady(true)
    }
    // If no id, fall through to userPets query below
  }, [authLoading, isAuthenticated])

  const convexId = petId as Id<'pets'> | null

  const pet          = useQuery(api.pets.getById,             !convexId ? 'skip' : { petId: convexId })
  const events       = useQuery(api.events.listByPet,         !convexId ? 'skip' : { petId: convexId, limit: 50 })
  const weightLogs   = useQuery(api.medical.listWeightLogs,   !convexId ? 'skip' : { petId: convexId })
  const medications  = useQuery(api.medical.listMedications,  !convexId ? 'skip' : { petId: convexId })
  const vaccinations = useQuery(api.medical.listVaccinations, !convexId ? 'skip' : { petId: convexId })
  const vetVisits    = useQuery(api.medical.listVetVisits,    !convexId ? 'skip' : { petId: convexId })

  // Get current user identity to look up pets by userId
  const viewer = useQuery(api.users.viewer, !isAuthenticated ? 'skip' : {})

  // Fallback: if no local petId, query user's pets by userId
  const userPets = useQuery(
    api.pets.listByUserId,
    !petId && viewer ? { userId: viewer.tokenIdentifier } : 'skip'
  )

  useEffect(() => {
    if (authLoading || !isAuthenticated || petId) return
    if (userPets === undefined) return // still loading
    if (userPets && userPets.length > 0) {
      const id = userPets[0]._id
      localStorage.setItem('current_pet_id', id)
      setPetId(id)
    }
    setReady(true)
  }, [authLoading, isAuthenticated, petId, userPets])

  useEffect(() => {
    if (ready && !petId) router.replace('/onboarding')
  }, [ready, petId, router])

  const loading = authLoading || !isAuthenticated || !ready || (!!petId && pet === undefined)

  return {
    pet: pet ?? null,
    events: events ?? [],
    weightLogs: weightLogs ?? [],
    medications: medications ?? [],
    vaccinations: vaccinations ?? [],
    vetVisits: vetVisits ?? [],
    loading,
    petId: convexId,
  }
}
