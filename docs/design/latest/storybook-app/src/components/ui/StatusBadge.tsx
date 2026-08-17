export type Status = 'running' | 'succeeded' | 'failed' | 'aborted' | 'requested' | 'claimed'
export type StatusBadgeSize = 'sm' | 'md'

const label: Record<Status, string> = {
  running: '実行中',
  succeeded: '正常終了',
  failed: '異常終了',
  aborted: '中止済み',
  requested: '依頼中',
  claimed: '取得済み',
}

const style: Record<Status, { background: string; color: string }> = {
  running: { background: 'var(--status-badge-running-bg)', color: 'var(--status-badge-running-fg)' },
  succeeded: { background: 'var(--status-badge-succeeded-bg)', color: 'var(--status-badge-succeeded-fg)' },
  failed: { background: 'var(--status-badge-failed-bg)', color: 'var(--status-badge-failed-fg)' },
  aborted: { background: 'var(--status-badge-aborted-bg)', color: 'var(--status-badge-aborted-fg)' },
  requested: { background: 'var(--status-badge-requested-bg)', color: 'var(--status-badge-requested-fg)' },
  claimed: { background: 'var(--status-badge-claimed-bg)', color: 'var(--status-badge-claimed-fg)' },
}

export interface StatusBadgeProps {
  status: Status
  size?: StatusBadgeSize
}

export const StatusBadge = ({ status, size = 'md' }: StatusBadgeProps) => {
  const s = style[status]
  return (
    <span
      style={{
        display: 'inline-block',
        background: s.background,
        color: s.color,
        borderRadius: 'var(--radius-sm)',
        padding: size === 'sm' ? '2px var(--space-2)' : '4px var(--space-3)',
        fontSize: size === 'sm' ? 'var(--font-size-xs)' : 'var(--font-size-sm)',
        fontFamily: 'var(--font-family-mono)',
        fontWeight: 'var(--font-weight-medium)',
        letterSpacing: '0.02em',
      }}
    >
      {status.toUpperCase()} / {label[status]}
    </span>
  )
}
