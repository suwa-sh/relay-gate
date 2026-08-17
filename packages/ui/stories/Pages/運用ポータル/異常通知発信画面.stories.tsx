import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { HangDetectionNotice } from '../../../components/domain/HangDetectionNotice'
import { Banner } from '../../../components/ui/Banner'

/**
 * 異常通知発信画面
 * route: /cli/hang-watch/notify
 * UC: ハング疑い・異常を運用者へ通知する（relaygate hang-watch notify, CronJob起動）
 *
 * notified_at未設定のハング検知記録を HangDetectionNotice で通知する。
 * banner/email 両variantを必ず用意する。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/異常通知発信画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const noticeArgs = {
  runId: 'run-20260817-blue-041',
  anomalyType: 'ハング疑い',
  detectedAt: '2026-08-17T10:30:00+09:00',
  thresholdMinutes: 30,
  slot: 'blue' as const,
  notifyTo: '運用者 / 移行運用責任者',
}

export const BannerDashboard: Story = {
  name: '通知（banner variant / ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <HangDetectionNotice variant="banner" {...noticeArgs} />
    </OpsPortalShell>
  ),
}

export const EmailDashboard: Story = {
  name: '通知（email variant / ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <HangDetectionNotice variant="email" {...noticeArgs} />
    </OpsPortalShell>
  ),
}

export const NoneToNotifyDashboard: Story = {
  name: '通知対象0件（正常終了）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <Banner variant="info" title="通知対象のハング検知記録はありません">
        通知件数=0（exitcode=0）
      </Banner>
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: '通知送信失敗・notified_at更新失敗（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <Banner variant="error" title="通知送信に失敗しました">
        run_id=run-20260817-blue-041 の通知送信に失敗しました（exitcode=1）
      </Banner>
    </OpsPortalShell>
  ),
}

export const BannerHeadless: Story = {
  name: '通知（banner variant / headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <HangDetectionNotice variant="banner" {...noticeArgs} />
    </OpsPortalShell>
  ),
}

export const EmailHeadless: Story = {
  name: '通知（email variant / headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <HangDetectionNotice variant="email" {...noticeArgs} />
    </OpsPortalShell>
  ),
}
