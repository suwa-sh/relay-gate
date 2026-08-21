import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { ExecutionSpecCard } from '../../../components/domain/ExecutionSpecCard'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * リラン実行画面（/cli/rerun/run）
 *
 * UC: execution-spec.jsonの実行設定を保ったまま再実行する
 * - `relaygate rerun run --target background --run-id <元run_id>` の実行結果表示に対応する
 * - 元のexecution-spec.json（ExecutionSpecCard）を保ったまま新規run_id（parent_run_id=元run_id）で再実行を開始する
 * - 認証情報は参照名のみを表示し実値は表示しない
 * - 受理時は新規run_id・parent_run_id・attempt_id・attempt_no・status=STARTINGを表示する（起動確認前のためRUNNINGではなくSTARTING）
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/リラン実行画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const originalSpec = {
  runId: 'run-20260816-002',
  jobId: 'JOB-BATCH-0142',
  host: 'batch-runner-02',
  script: '/opt/relaygate/bin/run.sh',
  mapVersion: 'v3',
  implVersion: 'v12',
  hangDetectLimitMinutes: 30,
  credentialRef: 'secrets/batch-runner/db-01',
}

/** 元のexecution-spec.jsonを保ったまま新規run_id・parent_run_id=元run_idで発行される再実行後のspec */
const rerunSpec = {
  ...originalSpec,
  runId: 'run-20260817-011',
  parentRunId: originalSpec.runId,
}

/** 元execution-spec.jsonの設定を保ったまま再実行を受理し、新規run_id=RUNNINGで応答する（ダッシュボード） */
export const AcceptedDashboard: Story = {
  args: {
    activeNavKey: 'control',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate rerun run --target background --run-id {originalSpec.runId}
        </div>
        <ExecutionSpecCard {...rerunSpec} />
        <RunnerResultPanel
          runId={rerunSpec.runId}
          slot="blue"
          role="background"
          attemptId="att-blue-0002"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T10:15:00+09:00"
          stdout={`再実行を受理しました\nrun_id=${rerunSpec.runId}\nparent_run_id=${originalSpec.runId}\nattempt_id=att-blue-0002\nattempt_no=1\nstatus=STARTING`}
          stderr=""
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** 対象run_id未存在・SSH起動失敗による業務エラー（ダッシュボード） */
export const RerunFailedDashboard: Story = {
  args: {
    activeNavKey: 'control',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate rerun run --target background --run-id run-99999999-999
        </div>
        <RunnerResultPanel
          runId="run-99999999-999"
          slot="blue"
          role="background"
          startedAt="-"
          stdout=""
          stderr="Error: 対象run_idのexecution-spec.jsonが見つかりません"
          exitCode={1}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）での再実行受理表示 */
export const AcceptedHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <ExecutionSpecCard {...rerunSpec} />
        <RunnerResultPanel
          runId={rerunSpec.runId}
          slot="blue"
          role="background"
          attemptId="att-blue-0002"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T10:15:00+09:00"
          stdout={`再実行を受理しました\nrun_id=${rerunSpec.runId}\nparent_run_id=${originalSpec.runId}\nattempt_id=att-blue-0002\nattempt_no=1\nstatus=STARTING`}
          stderr=""
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}
