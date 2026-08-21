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

// run共通specとslot別実行設定の分離表示 + 再実行系譜(parent_run_id)の明示(CR-6078c4ed-003/005)
export const SlotConfigWithLineage: Story = {
  args: {
    runId: 'run-20260818-010',
    parentRunId: 'run-20260817-002',
    jobId: 'JOB-BATCH-0142',
    slot: 'green',
    host: 'batch-runner-02',
    execUser: 'relaygate',
    script: '/opt/relaygate-green/bin/run.sh',
    workDir: '/var/relaygate/green/work',
    mapVersion: 'v3',
    implVersion: 'v13',
    hangDetectLimitMinutes: 30,
    credentialRef: 'secrets/batch-runner/db-01',
  },
}
