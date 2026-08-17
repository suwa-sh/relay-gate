import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { CrossCheckRequestRow } from '../../../components/domain/CrossCheckRequestRow'
import { Button } from '../../../components/ui/Button'
import { Banner } from '../../../components/ui/Banner'
import { TerminalPanel } from '../../../components/ui/TerminalPanel'

const meta: Meta = {
  title: 'Pages/運用ポータル/確報比較中止依頼画面',
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj

/**
 * 中止依頼前の初期状態。対象run_id・対象日・現在状態（RUNNING）をCrossCheckRequestRowで再確認し、
 * destructive variant の Button で中止依頼を確定する導線を示す。
 */
export const Dashboard: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <CrossCheckRequestRow
          variant="final"
          requests={[
            {
              runId: 'run-20260817-final-011',
              jobIdOrTargetDate: '2026-08-16',
              state: 'running',
              leaseExpiry: '2026-08-17T09:40:00+09:00',
              workerId: 'worker-final-01',
            },
          ]}
        />
        <div>
          <Button variant="destructive" size="md">
            確報比較依頼の中止を依頼する
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
        <CrossCheckRequestRow
          variant="final"
          requests={[
            {
              runId: 'run-20260817-final-011',
              jobIdOrTargetDate: '2026-08-16',
              state: 'running',
              leaseExpiry: '2026-08-17T09:40:00+09:00',
              workerId: 'worker-final-01',
            },
          ]}
        />
        <div>
          <Button variant="destructive" size="md">
            確報比較依頼の中止を依頼する
          </Button>
        </div>
        <Banner variant="info" title="中止依頼を受理しました">
          run_id=run-20260817-final-011（対象日2026-08-16）の中止依頼を受理しました。続けて対話確認画面（confirmコマンド）でABORTEDへの遷移を確定してください。
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
        <CrossCheckRequestRow
          variant="final"
          requests={[
            {
              runId: 'run-20260817-final-007',
              jobIdOrTargetDate: '2026-08-15',
              state: 'failed',
              leaseExpiry: '2026-08-15T19:10:00+09:00',
              workerId: 'worker-final-02',
            },
          ]}
        />
        <div>
          <Button variant="destructive" size="md">
            確報比較依頼の中止を依頼する
          </Button>
        </div>
        <Banner variant="error" title="中止依頼を拒否しました">
          対象の確報比較依頼（run_id=run-20260817-final-007、対象日2026-08-15）は状態がFAILEDです。RUNNING中の依頼のみ中止依頼を受け付けます（exit code 1）。
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * CLI単体運用時のヘッドレス表示。relaygate abort final-crosscheck request コマンドの標準出力を再現する。
 */
export const Headless: Story = {
  render: () => (
    <OpsPortalShell headless>
      <TerminalPanel title="$ relaygate abort final-crosscheck request --run-id=run-20260817-final-011">
        {'中止依頼受理: run-20260817-final-011 対象日=2026-08-16 状態=RUNNING\n次アクション: relaygate abort final-crosscheck confirm --run-id=run-20260817-final-011'}
      </TerminalPanel>
    </OpsPortalShell>
  ),
}
