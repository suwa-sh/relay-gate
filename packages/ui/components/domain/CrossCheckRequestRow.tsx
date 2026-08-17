import { StatusBadge, type Status } from '../ui/StatusBadge'

export interface CrossCheckRequest {
  runId: string
  jobIdOrTargetDate: string
  state: Status
  leaseExpiry: string
  workerId: string
}

export interface CrossCheckRequestRowProps {
  variant: 'rapid' | 'final'
  requests: CrossCheckRequest[]
}

export const CrossCheckRequestRow = ({ variant, requests }: CrossCheckRequestRowProps) => (
  <div style={{ width: '680px', maxWidth: '100%', overflowX: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
    <table style={{ width: '100%', borderCollapse: 'collapse', fontFamily: 'var(--font-family-sans)' }}>
      <thead>
        <tr style={{ background: 'var(--hover-muted)' }}>
          {['run_id', variant === 'rapid' ? 'JOB_ID' : '対象日', '状態', 'lease期限', 'worker'].map((h) => (
            <th
              key={h}
              style={{
                textAlign: 'left',
                padding: 'var(--space-2) var(--space-3)',
                fontSize: 'var(--font-size-xs)',
                color: 'var(--foreground-secondary)',
                fontWeight: 'var(--font-weight-medium)',
                borderBottom: '1px solid var(--border)',
              }}
            >
              {h}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {requests.map((r) => (
          <tr key={r.runId} style={{ borderBottom: '1px solid var(--border)' }}>
            <td style={{ padding: 'var(--space-2) var(--space-3)', fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>
              {r.runId}
            </td>
            <td style={{ padding: 'var(--space-2) var(--space-3)', fontSize: 'var(--font-size-sm)' }}>{r.jobIdOrTargetDate}</td>
            <td style={{ padding: 'var(--space-2) var(--space-3)' }}>
              <StatusBadge status={r.state} size="sm" />
            </td>
            <td style={{ padding: 'var(--space-2) var(--space-3)', fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>
              {r.leaseExpiry}
            </td>
            <td style={{ padding: 'var(--space-2) var(--space-3)', fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>
              {r.workerId}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)
