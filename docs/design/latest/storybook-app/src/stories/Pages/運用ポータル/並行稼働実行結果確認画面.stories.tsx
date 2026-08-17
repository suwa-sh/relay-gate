import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'
import { StatusBadge } from '../../../components/ui/StatusBadge'

/**
 * 並行稼働実行結果確認画面（/cli/concurrent-run/result）
 *
 * UC: 並行稼働実行結果を確認する
 * - `relaygate concurrent-run result --job-id <JOB_ID>` または `--run-id <run_id>` の実行結果表示に対応する
 * - slot_typeごとにセクション分割した実行結果一覧を表示する
 * - blue/greenのslot間結果比較を横並びで提示する（ux-design.md の改善機会に対応）
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/並行稼働実行結果確認画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

/** blue（foreground）/ green（background）の実行結果をslotごとに横並び比較する（ダッシュボード） */
export const BlueGreenComparisonDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run result --job-id JOB-2026-0817-001
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-6)', flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <span style={{ fontFamily: 'var(--font-family-sans)', fontWeight: 'var(--font-weight-bold)', fontSize: 'var(--font-size-sm)' }}>
                blue（foreground）
              </span>
              <StatusBadge status="succeeded" size="sm" />
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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <span style={{ fontFamily: 'var(--font-family-sans)', fontWeight: 'var(--font-weight-bold)', fontSize: 'var(--font-size-sm)' }}>
                green（background）
              </span>
              <StatusBadge status="running" size="sm" />
            </div>
            <RunnerResultPanel
              runId="run-20260817-001"
              slot="green"
              role="background"
              startedAt="2026-08-17T09:00:15+09:00"
              stdout="processing... 32000/48213 rows"
              stderr=""
              exitCode={null}
            />
          </div>
        </div>
      </div>
    </OpsPortalShell>
  ),
}

/** blue/greenの結果が乖離している（green異常終了）ケース（ダッシュボード） */
export const BlueGreenDivergedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run result --job-id JOB-2026-0817-002
        </div>
        <div style={{ display: 'flex', gap: 'var(--space-6)', flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <span style={{ fontFamily: 'var(--font-family-sans)', fontWeight: 'var(--font-weight-bold)', fontSize: 'var(--font-size-sm)' }}>
                blue（foreground）
              </span>
              <StatusBadge status="succeeded" size="sm" />
            </div>
            <RunnerResultPanel
              runId="run-20260817-002"
              slot="blue"
              role="foreground"
              startedAt="2026-08-17T09:05:00+09:00"
              stdout="batch job completed. rows_processed=48310"
              stderr=""
              exitCode={0}
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <span style={{ fontFamily: 'var(--font-family-sans)', fontWeight: 'var(--font-weight-bold)', fontSize: 'var(--font-size-sm)' }}>
                green（background）
              </span>
              <StatusBadge status="failed" size="sm" />
            </div>
            <RunnerResultPanel
              runId="run-20260817-002"
              slot="green"
              role="background"
              startedAt="2026-08-17T09:05:03+09:00"
              stdout="processing...\nfailed at step 3"
              stderr="Error: connection timeout after 30000ms"
              exitCode={1}
            />
          </div>
        </div>
      </div>
    </OpsPortalShell>
  ),
}

/** 該当データなし（業務エラー、終了コード1） */
export const NotFoundDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>
        relaygate concurrent-run result --run-id run-99999999-999
        <br />
        Error: 指定されたrun_idに該当する実行結果が見つかりません
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）でのblue/green比較表示 */
export const BlueGreenComparisonHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', gap: 'var(--space-6)', flexWrap: 'wrap' }}>
        <RunnerResultPanel
          runId="run-20260817-001"
          slot="blue"
          role="foreground"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="batch job completed. rows_processed=48213"
          stderr=""
          exitCode={0}
        />
        <RunnerResultPanel
          runId="run-20260817-001"
          slot="green"
          role="background"
          startedAt="2026-08-17T09:00:15+09:00"
          stdout="processing... 32000/48213 rows"
          stderr=""
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}
