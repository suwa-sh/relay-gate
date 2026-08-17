import { TerminalPanel } from '../ui/TerminalPanel'
import { StatusBadge, type Status } from '../ui/StatusBadge'

export interface RunnerResultPanelProps {
  runId: string
  slot: 'blue' | 'green'
  role: 'foreground' | 'background'
  startedAt: string
  stdout: string
  stderr: string
  exitCode: number | null
}

const stateOf = (exitCode: number | null): Status => {
  if (exitCode === null) return 'running'
  return exitCode === 0 ? 'succeeded' : 'failed'
}

export const RunnerResultPanel = ({ runId, slot, role, startedAt, stdout, stderr, exitCode }: RunnerResultPanelProps) => (
  <div style={{ width: '560px', maxWidth: '100%' }}>
    <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
      <span style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-xs)', color: 'var(--foreground-secondary)' }}>
        run_id={runId} slot={slot} role={role} started_at={startedAt}
      </span>
      <StatusBadge status={stateOf(exitCode)} size="sm" />
    </div>
    <TerminalPanel title={`stdout / stderr (exitcode=${exitCode === null ? '未確定' : exitCode})`}>
      {`$ stdout.log\n${stdout}\n\n$ stderr.log\n${stderr || '(なし)'}`}
    </TerminalPanel>
  </div>
)
