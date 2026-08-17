import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { ResultTable } from './ResultTable'

const meta: Meta<typeof ResultTable> = {
  title: 'UI/ResultTable',
  component: ResultTable,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof ResultTable>

export const Default: Story = {
  args: {
    columns: [
      { key: 'runId', label: 'run_id' },
      { key: 'slot', label: 'slot' },
      { key: 'exitCode', label: 'exitcode' },
    ],
    rows: [
      { runId: 'run-20260817-001', slot: 'blue', exitCode: '0' },
      { runId: 'run-20260817-001', slot: 'green', exitCode: '0' },
    ],
  },
}

export const Compact: Story = {
  args: { ...Default.args, variant: 'compact' },
}
