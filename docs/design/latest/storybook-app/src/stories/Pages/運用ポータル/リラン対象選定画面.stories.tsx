import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow, type CrossCheckRequest } from '../../../components/domain/CrossCheckRequestRow'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * リラン対象選定画面（/cli/rerun/select）
 *
 * UC: 再実行対象のbackground実行・速報比較依頼を選択する
 * - `relaygate rerun select --target background|rapid-crosscheck` の結果表示に対応する
 * - background対象: 完了済み・中止済みのRunner実行結果（RunnerResultPanel background variant）をattempt_id/attempt_no付きで候補一覧表示する
 * - rapid-crosscheck対象: 完了済み・中止済みの速報比較依頼（CrossCheckRequestRow rapid variant）を候補一覧表示する
 * - 候補0件時は「該当するリラン候補はありません」を表示する
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/リラン対象選定画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const backgroundCandidates = [
  {
    runId: 'run-20260815-004',
    slot: 'blue' as const,
    role: 'background' as const,
    attemptId: 'att-blue-0001',
    attemptNo: 1,
    state: 'succeeded' as const,
    startedAt: '2026-08-15T09:00:03+09:00',
    stdout: 'batch job completed. rows_processed=48213',
    stderr: '',
    exitCode: 0,
  },
  {
    runId: 'run-20260816-002',
    slot: 'green' as const,
    role: 'background' as const,
    attemptId: 'att-green-0003',
    attemptNo: 1,
    state: 'failed' as const,
    startedAt: '2026-08-16T09:00:05+09:00',
    stdout: 'processing...\nfailed at step 3',
    stderr: 'Error: connection timeout after 30000ms',
    exitCode: 1,
  },
  {
    runId: 'run-20260816-005',
    slot: 'blue' as const,
    role: 'background' as const,
    attemptId: 'att-blue-0007',
    attemptNo: 2,
    state: 'aborted' as const,
    startedAt: '2026-08-16T21:10:00+09:00',
    stdout: '中止操作により停止',
    stderr: '',
    exitCode: 130,
  },
]

const rapidCandidates: CrossCheckRequest[] = [
  { runId: 'run-20260815-004', jobIdOrTargetDate: 'JOB-BATCH-0142', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-rapid-01' },
  { runId: 'run-20260816-002', jobIdOrTargetDate: 'JOB-BATCH-0142', state: 'failed', leaseExpiry: '-', workerId: 'worker-rapid-02' },
]

/** background対象の再実行候補一覧（ダッシュボード表示） */
export const BackgroundCandidatesDashboard: Story = {
  args: {
    activeNavKey: 'control',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate rerun select --target background --status FAILED,ABORTED
        </div>
        {backgroundCandidates.map((c) => (
          <RunnerResultPanel key={c.runId} {...c} />
        ))}
      </div>
    </OpsPortalShell>
  ),
}

/** rapid-crosscheck対象の再実行候補一覧（ダッシュボード表示） */
export const RapidCrosscheckCandidatesDashboard: Story = {
  args: {
    activeNavKey: 'control',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate rerun select --target rapid-crosscheck
        </div>
        <CrossCheckRequestRow variant="rapid" requests={rapidCandidates} />
      </div>
    </OpsPortalShell>
  ),
}

/** 候補0件（stdout: 該当するリラン候補はありません） */
export const EmptyDashboard: Story = {
  args: {
    activeNavKey: 'control',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>
        relaygate rerun select --target background --status FAILED
        <br />
        該当するリラン候補はありません
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）でのbackground対象候補表示 */
export const BackgroundCandidatesHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {backgroundCandidates.map((c) => (
          <RunnerResultPanel key={c.runId} {...c} />
        ))}
      </div>
    </OpsPortalShell>
  ),
}
