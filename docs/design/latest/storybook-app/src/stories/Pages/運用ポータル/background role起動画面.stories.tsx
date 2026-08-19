import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { ExecutionSpecCard } from '../../../components/domain/ExecutionSpecCard'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * background role起動画面（/cli/concurrent-run/start-background）
 *
 * UC: background roleを起動する
 * - `relaygate concurrent-run start-background --run-id <run_id>` の実行結果表示に対応する
 * - execution-spec.jsonで確定済みのbackground対象slotについてworkerへ起動トリガーを送出する（tier-facade）
 * - トリガーを受けたworkerがbackground実行を開始しRunner実行結果を記録する（tier-worker）
 * - 起動受付時点の標準出力はattempt_id・attempt_noを伴うstatus=STARTINGを表示する（RUNNINGへの遷移は起動確認成功後）
 * - SSH起動タイムアウト等の結果取得不能時はUNKNOWNとして記録し、推測でFAILEDへ確定しない
 * - 認証情報は参照名のみを表示し実値は表示しない
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/background role起動画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const spec = {
  runId: 'run-20260817-020',
  jobId: 'JOB-BATCH-0142',
  host: 'green-runner-01',
  script: '/opt/relaygate/bin/run.sh',
  mapVersion: 'v3',
  implVersion: 'v13',
  hangDetectLimitMinutes: 30,
  credentialRef: 'secrets/green-runner/db-01',
}

/** 確定済みexecution-spec.jsonに基づきgreen slotのbackground実行を起動する（ダッシュボード） */
export const StartedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run start-background --run-id {spec.runId}
        </div>
        <ExecutionSpecCard {...spec} />
        <RunnerResultPanel
          runId={spec.runId}
          slot="green"
          role="background"
          attemptId="att-green-0001"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="background起動: run_id=run-20260817-020 slot_type=green attempt_id=att-green-0001 attempt_no=1 status=STARTING"
          stderr=""
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** SSH接続失敗・RDB書込み失敗による起動エラー（ダッシュボード） */
export const StartFailedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run start-background --run-id run-20260817-021
        </div>
        <RunnerResultPanel
          runId="run-20260817-021"
          slot="blue"
          role="background"
          attemptId="att-blue-0009"
          attemptNo={1}
          state="failed"
          startedAt="-"
          stdout=""
          stderr="Error: SSH接続に失敗しました（blue-runner-03, timeout）"
          exitCode={1}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** SSH起動タイムアウトによる結果取得不能（UNKNOWN。推測でFAILEDへ確定しない） */
export const StartUnknownDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run start-background --run-id run-20260817-022
        </div>
        <RunnerResultPanel
          runId="run-20260817-022"
          slot="blue"
          role="background"
          attemptId="att-blue-0010"
          attemptNo={1}
          state="unknown"
          startedAt="2026-08-17T09:05:00+09:00"
          stdout="background起動: run_id=run-20260817-022 slot_type=blue attempt_id=att-blue-0010 attempt_no=1 status=UNKNOWN"
          stderr="Warning: SSH起動確認がタイムアウトしました（結果取得不能。実結果の回収または対話確認による回復処理が必要）"
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）でのbackground起動表示 */
export const StartedHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <ExecutionSpecCard {...spec} />
        <RunnerResultPanel
          runId={spec.runId}
          slot="green"
          role="background"
          attemptId="att-green-0001"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="background起動: run_id=run-20260817-020 slot_type=green attempt_id=att-green-0001 attempt_no=1 status=STARTING"
          stderr=""
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}
