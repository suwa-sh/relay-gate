import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { HangDetectionNotice } from './HangDetectionNotice'

const meta: Meta<typeof HangDetectionNotice> = {
  title: 'Domain/HangDetectionNotice',
  component: HangDetectionNotice,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof HangDetectionNotice>

const baseArgs = {
  runId: 'run-20260817-003',
  anomalyType: 'ハング疑い',
  detectedAt: '2026-08-17T09:40:00+09:00',
  thresholdMinutes: 30,
  slot: 'blue' as const,
  notifyTo: '運用者 / 移行運用責任者',
}

export const Banner: Story = { args: { variant: 'banner', ...baseArgs } }
export const Email: Story = { args: { variant: 'email', ...baseArgs } }
