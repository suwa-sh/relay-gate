import { Icon } from '../ui/Icon'

export interface HangDetectionNoticeProps {
  variant: 'banner' | 'email'
  runId: string
  anomalyType: string
  detectedAt: string
  thresholdMinutes: number
  slot: 'blue' | 'green'
  notifyTo: string
}

export const HangDetectionNotice = ({
  variant,
  runId,
  anomalyType,
  detectedAt,
  thresholdMinutes,
  slot,
  notifyTo,
}: HangDetectionNoticeProps) => {
  const body = (
    <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)' }}>
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontWeight: 'var(--font-weight-bold)' }}>
        <Icon name="alert-triangle" size={16} />
        異常検知: {anomalyType}
      </div>
      <dl style={{ margin: 'var(--space-2) 0 0', display: 'grid', gridTemplateColumns: 'auto 1fr', rowGap: 4, columnGap: 8 }}>
        <dt style={{ color: 'var(--foreground-secondary)' }}>run_id</dt>
        <dd style={{ fontFamily: 'var(--font-family-mono)' }}>{runId}</dd>
        <dt style={{ color: 'var(--foreground-secondary)' }}>検知日時</dt>
        <dd style={{ fontFamily: 'var(--font-family-mono)' }}>{detectedAt}</dd>
        <dt style={{ color: 'var(--foreground-secondary)' }}>しきい値</dt>
        <dd>{thresholdMinutes} 分</dd>
        <dt style={{ color: 'var(--foreground-secondary)' }}>対象slot</dt>
        <dd>{slot}</dd>
        <dt style={{ color: 'var(--foreground-secondary)' }}>通知先</dt>
        <dd>{notifyTo}</dd>
      </dl>
    </div>
  )

  if (variant === 'email') {
    return (
      <div style={{ width: '520px', maxWidth: '100%', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
        <div
          style={{
            display: 'flex',
            gap: 'var(--space-2)',
            alignItems: 'center',
            padding: 'var(--space-2) var(--space-4)',
            borderBottom: '1px solid var(--border)',
            background: 'var(--hover-muted)',
            fontSize: 'var(--font-size-xs)',
            color: 'var(--foreground-secondary)',
          }}
        >
          <Icon name="mail" size={14} />
          件名: [RelayGate] ハング検知通知 run_id={runId}
        </div>
        <div style={{ padding: 'var(--space-4)' }}>{body}</div>
      </div>
    )
  }

  return (
    <div
      style={{
        width: '480px',
        maxWidth: '100%',
        background: 'var(--banner-warning-bg)',
        color: 'var(--banner-warning-fg)',
        border: '1px solid var(--banner-warning-fg)',
        borderRadius: 'var(--radius-sm)',
        padding: 'var(--space-4)',
      }}
    >
      {body}
    </div>
  )
}
