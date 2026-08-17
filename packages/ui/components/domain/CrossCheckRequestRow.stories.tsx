import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { CrossCheckRequestRow } from './CrossCheckRequestRow'

const meta: Meta<typeof CrossCheckRequestRow> = {
  title: 'Domain/CrossCheckRequestRow',
  component: CrossCheckRequestRow,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof CrossCheckRequestRow>

export const Rapid: Story = {
  args: {
    variant: 'rapid',
    requests: [
      { runId: 'run-20260817-001', jobIdOrTargetDate: 'JOB-BATCH-0142', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-01' },
      { runId: 'run-20260817-002', jobIdOrTargetDate: 'JOB-BATCH-0143', state: 'failed', leaseExpiry: '-', workerId: 'worker-02' },
      { runId: 'run-20260817-003', jobIdOrTargetDate: 'JOB-BATCH-0144', state: 'running', leaseExpiry: '2026-08-17T09:20:00', workerId: 'worker-01' },
      { runId: 'run-20260817-004', jobIdOrTargetDate: 'JOB-BATCH-0145', state: 'requested', leaseExpiry: '-', workerId: '-' },
    ],
  },
}

export const Final: Story = {
  args: {
    variant: 'final',
    requests: [
      { runId: 'run-20260817-005', jobIdOrTargetDate: '2026-08-17', state: 'succeeded', leaseExpiry: '-', workerId: 'worker-03' },
      { runId: 'run-20260816-005', jobIdOrTargetDate: '2026-08-16', state: 'aborted', leaseExpiry: '-', workerId: 'worker-03' },
    ],
  },
}
