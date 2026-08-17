import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { ExecutionSpecCard } from './ExecutionSpecCard'

const meta: Meta<typeof ExecutionSpecCard> = {
  title: 'Domain/ExecutionSpecCard',
  component: ExecutionSpecCard,
  tags: ['autodocs'],
}
export default meta
type Story = StoryObj<typeof ExecutionSpecCard>

export const Default: Story = {
  args: {
    runId: 'run-20260817-001',
    jobId: 'JOB-BATCH-0142',
    host: 'batch-runner-01',
    script: '/opt/relaygate/bin/run.sh',
    mapVersion: 'v3',
    implVersion: 'v12',
    hangDetectLimitMinutes: 30,
    credentialRef: 'secrets/batch-runner/db-01',
  },
}
