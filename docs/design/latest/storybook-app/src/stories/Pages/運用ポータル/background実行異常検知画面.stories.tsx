import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { HangDetectionNotice } from '../../../components/domain/HangDetectionNotice'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * background実行異常検知画面
 * route: /cli/hang-watch/detect
 * UC: background実行の未完了・非0終了・速報比較異常を定期検知する（relaygate hang-watch detect, CronJob起動）
 *
 * 検知したハング疑い・異常を HangDetectionNotice（banner variant）で表示し、
 * 検知件数・種別サマリを RunnerResultPanel（background variant）で表示する。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/background実行異常検知画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const DetectedDashboard: Story = {
  name: '異常検知あり（ダッシュボード）',
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
      <div style={{ marginTop: 'var(--space-4)' }}>
        <RunnerResultPanel
          runId="run-20260817-hangwatch-088"
          slot="blue"
          role="background"
          startedAt="2026-08-17T10:30:00+09:00"
          stdout={'検知件数=2\nハング疑い: 1件\nbackground実行エラー: 1件'}
          stderr=""
          exitCode={0}
        />
      </div>
    </OpsPortalShell>
  ),
}

export const NoDetectionDashboard: Story = {
  name: '異常検知なし（正常終了）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <RunnerResultPanel
        runId="run-20260817-hangwatch-089"
        slot="blue"
        role="background"
        startedAt="2026-08-17T10:31:00+09:00"
        stdout="検知件数=0"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: 'RDB接続断・永続化失敗（業務エラー）',
  render: () => (
    <OpsPortalShell activeNavKey="hang-watch">
      <RunnerResultPanel
        runId="run-20260817-hangwatch-090"
        slot="blue"
        role="background"
        startedAt="2026-08-17T10:32:00+09:00"
        stdout=""
        stderr="Error: 検知記録の永続化に失敗しました reason=RDB接続断"
        exitCode={1}
      />
    </OpsPortalShell>
  ),
}

export const DetectedHeadless: Story = {
  name: '異常検知あり（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <RunnerResultPanel
        runId="run-20260817-hangwatch-088"
        slot="blue"
        role="background"
        startedAt="2026-08-17T10:30:00+09:00"
        stdout={'検知件数=2\nハング疑い: 1件\nbackground実行エラー: 1件'}
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
