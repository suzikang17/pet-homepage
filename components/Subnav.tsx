'use client'

interface SubnavItem { key: string; label: string }

export function Subnav({ items, active, onChange }: {
  items: SubnavItem[]
  active: string
  onChange: (key: string) => void
}) {
  return (
    <div className="subnav">
      {items.map(item => (
        <button
          key={item.key}
          className={active === item.key ? 'active' : ''}
          onClick={() => onChange(item.key)}
          type="button"
        >
          {item.label}
        </button>
      ))}
    </div>
  )
}
