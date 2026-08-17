import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { AbortConfirmDialog } from './AbortConfirmDialog'

const meta: Meta<typeof AbortConfirmDialog> = {
  title: 'Domain/AbortConfirmDialog',
  component: AbortConfirmDialog,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof AbortConfirmDialog>

export const BlueAbort: Story = {
  args: {
    runId: 'run-20260817-001',
    target: 'blue background実行',
    impactSummary: '停止確認済みのblue background実行をABORTEDへ遷移させます。',
  },
}

export const RapidCrossCheckAbort: Story = {
  args: {
    runId: 'run-20260817-002',
    target: '速報比較依頼',
    impactSummary: 'RUNNING中の速報比較依頼を中止します。',
  },
}
