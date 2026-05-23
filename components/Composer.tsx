"use client"

import { useEffect, useRef, useState } from "react"
import { useMutation } from "convex/react"
import { api } from "@/convex/_generated/api"
import { Toast } from "./Toast"
import type { Id } from "@/convex/_generated/dataModel"

type ComposerType = "note" | "weight" | "symptom" | "med" | "photo"

const placeholders: Record<ComposerType, string> = {
  note:    "What happened today?",
  weight:  "Optional note…",
  symptom: "Started limping a little after the trail…",
  med:     "Gave Apoquel with breakfast.",
  photo:   "Sun-nap on the deck. Caption?",
}

const submitMessages: Record<ComposerType, string> = {
  note:    "Note added to timeline.",
  weight:  "Weight logged — added to chart.",
  symptom: "Symptom noted. We'll surface this for the next vet visit.",
  med:     "Medication logged.",
  photo:   "Photo added to the timeline.",
}

const types: { key: ComposerType; label: string }[] = [
  { key: "note",    label: "📝 Note" },
  { key: "weight",  label: "⚖ Weight" },
  { key: "symptom", label: "🩺 Symptom" },
  { key: "med",     label: "💊 Medication" },
  { key: "photo",   label: "📷 Photo" },
]

const EVENT_TYPES: Partial<Record<ComposerType, string>> = {
  note:    "note",
  symptom: "symptom",
  med:     "medication_given",
}

export function Composer({ petId, petName }: { petId: Id<"pets">; petName: string }) {
  const [collapsed, setCollapsed]   = useState(true)
  const [type, setType]             = useState<ComposerType>("note")
  const [text, setText]             = useState("")
  const [weightVal, setWeightVal]   = useState("")
  const [weightUnit, setWeightUnit] = useState<"lb" | "kg">("lb")
  const [weightSrc, setWeightSrc]   = useState<"bathroom" | "vet" | "other">("bathroom")
  const [submitting, setSubmitting] = useState(false)
  const [toast, setToast]           = useState<{ message: string; show: boolean }>({ message: "", show: false })

  const textareaRef      = useRef<HTMLTextAreaElement>(null)
  const toastTimerRef    = useRef<ReturnType<typeof setTimeout> | null>(null)
  const collapseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const focusTimerRef    = useRef<ReturnType<typeof setTimeout> | null>(null)

  const logEvent  = useMutation(api.events.create)
  const logWeight = useMutation(api.medical.createWeightLog)

  const expand = () => {
    setCollapsed(false)
    if (focusTimerRef.current) clearTimeout(focusTimerRef.current)
    focusTimerRef.current = setTimeout(() => { textareaRef.current?.focus() }, 200)
  }

  const collapse = () => {
    setCollapsed(true)
    setText("")
    setWeightVal("")
  }

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        if (collapsed) expand()
        else textareaRef.current?.focus()
      }
      if (e.key === "Escape" && !collapsed) collapse()
    }
    window.addEventListener("keydown", handler)
    return () => window.removeEventListener("keydown", handler)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collapsed])

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
      if (collapseTimerRef.current) clearTimeout(collapseTimerRef.current)
      if (focusTimerRef.current) clearTimeout(focusTimerRef.current)
    }
  }, [])

  const showToast = (message: string) => {
    setToast({ message, show: true })
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current)
    toastTimerRef.current = setTimeout(() => { setToast(t => ({ ...t, show: false })) }, 2200)
  }

  const handleSubmit: React.MouseEventHandler<HTMLButtonElement> = async (e) => {
    e.stopPropagation()
    if (submitting) return
    setSubmitting(true)
    try {
      const now = new Date().toISOString()

      if (type === "weight") {
        const raw = parseFloat(weightVal)
        if (!isNaN(raw) && raw > 0) {
          const weightKg = weightUnit === "lb" ? raw * 0.453592 : raw
          await logWeight({ petId, recordedAt: now, weightKg, source: weightSrc })
        }
      } else if (type === "photo") {
        // Photo upload not yet wired — show toast only
      } else {
        const eventType = EVENT_TYPES[type]!
        if (text.trim()) {
          await logEvent({
            petId,
            occurredAt: now,
            source: "manual",
            eventType,
            notes: text.trim(),
            attachments: [],
            parsedFields: {},
          })
        }
      }

      showToast(submitMessages[type])
      if (collapseTimerRef.current) clearTimeout(collapseTimerRef.current)
      collapseTimerRef.current = setTimeout(() => collapse(), 500)
    } catch {
      showToast("Something went wrong. Try again.")
    } finally {
      setSubmitting(false)
    }
  }

  const handleClose: React.MouseEventHandler<HTMLButtonElement> = (e) => {
    e.stopPropagation()
    collapse()
  }

  const handleWrapperClick = () => { if (collapsed) expand() }

  return (
    <>
      <div className="composer-wrap">
        <div
          className={`composer ${collapsed ? "collapsed" : ""}`}
          onClick={handleWrapperClick}
        >
          <div className="composer-h">
            <div className="ic">
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6">
                <path d="M12 5v14M5 12h14" />
              </svg>
            </div>
            <div className="label">Log something for {petName}</div>
            <div className="hint"><kbd>⌘</kbd> <kbd>K</kbd></div>
            <button className="close" type="button" onClick={handleClose} title="Collapse" aria-label="Collapse composer">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
                <path d="M18 6L6 18M6 6l12 12" />
              </svg>
            </button>
          </div>
          <div className="body">
            <div className="types">
              {types.map(t => (
                <button
                  key={t.key}
                  className={type === t.key ? "active" : ""}
                  onClick={e => { e.stopPropagation(); setType(t.key) }}
                  type="button"
                >
                  {t.label}
                </button>
              ))}
            </div>
            <textarea
              ref={textareaRef}
              value={text}
              onChange={e => setText(e.target.value)}
              placeholder={placeholders[type]}
              onClick={e => e.stopPropagation()}
            />
            <div className={`extras ${type === "weight" ? "show" : ""}`}>
              <input
                type="number"
                placeholder="62.4"
                value={weightVal}
                onChange={e => setWeightVal(e.target.value)}
                onClick={e => e.stopPropagation()}
              />
              <select
                value={weightUnit}
                onChange={e => setWeightUnit(e.target.value as "lb" | "kg")}
                onClick={e => e.stopPropagation()}
              >
                <option value="lb">lb</option>
                <option value="kg">kg</option>
              </select>
              <select
                value={weightSrc}
                onChange={e => setWeightSrc(e.target.value as "bathroom" | "vet" | "other")}
                onClick={e => e.stopPropagation()}
              >
                <option value="bathroom">Bathroom scale</option>
                <option value="vet">Vet scale</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div className="composer-foot">
              <div className="composer-tools">
                <button type="button" title="Attach photo" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <path d="M21.44 11.05l-9.19 9.19a6 6 0 1 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" />
                  </svg>
                </button>
                <button type="button" title="Set date" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <rect x="3" y="4" width="18" height="18" rx="2" />
                    <path d="M16 2v4M8 2v4M3 10h18" />
                  </svg>
                </button>
                <button type="button" title="Tag" onClick={e => e.stopPropagation()}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
                    <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
                  </svg>
                </button>
              </div>
              <button
                className="submit"
                type="button"
                onClick={handleSubmit}
                disabled={submitting}
              >
                {submitting ? "Saving…" : "Add to timeline"}
                {!submitting && (
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
                    <path d="M5 12h14M13 5l7 7-7 7" />
                  </svg>
                )}
              </button>
            </div>
          </div>
        </div>
      </div>
      <Toast message={toast.message} show={toast.show} />
    </>
  )
}
