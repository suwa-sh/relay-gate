// run共通execution specとslot別実行設定を分離して表示する。再実行では系譜(parent_run_id)を明示する。
// 認証情報は参照名のみ表示し実値は表示しない
export interface ExecutionSpecCardProps {
  runId: string
  parentRunId?: string
  jobId: string
  slot?: 'blue' | 'green'
  host: string
  execUser?: string
  script: string
  workDir?: string
  mapVersion: string
  implVersion: string
  hangDetectLimitMinutes: number
  credentialRef: string
}

const Row = ({ label, value }: { label: string; value: string | number }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--border)' }}>
    <span style={{ color: 'var(--foreground-secondary)', fontSize: 'var(--font-size-xs)' }}>{label}</span>
    <span style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-sm)' }}>{value}</span>
  </div>
)

const SectionLabel = ({ children }: { children: string }) => (
  <div
    style={{
      fontSize: 'var(--font-size-xs)',
      fontWeight: 'var(--font-weight-medium)',
      color: 'var(--foreground-secondary)',
      margin: 'var(--space-3) 0 var(--space-1)',
    }}
  >
    {children}
  </div>
)

export const ExecutionSpecCard = ({
  runId,
  parentRunId,
  jobId,
  slot,
  host,
  execUser,
  script,
  workDir,
  mapVersion,
  implVersion,
  hangDetectLimitMinutes,
  credentialRef,
}: ExecutionSpecCardProps) => (
  <div
    style={{
      width: '420px',
      maxWidth: '100%',
      background: 'var(--background)',
      border: '1px solid var(--border)',
      borderRadius: 'var(--radius-sm)',
      padding: 'var(--space-4)',
      fontFamily: 'var(--font-family-sans)',
    }}
  >
    <div style={{ fontSize: 'var(--font-size-sm)', fontWeight: 'var(--font-weight-bold)', marginBottom: 'var(--space-2)' }}>
      execution-spec.json
    </div>
    <SectionLabel>run共通</SectionLabel>
    <Row label="run_id" value={runId} />
    {parentRunId !== undefined && <Row label="parent_run_id（再実行元）" value={parentRunId} />}
    <Row label="JOB_ID" value={jobId} />
    <Row label="map版" value={mapVersion} />
    <Row label="hang_detect_limit_minutes" value={hangDetectLimitMinutes} />
    <Row label="認証情報（参照名のみ）" value={credentialRef} />
    <SectionLabel>slot別実行設定</SectionLabel>
    {slot !== undefined && <Row label="slot" value={slot} />}
    <Row label="host" value={host} />
    {execUser !== undefined && <Row label="実行ユーザー" value={execUser} />}
    <Row label="script" value={script} />
    {workDir !== undefined && <Row label="作業ディレクトリ" value={workDir} />}
    <Row label="実装版" value={implVersion} />
  </div>
)
