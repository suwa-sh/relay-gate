import { TerminalPanel } from '../ui/TerminalPanel'
import { StatusBadge, type Status } from '../ui/StatusBadge'

// Runner実行結果identityは(run_id, slot, role, attempt)。実行状態はarch正本の6値
// (STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED)で、timeout後は推測でFAILEDを
// 表示せずunknownを明示する(state未指定時のみexitCodeから暫定導出する)
export type RunnerExecutionState = Extract<
  Status,
  'starting' | 'running' | 'succeeded' | 'failed' | 'unknown' | 'aborted'
>

export interface RunnerResultPanelProps {
  runId: string
  slot: 'blue' | 'green'
  role: 'foreground' | 'background'
  attemptId?: string
  attemptNo?: number
  state?: RunnerExecutionState
  startedAt: string
  stdout: string
  stderr: string
  exitCode: number | null
}

const stateOf = (exitCode: number | null): RunnerExecutionState => {
  if (exitCode === null) return 'running'
  return exitCode === 0 ? 'succeeded' : 'failed'
}

export const RunnerResultPanel = ({
  runId,
  slot,
  role,
  attemptId,
  attemptNo,
  state,
  startedAt,
  stdout,
  stderr,
  exitCode,
}: RunnerResultPanelProps) => (
  <div style={{ width: '560px', maxWidth: '100%' }}>
    <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', marginBottom: 'var(--space-2)', flexWrap: 'wrap' }}>
      <span style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-xs)', color: 'var(--foreground-secondary)' }}>
        run_id={runId} slot={slot} role={role}
        {attemptNo !== undefined ? ` attempt_no=${attemptNo}` : ''}
        {attemptId !== undefined ? ` attempt_id=${attemptId}` : ''}
        {` started_at=${startedAt}`}
      </span>
      <StatusBadge status={state ?? stateOf(exitCode)} size="sm" />
    </div>
    <TerminalPanel title={`stdout / stderr (exitcode=${exitCode === null ? '未確定' : exitCode})`}>
      {`$ stdout.log\n${stdout}\n\n$ stderr.log\n${stderr || '(なし)'}`}
    </TerminalPanel>
  </div>
)
