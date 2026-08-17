export interface ResultTableColumn {
  key: string
  label: string
}

export interface ResultTableProps {
  variant?: 'default' | 'compact'
  columns: ResultTableColumn[]
  rows: Record<string, string>[]
}

export const ResultTable = ({ variant = 'default', columns, rows }: ResultTableProps) => (
  <div style={{ overflowX: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
    <table style={{ width: '100%', borderCollapse: 'collapse', fontFamily: 'var(--font-family-sans)' }}>
      <thead>
        <tr style={{ background: 'var(--hover-muted)' }}>
          {columns.map((c) => (
            <th
              key={c.key}
              style={{
                textAlign: 'left',
                padding: variant === 'compact' ? 'var(--space-1) var(--space-2)' : 'var(--space-2) var(--space-3)',
                fontSize: 'var(--font-size-xs)',
                color: 'var(--foreground-secondary)',
                fontWeight: 'var(--font-weight-medium)',
                borderBottom: '1px solid var(--border)',
              }}
            >
              {c.label}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row, i) => (
          <tr key={i} style={{ borderBottom: '1px solid var(--border)' }}>
            {columns.map((c) => (
              <td
                key={c.key}
                style={{
                  padding: variant === 'compact' ? 'var(--space-1) var(--space-2)' : 'var(--space-2) var(--space-3)',
                  fontSize: 'var(--font-size-sm)',
                  fontFamily: c.key.match(/id|run|code/i) ? 'var(--font-family-mono)' : undefined,
                }}
              >
                {row[c.key]}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)
