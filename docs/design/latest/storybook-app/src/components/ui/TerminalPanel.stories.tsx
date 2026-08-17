import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { TerminalPanel } from './TerminalPanel'

const meta: Meta<typeof TerminalPanel> = {
  title: 'UI/TerminalPanel',
  component: TerminalPanel,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof TerminalPanel>

export const Default: Story = {
  args: {
    title: 'stdout.log',
    children: '[INFO] blue background slot started (run_id=run-20260817-001)\n[INFO] exitcode=0\n[INFO] SUCCEEDED',
  },
}

export const Compact: Story = {
  args: { title: 'stderr.log', variant: 'compact', size: 'sm', children: '(なし)' },
}
