import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'

/**
 * 確報結果応答画面
 * route: /cli/final-crosscheck/respond
 * UC: 確報クロスチェック結果をstdout/stderr/exitcodeで応答する（relaygate final-crosscheck respond）
 *
 * 運用性NFR「応答はstdout/stderr/exitcodeのみに限定」に対応するため、
 * RunnerResultPanel は foreground variant（差分件数・レポートURI等は一切含まない）で表示する。
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/確報結果応答画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const SucceededDashboard: Story = {
  name: '正常終了（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <RunnerResultPanel
        runId="run-20260817-final-014"
        slot="blue"
        role="foreground"
        startedAt="2026-08-17T06:00:03+09:00"
        stdout="確報比較結果: SUCCEEDED"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const FailedDashboard: Story = {
  name: '異常終了（ダッシュボード）',
  render: () => (
    <OpsPortalShell activeNavKey="final-crosscheck">
      <RunnerResultPanel
        runId="run-20260817-final-015"
        slot="green"
        role="foreground"
        startedAt="2026-08-17T06:00:05+09:00"
        stdout=""
        stderr="確報比較結果: FAILED"
        exitCode={1}
      />
    </OpsPortalShell>
  ),
}

export const SucceededHeadless: Story = {
  name: '正常終了（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <RunnerResultPanel
        runId="run-20260817-final-014"
        slot="blue"
        role="foreground"
        startedAt="2026-08-17T06:00:03+09:00"
        stdout="確報比較結果: SUCCEEDED"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}

export const UndeterminedHeadless: Story = {
  name: 'status未確定（headless / CLI単体運用）',
  render: () => (
    <OpsPortalShell headless>
      <RunnerResultPanel
        runId="run-20260817-final-016"
        slot="blue"
        role="foreground"
        startedAt="2026-08-17T06:00:07+09:00"
        stdout=""
        stderr="確報比較結果: 未確定"
        exitCode={1}
      />
    </OpsPortalShell>
  ),
}
