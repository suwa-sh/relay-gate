import type { ReactNode } from 'react'

export type TerminalPanelVariant = 'default' | 'compact'
export type TerminalPanelSize = 'sm' | 'md' | 'lg'

export interface TerminalPanelProps {
  title?: string
  variant?: TerminalPanelVariant
  size?: TerminalPanelSize
  children: ReactNode
}

const sizeWidth: Record<TerminalPanelSize, string> = { sm: '360px', md: '560px', lg: '760px' }

export const TerminalPanel = ({ title, variant = 'default', size = 'md', children }: TerminalPanelProps) => (
  <div
    style={{
      width: sizeWidth[size],
      maxWidth: '100%',
      background: 'var(--terminal-panel-background)',
      color: 'var(--terminal-panel-foreground)',
      borderRadius: 'var(--terminal-panel-radius)',
      boxShadow: 'var(--shadow-md)',
      overflow: 'hidden',
    }}
  >
    {title && (
      <div
        style={{
          padding: 'var(--space-2) var(--space-4)',
          borderBottom: '1px solid rgba(255,255,255,0.12)',
          fontFamily: 'var(--font-family-mono)',
          fontSize: 'var(--font-size-xs)',
          color: 'var(--color-slate-400)',
        }}
      >
        {title}
      </div>
    )}
    <pre
      style={{
        margin: 0,
        padding: variant === 'compact' ? 'var(--space-2)' : 'var(--terminal-panel-padding)',
        fontFamily: 'var(--terminal-panel-font)',
        fontSize: 'var(--font-size-sm)',
        lineHeight: 1.6,
        whiteSpace: 'pre-wrap',
        wordBreak: 'break-all',
      }}
    >
      {children}
    </pre>
  </div>
)
