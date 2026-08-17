import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { ConfirmPrompt } from './ConfirmPrompt'

const meta: Meta<typeof ConfirmPrompt> = {
  title: 'UI/ConfirmPrompt',
  component: ConfirmPrompt,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof ConfirmPrompt>

export const Default: Story = {
  args: { target: 'run_id=run-20260817-001', message: 'blue background実行を中止します。' },
}

export const Destructive: Story = {
  args: {
    variant: 'destructive',
    target: 'run_id=run-20260817-001 slot=blue',
    message: '停止確認済みのblue background実行をABORTEDへ遷移させます。この操作は取消できません。',
  },
}
