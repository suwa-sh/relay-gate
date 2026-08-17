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
