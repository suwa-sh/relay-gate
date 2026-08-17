import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * 実行結果応答管理画面（/cli/concurrent-run/respond-foreground）
 *
 * UC: foreground roleの標準出力・標準エラー・終了コードを応答する
 * - `relaygate concurrent-run respond-foreground --run-id <run_id>` の実行結果表示に対応する
 * - foreground役割のRunner実行結果から stdout/stderr/exitCode のみをジョブスケジューラへ応答する
 * - 運用性NFR「応答はstdout/stderr/exitcodeのみに限定」に対応し、比較結果・差分件数等の詳細は一切表示しない（RunnerResultPanel foreground variant）
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
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="batch job completed. rows_processed=48213"
          stderr=""
          exitCode={0}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行がexitcode非0で異常終了した応答（ダッシュボード） */
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
          startedAt="2026-08-17T09:05:03+09:00"
          stdout="processing...\nfailed at step 3"
          stderr="Error: connection timeout after 30000ms"
          exitCode={1}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** foreground実行結果が未確定（業務エラー、終了コード1） */
export const UnresolvedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run respond-foreground --run-id run-20260817-003
        </div>
        <RunnerResultPanel
          runId="run-20260817-003"
          slot="blue"
          role="foreground"
          startedAt="2026-08-17T09:10:00+09:00"
          stdout=""
          stderr="Error: foreground実行結果が未確定です"
          exitCode={1}
        />
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
        startedAt="2026-08-17T09:00:12+09:00"
        stdout="batch job completed. rows_processed=48213"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
