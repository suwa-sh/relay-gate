import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'
import { StatusBadge } from '../../../components/ui/StatusBadge'

/**
 * 速報クロスチェック実行画面
 * route: /cli/rapid-crosscheck/run
 * UC: 速報クロスチェックを実行し差分を検知する（relaygate rapid-crosscheck run, CronJob起動）
 *
 * 実行ログ（run_id/comparison_result/diff_count）を RunnerResultPanel（background variant）で表示し、
 * 比較結果（OK/NG）を StatusBadge で併記する。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/速報クロスチェック実行画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const NoDiffDashboard: Story = {
  name: '差分なし・SUCCEEDED（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
        <span style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)' }}>比較結果:</span>
        <StatusBadge status="succeeded" />
      </div>
      <RunnerResultPanel
        runId="run-20260817-rapid-021"
        slot="blue"
        role="background"
        startedAt="2026-08-17T09:05:00+09:00"
        stdout="run_id=run-20260817-rapid-021 comparison_result=OK diff_count=0"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const DiffDetectedDashboard: Story = {
  name: '差分検知・FAILED（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', marginBottom: 'var(--space-2)' }}>
        <span style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)' }}>比較結果:</span>
        <StatusBadge status="failed" />
      </div>
      <RunnerResultPanel
        runId="run-20260817-rapid-022"
        slot="green"
        role="background"
        startedAt="2026-08-17T09:05:03+09:00"
        stdout="run_id=run-20260817-rapid-022 comparison_result=NG diff_count=37"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: 'RDB接続エラー等（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <RunnerResultPanel
        runId="run-20260817-rapid-023"
        slot="blue"
        role="background"
        startedAt="2026-08-17T09:05:10+09:00"
        stdout=""
        stderr="Error: 比較対象未確定 reason=RDB接続エラー"
        exitCode={1}
      />
    </OpsPortalShell>
  ),
}

export const NoTargetsDashboard: Story = {
  name: '対象なし（正常終了）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <RunnerResultPanel
        runId="run-20260817-rapid-000"
        slot="blue"
        role="background"
        startedAt="2026-08-17T09:05:00+09:00"
        stdout="対象となるREQUESTED状態の速報比較依頼はありません"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const DiffDetectedHeadless: Story = {
  name: '差分検知・FAILED（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <RunnerResultPanel
        runId="run-20260817-rapid-022"
        slot="green"
        role="background"
        startedAt="2026-08-17T09:05:03+09:00"
        stdout="run_id=run-20260817-rapid-022 comparison_result=NG diff_count=37"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
