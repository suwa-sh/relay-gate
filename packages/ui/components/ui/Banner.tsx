import type { ReactNode } from 'react'
import { Icon, type IconName } from './Icon'

export type BannerVariant = 'info' | 'success' | 'warning' | 'error'

const style: Record<BannerVariant, { background: string; color: string; icon: IconName }> = {
  info: { background: 'var(--banner-info-bg)', color: 'var(--banner-info-fg)', icon: 'terminal' },
  success: { background: 'var(--banner-success-bg)', color: 'var(--banner-success-fg)', icon: 'check' },
  warning: { background: 'var(--banner-warning-bg)', color: 'var(--banner-warning-fg)', icon: 'alert-triangle' },
  error: { background: 'var(--banner-error-bg)', color: 'var(--banner-error-fg)', icon: 'x-circle' },
}

export interface BannerProps {
  variant: BannerVariant
  title: string
  children?: ReactNode
}

export const Banner = ({ variant, title, children }: BannerProps) => {
  const s = style[variant]
  return (
    <div
      style={{
        display: 'flex',
        gap: 'var(--space-3)',
        alignItems: 'flex-start',
        background: s.background,
        color: s.color,
        border: `1px solid ${s.color}`,
        borderRadius: 'var(--radius-sm)',
        padding: 'var(--space-4)',
        fontFamily: 'var(--font-family-sans)',
      }}
    >
      <Icon name={s.icon} size={18} />
      <div>
        <div style={{ fontWeight: 'var(--font-weight-bold)', fontSize: 'var(--font-size-sm)' }}>{title}</div>
        {children && (
          <div style={{ marginTop: 'var(--space-1)', fontSize: 'var(--font-size-sm)', opacity: 0.9 }}>{children}</div>
        )}
      </div>
    </div>
  )
}
