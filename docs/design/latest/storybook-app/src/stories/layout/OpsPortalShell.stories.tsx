import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../components/common/OpsPortalShell'
import { RunnerResultPanel } from '../../components/domain/RunnerResultPanel'

const meta: Meta<typeof OpsPortalShell> = {
  title: 'Layout/OpsPortalShell',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

export const Dashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
    mapVersion: 'v1.4.0',
    implVersion: 'v1.4.0',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <RunnerResultPanel
        runId="run-20260817-blue-001"
        slot="blue"
        role="background"
        startedAt="2026-08-17T09:00:12+09:00"
        stdout="INFO job started\nINFO processing 1200 rows"
        stderr=""
        exitCode={null}
      />
    </OpsPortalShell>
  ),
}

export const Headless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <RunnerResultPanel
        runId="run-20260817-blue-001"
        slot="blue"
        role="foreground"
        startedAt="2026-08-17T09:00:12+09:00"
        stdout="INFO job started\nINFO processing 1200 rows\nINFO job succeeded"
        stderr=""
        exitCode={0}
      />
    </OpsPortalShell>
  ),
}
