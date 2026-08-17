import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { HangDetectionNotice } from '../../../components/domain/HangDetectionNotice'
import { Banner } from '../../../components/ui/Banner'

/**
 * ハング異常通知確認画面
 * route: /cli/hang-watch/notice
 * UC: ハング疑い・異常の通知を確認する（relaygate hang-watch notice [--run-id]）
 *
 * 通知済み（notified_at設定済み）のハング検知記録を検知日時降順で一覧表示する。
 * HangDetectionNotice（banner variant）を検知日時降順で複数件並べる。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/ハング異常通知確認画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const ListDashboard: Story = {
  name: '通知済み一覧・検知日時降順（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        <HangDetectionNotice
          variant="banner"
          runId="run-20260817-blue-041"
          anomalyType="ハング疑い"
          detectedAt="2026-08-17T10:30:00+09:00"
          thresholdMinutes={30}
          slot="blue"
          notifyTo="運用者 / 移行運用責任者"
        />
        <HangDetectionNotice
          variant="banner"
          runId="run-20260817-green-038"
          anomalyType="速報クロスチェック異常"
          detectedAt="2026-08-17T09:15:00+09:00"
          thresholdMinutes={5}
          slot="green"
          notifyTo="運用者 / 移行運用責任者"
        />
        <HangDetectionNotice
          variant="banner"
          runId="run-20260816-blue-029"
          anomalyType="background実行エラー"
          detectedAt="2026-08-16T22:05:00+09:00"
          thresholdMinutes={30}
          slot="blue"
          notifyTo="運用者 / 移行運用責任者"
        />
      </div>
    </OpsPortalShell>
  ),
}

export const FilteredByRunIdDashboard: Story = {
  name: '--run-id 指定で1件に絞り込み（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <HangDetectionNotice
        variant="banner"
        runId="run-20260817-blue-041"
        anomalyType="ハング疑い"
        detectedAt="2026-08-17T10:30:00+09:00"
        thresholdMinutes={30}
        slot="blue"
        notifyTo="運用者 / 移行運用責任者"
      />
    </OpsPortalShell>
  ),
}

export const EmptyDashboard: Story = {
  name: '該当なし（正常終了）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <Banner variant="info" title="該当するハング検知記録はありません" />
    </OpsPortalShell>
  ),
}

export const ValidationErrorDashboard: Story = {
  name: '--run-id 形式不正（バリデーションエラー）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <Banner variant="error" title="--run-id 形式不正">
        指定された run_id の形式が不正です。（exitcode=2）
      </Banner>
    </OpsPortalShell>
  ),
}

export const ListHeadless: Story = {
  name: '通知済み一覧（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        <HangDetectionNotice
          variant="banner"
          runId="run-20260817-blue-041"
          anomalyType="ハング疑い"
          detectedAt="2026-08-17T10:30:00+09:00"
          thresholdMinutes={30}
          slot="blue"
          notifyTo="運用者 / 移行運用責任者"
        />
        <HangDetectionNotice
          variant="banner"
          runId="run-20260817-green-038"
          anomalyType="速報クロスチェック異常"
          detectedAt="2026-08-17T09:15:00+09:00"
          thresholdMinutes={5}
          slot="green"
          notifyTo="運用者 / 移行運用責任者"
        />
      </div>
    </OpsPortalShell>
  ),
}
