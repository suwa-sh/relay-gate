import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { StatusBadge, type Status } from './StatusBadge'

const meta: Meta<typeof StatusBadge> = {
  title: 'UI/StatusBadge',
  component: StatusBadge,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof StatusBadge>

export const Running: Story = { args: { status: 'running' } }
export const Succeeded: Story = { args: { status: 'succeeded' } }
export const Failed: Story = { args: { status: 'failed' } }
export const Aborted: Story = { args: { status: 'aborted' } }
export const Requested: Story = { args: { status: 'requested' } }
export const Claimed: Story = { args: { status: 'claimed' } }

const allStatuses: Status[] = ['requested', 'claimed', 'running', 'succeeded', 'failed', 'aborted']

export const AllStates: Story = {
  render: () => (
    <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
      {allStatuses.map((s) => (
        <StatusBadge key={s} status={s} />
      ))}
    </div>
  ),
}
