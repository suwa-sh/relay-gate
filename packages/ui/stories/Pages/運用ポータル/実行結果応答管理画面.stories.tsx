import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'
import { Banner } from '../../../components/ui/Banner'

/**
 * 実行結果応答管理画面（/cli/concurrent-run/respond-foreground）
 *
 * UC: foreground roleの標準出力・標準エラー・終了コードを応答する
 * - `relaygate concurrent-run respond-foreground --run-id <run_id>` の実行結果表示に対応する
 * - foreground役割のRunner実行結果から stdout/stderr/exitCode のみをジョブスケジューラへ応答する
 * - 運用性NFR「応答はstdout/stderr/exitcodeのみに限定」に対応し、比較結果・差分件数等の詳細は一切表示しない（RunnerResultPanel foreground variant）
 * - 本コマンドはexit_code_convention_exception対象。exitcode.txtの値を0を含む全値そのまま透過し、relay-gate自身のエラーだけを退避コード125（実行結果未確定・取得不能・中止済み・起動イベント送出失敗の補償記録であるFAILEDかつexit_code=NULL）/124（バリデーションエラー）へ分離する
 * - 起動UC（feature flag設定に基づきslotを選択して起動する）が送出失敗をFAILEDへ補償記録した試行はexit_code=NULLのため、
 *   非0のexit_codeを持つ通常のFAILED（業務エラー、そのまま透過）とは区別して退避コード125で応答する（CR-6078c4ed-012）
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/実行結果応答管理画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

/** foreground実行がexitcode=0で正常終了した応答（ダッシュボード） */
export const SucceededDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id run-20260817-001
        </div>
        <RunnerResultPanel
          runId="run-20260817-001"
          slot="blue"
          role="foreground"
          state="succeeded"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="batch job completed. rows_processed=48213"
          stderr=""
          exitCode={0}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行の非0終了コードをそのまま透過した応答（業務エラー、丸めない）（ダッシュボード） */
export const FailedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id run-20260817-002
        </div>
        <RunnerResultPanel
          runId="run-20260817-002"
          slot="green"
          role="foreground"
          state="failed"
          startedAt="2026-08-17T09:05:03+09:00"
          stdout="processing...\nfailed at step 3"
          stderr="Error: connection timeout after 30000ms"
          exitCode={3}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** 起動イベント送出失敗の補償記録（status=FAILEDかつexit_code=NULL）。非0exit_codeの通常FAILEDとは異なり退避コード125で応答する */
export const LaunchFailedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
        </div>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="blue"
          role="foreground"
          attemptId="att-blue-0001"
          attemptNo={1}
          state="failed"
          startedAt="2026-08-17T09:10:00+09:00"
          stdout=""
          stderr={
            '起動イベントの送出に失敗したため status=FAILED（exit_code=NULL）で補償記録されています\n' +
            '次アクション: リランするか実行環境の接続状態を確認してください'
          }
          exitCode={125}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行結果がまだ確定していない（relay-gate退避終了コード125。業務終了コード1への丸め写像ではない） */
export const UnresolvedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
        </div>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="blue"
          role="foreground"
          state="running"
          startedAt="2026-08-17T09:10:00+09:00"
          stdout=""
          stderr={'foreground実行結果が未確定です: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57\n次アクション: 実行完了後に再実行してください'}
          exitCode={125}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行結果がUNKNOWN（結果取得不能）。stderr.log内容とrelay-gateエラー内容（原因+次アクション）を併記し、退避コード125で応答する */
export const UnknownDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
        </div>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="blue"
          role="foreground"
          state="unknown"
          startedAt="2026-08-17T09:10:00+09:00"
          stdout=""
          stderr={
            'ssh: connect to host blue-host-01 port 22: Connection timed out\n' +
            'foreground実行結果を取得できません（status=UNKNOWN）\n' +
            '次アクション: 実結果を回収するか `relaygate concurrent-run result --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` で状態を確認してください'
          }
          exitCode={125}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行結果がABORTED（中止済み）。stderr.log取得不能時はrelay-gateエラー内容のみを出力し、退避コード125で応答する */
export const AbortedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
        </div>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="blue"
          role="foreground"
          state="aborted"
          startedAt="2026-08-17T09:10:00+09:00"
          stdout=""
          stderr={'foreground実行は中止済みです（status=ABORTED）\n次アクション: リランするか正規ジョブで再実行してください'}
          exitCode={125}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** run_id未指定によるrelay-gateバリデーションエラー（退避終了コード124。execution結果を参照できないためRunnerResultPanelは表示しない） */
export const ValidationErrorDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground
        </div>
        <Banner variant="error" title="run_id を指定してください">
          --run-id は必須です（終了コード124 / bash予約の126・127とは衝突しません）
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）でのforeground応答表示 */
export const SucceededHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <RunnerResultPanel
        runId="run-20260817-001"
        slot="blue"
        role="foreground"
        state="succeeded"
        startedAt="2026-08-17T09:00:12+09:00"
        stdout="batch job completed. rows_processed=48213"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
