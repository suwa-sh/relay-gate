import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow } from '../../../components/domain/CrossCheckRequestRow'
import { Banner } from '../../../components/ui/Banner'

/**
 * 速報比較依頼作成画面
 * route: /cli/rapid-crosscheck/create
 * UC: blue/green runnerの完了通知を受けて速報比較依頼を作成する（relaygate rapid-crosscheck create, CronJob起動）
 *
 * 新規作成した速報比較依頼を CrossCheckRequestRow（variant="rapid"）で一覧表示し、
 * 処理件数を Banner（info/success/error variant）で即時フィードバックする。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/速報比較依頼作成画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const CreatedDashboard: Story = {
  name: '依頼作成成功（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="success" title="速報比較依頼を2件作成しました">
        job_id=JOB-BATCH-0142, JOB-BATCH-0143（exitcode=0）
      </Banner>
      <div style={{ marginTop: 'var(--space-4)' }}>
        <CrossCheckRequestRow
          variant="rapid"
          requests={[
            { runId: 'run-20260817-rapid-021', jobIdOrTargetDate: 'JOB-BATCH-0142', state: 'requested', leaseExpiry: '-', workerId: '-' },
            { runId: 'run-20260817-rapid-022', jobIdOrTargetDate: 'JOB-BATCH-0143', state: 'requested', leaseExpiry: '-', workerId: '-' },
          ]}
        />
      </div>
    </OpsPortalShell>
  ),
}

export const NoneCreatedDashboard: Story = {
  name: '対象なし（正常終了0件）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="info" title="対象となる未依頼ジョブはありません">
        処理件数=0（exitcode=0）
      </Banner>
    </OpsPortalShell>
  ),
}

export const ModeOffDashboard: Story = {
  name: 'RAPID_CROSSCHECK_MODE=off（依頼を作成しない）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="info" title="速報クロスチェックは無効化されています">
        RAPID_CROSSCHECK_MODE=off のため、速報比較依頼は作成されませんでした。（exitcode=0）
      </Banner>
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: 'RDB接続エラー（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="rapid-crosscheck">
      <Banner variant="error" title="速報比較依頼の作成に失敗しました">
        Error: RDB接続エラー（exitcode=1）
      </Banner>
    </OpsPortalShell>
  ),
}

export const CreatedHeadless: Story = {
  name: '依頼作成成功（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <Banner variant="success" title="速報比較依頼を2件作成しました">
        job_id=JOB-BATCH-0142, JOB-BATCH-0143（exitcode=0）
      </Banner>
    </OpsPortalShell>
  ),
}
