import type { Meta, StoryObj } from '@storybook/nextjs-vite'
import { OpsPortalShell } from '../../../components/common/OpsPortalShell'
import { ExecutionSpecCard } from '../../../components/domain/ExecutionSpecCard'
import { RunnerResultPanel } from '../../../components/domain/RunnerResultPanel'
import { Banner } from '../../../components/ui/Banner'

/**
 * 起動slot選択画面（/cli/concurrent-run/select-slot）
 *
 * UC: feature flag設定に基づきslotを選択して起動する
 * - `relaygate concurrent-run select-slot --job-id <JOB_ID>` の実行結果表示に対応する
 * - BLUE_MODE/GREEN_MODE（off/background/foreground）とRAPID_CROSSCHECK_MODE（on/off）の組み合わせから
 *   execution-spec.jsonを確定・保存し起動する
 * - BLUE_MODE/GREEN_MODEを同時にforegroundにする組み合わせは業務ルール（SR-001）で拒否する（終了コード2）
 * - ジョブマップはslotごとの独立ファイル（RELAYGATE_JOB_MAP_PATH_BLUE/_GREEN）であり、job_map_versionは
 *   slot_execution_specsへslot別に保存する（CR-6078c4ed-018）
 * - 起動イベント送出に失敗した試行はFAILED、timeoutした試行はUNKNOWNへ本コマンドが補償記録する
 *   （標準出力のstatus=STARTING行は維持したまま、標準エラーで補償記録した旨を通知する。CR-6078c4ed-012）
 */
const meta: Meta<typeof OpsPortalShell> = {
  title: 'Pages/運用ポータル/起動slot選択画面',
  component: OpsPortalShell,
  tags: ['autodocs'],
  parameters: {
    layout: 'fullscreen',
  },
}
export default meta
type Story = StoryObj<typeof OpsPortalShell>

const concurrentSpec = {
  runId: 'run-20260817-001',
  jobId: 'JOB-2026-0817-001',
  host: 'batch-runner-01',
  script: '/opt/relaygate/bin/run.sh',
  mapVersion: 'v3',
  implVersion: 'v12',
  hangDetectLimitMinutes: 30,
  credentialRef: 'secrets/batch-runner/db-01',
}

/** BLUE_MODE=foreground, GREEN_MODE=background（並行稼働）でexecution-spec.jsonを確定する（ダッシュボード） */
export const ConcurrentModeDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id {concurrentSpec.jobId}
        </div>
        <Banner variant="success" title="slot選択が完了しました">
          blue: foreground / green: background / rapid_crosscheck: on
        </Banner>
        <ExecutionSpecCard {...concurrentSpec} />
      </div>
    </OpsPortalShell>
  ),
}

/** BLUE_MODE=off, GREEN_MODE=foreground（新実装単独本番）でexecution-spec.jsonを確定する（ダッシュボード） */
export const GreenSoloModeDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '新実装単独本番',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id JOB-2026-0817-004
        </div>
        <Banner variant="success" title="slot選択が完了しました">
          blue: off / green: foreground / rapid_crosscheck: off
        </Banner>
        <ExecutionSpecCard
          runId="run-20260817-004"
          jobId="JOB-2026-0817-004"
          host="green-runner-01"
          script="/opt/relaygate/bin/run.sh"
          mapVersion="v3"
          implVersion="v13"
          hangDetectLimitMinutes={30}
          credentialRef="secrets/green-runner/db-01"
        />
      </div>
    </OpsPortalShell>
  ),
}

/** BLUE_MODE/GREEN_MODE同時foreground拒否（バリデーションエラー、終了コード2、execution-spec.json未作成） */
export const BothForegroundRejectedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id JOB-2026-0817-003
        </div>
        <Banner variant="error" title="BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません">
          JOB_ID=JOB-2026-0817-003 のジョブマップ設定を見直してください（終了コード2 / execution-spec.jsonは作成されません）
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/** JOB_IDに対応するジョブマップが存在しない（業務エラー、終了コード1） */
export const JobMapUnresolvedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id JOB-UNKNOWN-999
        </div>
        <Banner variant="error" title="JOB_IDに対応するジョブマップが見つかりません">
          slot_type=green のジョブマップ（/etc/relaygate/job-map.green.json）に JOB_ID=JOB-UNKNOWN-999 は存在しません（終了コード1）
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/** slotごとの独立ジョブマップに必須フィールドが欠落している（バリデーションエラー、終了コード2） */
export const JobMapFieldMissingDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id daily-settlement
        </div>
        <Banner variant="error" title="ジョブマップの必須フィールドが欠落しています">
          slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.host（終了コード2 /
          execution-spec.jsonは作成されません）
        </Banner>
      </div>
    </OpsPortalShell>
  ),
}

/** 起動イベント送出失敗をFAILEDへ補償記録する（標準出力のstatus=STARTINGは維持、終了コード1） */
export const LaunchEventFailedDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id daily-settlement
        </div>
        <Banner variant="error" title="起動イベントの送出に失敗しました">
          slot_type=green attempt_id=att-green-0001 を FAILED として記録しました（終了コード1）
        </Banner>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="green"
          role="background"
          attemptId="att-green-0001"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 slot_type=green role=background attempt_id=att-green-0001 status=STARTING"
          stderr="Error: green実装ホストへのSSH起動イベント送出に失敗しました（slot_type=green attempt_id=att-green-0001 を FAILED として記録しました）"
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** 起動イベント送出timeoutをUNKNOWNへ補償記録する（推測でFAILEDにしない、終了コード124） */
export const LaunchEventTimeoutDashboard: Story = {
  args: {
    activeNavKey: 'concurrent-run',
    operationMode: '並行稼働',
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div style={{ fontFamily: 'var(--font-family-sans)', fontSize: 'var(--font-size-sm)', color: 'var(--foreground-secondary)' }}>
          relaygate concurrent-run select-slot --job-id daily-settlement
        </div>
        <Banner variant="warning" title="起動イベントの送出がtimeoutしました">
          slot_type=blue attempt_id=att-blue-0001 を UNKNOWN として記録しました（推測でFAILEDにはしません / 終了コード124）
        </Banner>
        <RunnerResultPanel
          runId="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
          slot="blue"
          role="foreground"
          attemptId="att-blue-0001"
          attemptNo={1}
          state="starting"
          startedAt="2026-08-17T09:00:12+09:00"
          stdout="run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 slot_type=blue role=foreground attempt_id=att-blue-0001 status=STARTING"
          stderr="Warning: blue実装ホストへのSSH起動イベント送出がtimeoutしました（slot_type=blue attempt_id=att-blue-0001 を UNKNOWN として記録しました）"
          exitCode={null}
        />
      </div>
    </OpsPortalShell>
  ),
}

/** CLI単体運用（ヘッドレス）でのslot選択完了表示 */
export const ConcurrentModeHeadless: Story = {
  args: {
    headless: true,
  },
  render: (args) => (
    <OpsPortalShell {...args}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Banner variant="success" title="slot選択が完了しました">
          blue: foreground / green: background / rapid_crosscheck: on
        </Banner>
        <ExecutionSpecCard {...concurrentSpec} />
      </div>
    </OpsPortalShell>
  ),
}
