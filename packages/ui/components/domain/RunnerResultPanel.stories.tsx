import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { RunnerResultPanel } from './RunnerResultPanel'

const meta: Meta<typeof RunnerResultPanel> = {
  title: 'Domain/RunnerResultPanel',
  component: RunnerResultPanel,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof RunnerResultPanel>

export const Succeeded: Story = {
  args: {
    runId: 'run-20260817-001',
    slot: 'blue',
    role: 'foreground',
    startedAt: '2026-08-17T09:00:12+09:00',
    stdout: 'batch job completed. rows_processed=48213',
    stderr: '',
    exitCode: 0,
  },
}

export const Failed: Story = {
  args: {
    runId: 'run-20260817-002',
    slot: 'green',
    role: 'background',
    startedAt: '2026-08-17T09:05:03+09:00',
    stdout: 'processing...',
    stderr: 'Error: connection timeout after 30000ms',
    exitCode: 1,
  },
}

export const Running: Story = {
  args: {
    runId: 'run-20260817-003',
    slot: 'blue',
    role: 'background',
    startedAt: '2026-08-17T09:10:00+09:00',
    stdout: 'processing... (streaming)',
    stderr: '',
    exitCode: null,
  },
}

export const Starting: Story = {
  args: {
    runId: 'run-20260818-004',
    slot: 'green',
    role: 'background',
    attemptId: 'att-01J8ZK3Q',
    attemptNo: 1,
    state: 'starting',
    startedAt: '2026-08-18T09:00:00+09:00',
    stdout: '',
    stderr: '',
    exitCode: null,
  },
}

// timeout後は推測でFAILEDを確定せずUNKNOWNを明示する(CR-6078c4ed-005)
export const Unknown: Story = {
  args: {
    runId: 'run-20260818-005',
    slot: 'green',
    role: 'background',
    attemptId: 'att-01J8ZK7X',
    attemptNo: 2,
    state: 'unknown',
    startedAt: '2026-08-18T09:05:00+09:00',
    stdout: 'processing...',
    stderr: '',
    exitCode: null,
  },
}
