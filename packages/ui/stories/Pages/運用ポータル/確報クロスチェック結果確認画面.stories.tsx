import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow } from '../../../components/domain/CrossCheckRequestRow'
import { Banner } from '../../../components/ui/Banner'

/**
 * 確報クロスチェック結果確認画面
 * route: /cli/final-crosscheck/result
 * UC: 確報クロスチェック結果を確認する（relaygate final-crosscheck result --target-date）
 *
 * CrossCheckRequestRow は variant="final" で表示し、StatusBadge は内部で描画される。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/確報クロスチェック結果確認画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const SucceededDashboard: Story = {
  name: '照会成功・SUCCEEDED（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <CrossCheckRequestRow
        variant="final"
        requests={[
          { runId: 'run-20260817-final-014', jobIdOrTargetDate: '2026-08-17', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-03' },
        ]}
      />
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: '照会成功・FAILED（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <CrossCheckRequestRow
        variant="final"
        requests={[
          { runId: 'run-20260816-final-013', jobIdOrTargetDate: '2026-08-16', state: 'failed', leaseExpiry: '-', workerId: 'worker-02' },
        ]}
      />
    </OpsPortalShell>
  ),
}

export const NotFoundDashboard: Story = {
  name: '対象日の確報比較依頼が存在しない（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <Banner variant="error" title="対象日の確報比較依頼が存在しません">
        target-date=2026-08-10 の確報比較依頼は見つかりませんでした。（exitcode=1）
      </Banner>
    </OpsPortalShell>
  ),
}

export const ValidationErrorDashboard: Story = {
  name: 'target-date形式不正（バリデーションエラー）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <Banner variant="error" title="target-date形式不正">
        --target-date は YYYY-MM-DD 形式で指定してください。（exitcode=2）
      </Banner>
    </OpsPortalShell>
  ),
}

export const SucceededHeadless: Story = {
  name: '照会成功・SUCCEEDED（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <CrossCheckRequestRow
        variant="final"
        requests={[
          { runId: 'run-20260817-final-014', jobIdOrTargetDate: '2026-08-17', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-03' },
        ]}
      />
    </OpsPortalShell>
  ),
}
