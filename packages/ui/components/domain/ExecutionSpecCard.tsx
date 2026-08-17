export interface ExecutionSpecCardProps {
  runId: string
  jobId: string
  host: string
  script: string
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

export const ExecutionSpecCard = ({
  runId,
  jobId,
  host,
  script,
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
    <Row label="run_id" value={runId} />
    <Row label="JOB_ID" value={jobId} />
    <Row label="host" value={host} />
    <Row label="script" value={script} />
    <Row label="map版" value={mapVersion} />
    <Row label="実装版" value={implVersion} />
    <Row label="hang_detect_limit_minutes" value={hangDetectLimitMinutes} />
    <Row label="認証情報（参照名のみ）" value={credentialRef} />
  </div>
)
