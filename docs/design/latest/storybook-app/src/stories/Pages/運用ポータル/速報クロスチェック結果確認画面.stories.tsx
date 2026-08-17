import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow } from '../../../components/domain/CrossCheckRequestRow'
import { Banner } from '../../../components/ui/Banner'

/**
 * 速報クロスチェック結果確認画面
 * route: /cli/rapid-crosscheck/result
 * UC: 速報クロスチェック結果を確認する（relaygate rapid-crosscheck result --job-id / --run-id）
 *
 * CrossCheckRequestRow は variant="rapid" で表示し、StatusBadge は内部で描画される。
 * comparison_result / diff_count / diff_detail_uri は共通コンポーネントの表現範囲外のため、
 * 表の下部に補足情報として併記する（Progressive Disclosure）。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/速報クロスチェック結果確認画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const detailTextStyle = {
  marginTop: 'var(--space-3)',
  fontFamily: 'var(--font-family-mono)',
  fontSize: 'var(--font-size-xs)',
  color: 'var(--foreground-secondary)',
} as const

export const OkDashboard: Story = {
  name: '比較結果OK（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <CrossCheckRequestRow
        variant="rapid"
        requests={[
          { runId: 'run-20260817-rapid-021', jobIdOrTargetDate: 'JOB-BATCH-0142', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-01' },
        ]}
      />
      <div style={detailTextStyle}>comparison_result=OK diff_count=0</div>
    </OpsPortalShell>
  ),
}

export const NgDashboard: Story = {
  name: '比較結果NG（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <CrossCheckRequestRow
        variant="rapid"
        requests={[
          { runId: 'run-20260817-rapid-022', jobIdOrTargetDate: 'JOB-BATCH-0143', state: 'failed', leaseExpiry: '-', workerId: 'worker-02' },
        ]}
      />
      <div style={detailTextStyle}>
        comparison_result=NG diff_count=37 diff_detail_uri=s3://relaygate-reports/rapid/run-20260817-rapid-022/diff.json
      </div>
    </OpsPortalShell>
  ),
}

export const NotFoundDashboard: Story = {
  name: '対象が見つからない（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="error" title="対象の速報比較依頼が存在しません">
        job_id=JOB-BATCH-9999 に該当する速報比較依頼は見つかりませんでした。（exitcode=1）
      </Banner>
    </OpsPortalShell>
  ),
}

export const ValidationErrorDashboard: Story = {
  name: '引数未指定（バリデーションエラー）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="error" title="引数未指定">
        --job-id または --run-id のいずれかを指定してください。（exitcode=2）
      </Banner>
    </OpsPortalShell>
  ),
}

export const NgHeadless: Story = {
  name: '比較結果NG（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <CrossCheckRequestRow
        variant="rapid"
        requests={[
          { runId: 'run-20260817-rapid-022', jobIdOrTargetDate: 'JOB-BATCH-0143', state: 'failed', leaseExpiry: '-', workerId: 'worker-02' },
        ]}
      />
      <div style={detailTextStyle}>
        comparison_result=NG diff_count=37 diff_detail_uri=s3://relaygate-reports/rapid/run-20260817-rapid-022/diff.json
      </div>
    </OpsPortalShell>
  ),
}
