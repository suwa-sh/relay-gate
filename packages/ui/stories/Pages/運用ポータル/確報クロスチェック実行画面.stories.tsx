import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow } from '../../../components/domain/CrossCheckRequestRow'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * 確報クロスチェック実行画面
 * route: /cli/final-crosscheck/run
 * UC: 全テーブル・全ファイルを対象に確報クロスチェックを実行する（relaygate final-crosscheck run, CronJob起動）
 *
 * lease/claim取得した対象を CrossCheckRequestRow（variant="final"）で一覧表示し、
 * 実行ログ（run_id/status）を RunnerResultPanel（background variant）で表示する。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/確報クロスチェック実行画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const SucceededDashboard: Story = {
  name: '比較処理完了（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <CrossCheckRequestRow
        variant="final"
        requests={[
          { runId: 'run-20260817-final-014', jobIdOrTargetDate: '2026-08-17', state: 'succeeded', leaseExpiry: '2026-08-17T06:10:00+09:00', workerId: 'worker-03' },
        ]}
      />
      <div style={{ marginTop: 'var(--space-4)' }}>
        <RunnerResultPanel
          runId="run-20260817-final-014"
          slot="blue"
          role="background"
          startedAt="2026-08-17T06:00:00+09:00"
          stdout="run_id=run-20260817-final-014 status=SUCCEEDED"
          stderr=""
          exitCode={0}
        />
      </div>
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: '比較対象データ取得失敗（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <CrossCheckRequestRow
        variant="final"
        requests={[
          { runId: 'run-20260817-final-015', jobIdOrTargetDate: '2026-08-17', state: 'failed', leaseExpiry: '2026-08-17T06:10:00+09:00', workerId: 'worker-01' },
        ]}
      />
      <div style={{ marginTop: 'var(--space-4)' }}>
        <RunnerResultPanel
          runId="run-20260817-final-015"
          slot="green"
          role="background"
          startedAt="2026-08-17T06:00:00+09:00"
          stdout=""
          stderr="Error: 比較対象データ取得失敗 table=orders reason=connection timeout"
          exitCode={1}
        />
      </div>
    </OpsPortalShell>
  ),
}

export const NoTargetsDashboard: Story = {
  name: '対象依頼なし（正常終了）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <RunnerResultPanel
        runId="run-20260817-final-000"
        slot="blue"
        role="background"
        startedAt="2026-08-17T06:00:00+09:00"
        stdout="対象となるREQUESTED状態の確報比較依頼はありません"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const SucceededHeadless: Story = {
  name: '比較処理完了（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <RunnerResultPanel
        runId="run-20260817-final-014"
        slot="blue"
        role="background"
        startedAt="2026-08-17T06:00:00+09:00"
        stdout="run_id=run-20260817-final-014 status=SUCCEEDED"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
