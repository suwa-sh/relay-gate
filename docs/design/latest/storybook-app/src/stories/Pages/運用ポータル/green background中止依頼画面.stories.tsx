import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'
import { Button } from '../../../components/ui/Button'
import { Banner } from '../../../components/ui/Banner'
import { TerminalPanel } from '../../../components/ui/TerminalPanel'

const meta: Meta = {
  title: 'Pages/運用ポータル/green background中止依頼画面',
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj

const runningTarget = {
  runId: 'run-20260817-green-021',
  slot: 'green' as const,
  role: 'background' as const,
  startedAt: '2026-08-17T09:05:40+09:00',
  stdout: 'INFO job started\nINFO processing 4198 rows',
  stderr: '',
  exitCode: null,
}

/**
 * 中止依頼前の初期状態。対象run_id・現在状態（RUNNING）を再確認し、
 * destructive variant の Button で中止依頼を確定する導線を示す。
 */
export const Dashboard: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <RunnerResultPanel {...runningTarget} />
        <div>
          <Button variant="destructive" size="md">
            green background実行の中止を依頼する
          </Button>
        </div>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * 中止依頼が受理された直後。Banner(info)で受理結果と次アクション（対話確認画面への遷移）を案内する。
 */
export const Accepted: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <RunnerResultPanel {...runningTarget} />
        <div>
          <Button variant="destructive" size="md">
            green background実行の中止を依頼する
          </Button>
        </div>
        <Banner variant="info" title="中止依頼を受理しました">
          run_id=run-20260817-green-021 の中止依頼を受理しました。続けて対話確認画面（confirmコマンド）でABORTEDへの遷移を確定してください。
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * バリデーションエラー: 対象状態がRUNNING以外（既にFAILED）のため中止依頼を拒否する業務エラー。
 */
export const ValidationError: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <RunnerResultPanel
          runId="run-20260817-green-018"
          slot="green"
          role="background"
          startedAt="2026-08-17T06:12:09+09:00"
          stdout="INFO job started"
          stderr="ERROR connection refused"
          exitCode={1}
        />
        <div>
          <Button variant="destructive" size="md">
            green background実行の中止を依頼する
          </Button>
        </div>
        <Banner variant="error" title="中止依頼を拒否しました">
          対象のgreen background実行（run_id=run-20260817-green-018）は状態がFAILEDです。RUNNING中の実行のみ中止依頼を受け付けます（exit code 1）。
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * CLI単体運用時のヘッドレス表示。relaygate abort green request コマンドの標準出力を再現する。
 */
export const Headless: Story = {
  render: () => (
    <OpsPortalShell headless>
      <TerminalPanel title="$ relaygate abort green request --run-id=run-20260817-green-021">
        {'中止依頼受理: run-20260817-green-021\n次アクション: relaygate abort green confirm --run-id=run-20260817-green-021'}
      </TerminalPanel>
    </OpsPortalShell>
  ),
}
