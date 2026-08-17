import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { AbortConfirmDialog } from '../../../components/domain/AbortConfirmDialog'
import { Banner } from '../../../components/ui/Banner'

const meta: Meta = {
  title: 'Pages/運用ポータル/確報比較中止確認画面',
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj

/**
 * 対話確認の初期状態。AbortConfirmDialogで対象run_id・影響範囲・取消不可であることを明示し、
 * y/nの二択のみを許可する（対話確認スキップは禁止）。
 */
export const Dashboard: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <AbortConfirmDialog
        runId="run-20260817-final-011"
        target="確報比較依頼（対象日2026-08-16）"
        impactSummary="RUNNING中の確報比較依頼をABORTEDへ遷移させます。比較処理は即時停止し、以降の再開・リトライは新規依頼として扱われます。"
      />
    </OpsPortalShell>
  ),
}

/**
 * y応答によりABORTEDへの遷移が完了した状態。Banner(success)で結果を明示する。
 */
export const Success: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <AbortConfirmDialog
          runId="run-20260817-final-011"
          target="確報比較依頼（対象日2026-08-16）"
          impactSummary="RUNNING中の確報比較依頼をABORTEDへ遷移させます。比較処理は即時停止し、以降の再開・リトライは新規依頼として扱われます。"
        />
        <Banner variant="success" title="確報比較依頼をABORTEDへ遷移させました">
          run_id=run-20260817-final-011
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * n応答、または状態競合など業務エラーによりABORTEDへの遷移が行われなかった状態。
 */
export const Error: Story = {
  render: () => (
    <OpsPortalShell activeNavKey="control">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <AbortConfirmDialog
          runId="run-20260817-final-011"
          target="確報比較依頼（対象日2026-08-16）"
          impactSummary="RUNNING中の確報比較依頼をABORTEDへ遷移させます。比較処理は即時停止し、以降の再開・リトライは新規依頼として扱われます。"
        />
        <Banner variant="error" title="中止をキャンセルしました">
          n応答によりrun_id=run-20260817-final-011の状態は変更されていません（exit code 1）。
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/**
 * CLI単体運用時のヘッドレス表示。TTYプロンプト風のy/n二択のみを表示する。
 */
export const Headless: Story = {
  render: () => (
    <OpsPortalShell headless>
      <AbortConfirmDialog
        runId="run-20260817-final-011"
        target="確報比較依頼（対象日2026-08-16）"
        impactSummary="RUNNING中の確報比較依頼をABORTEDへ遷移させます。比較処理は即時停止し、以降の再開・リトライは新規依頼として扱われます。"
      />
    </OpsPortalShell>
  ),
}
