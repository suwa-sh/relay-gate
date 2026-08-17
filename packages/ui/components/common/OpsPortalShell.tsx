import type { ReactNode } from 'react'
import { Logo } from '../ui/Logo'
import { Icon, type IconName } from '../ui/Icon'

export type OperationMode = '並行稼働' | '新実装単独本番' | '次世代実装との並行稼働'

export interface OpsPortalShellNavItem {
  key: string
  label: string
  icon: IconName
}

export const OPS_PORTAL_NAV: OpsPortalShellNavItem[] = [
  { key: 'concurrent-run', label: '並行稼働実行', icon: 'refresh-cw' },
  { key: 'rapid-crosscheck', label: '速報クロスチェック', icon: 'clock' },
  { key: 'final-crosscheck', label: '確報クロスチェック', icon: 'check' },
  { key: 'hang-watch', label: 'ハング監視', icon: 'alert-triangle' },
  { key: 'control', label: '実行制御', icon: 'terminal' },
]

export interface OpsPortalShellProps {
  activeNavKey?: string
  operationMode?: OperationMode
  mapVersion?: string
  implVersion?: string
  headless?: boolean
  children: ReactNode
}

/**
 * 運用ポータル（ops）の共通レイアウトシェル。
 * ui-design.md「運用（ops）ポータル」節に基づく。CLI単体運用時は headless=true でヘッダー/サイドバー/フッターを省略する
 * （ターミナル出力レイアウトが正本のため）。
 */
export const OpsPortalShell = ({
  activeNavKey,
  operationMode = '並行稼働',
  mapVersion = 'v1.4.0',
  implVersion = 'v1.4.0',
  headless = false,
  children,
}: OpsPortalShellProps) => {
  if (headless) {
    return <div style={{ fontFamily: 'var(--font-family-mono)' }}>{children}</div>
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%', background: 'var(--background)' }}>
      <header
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 'var(--space-4)',
          padding: 'var(--space-3) var(--space-6)',
          borderBottom: '1px solid var(--color-slate-200)',
          // logo-full.svg はダークモードでも視認できるよう固定色（#0F172A等）で描画されているため、
          // ヘッダーはテーマに関わらず常に白背景（ブランドヘッダー）にしてコントラストを保つ
          background: 'var(--color-white)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
          <Logo variant="full" height={28} />
        </div>
        <span
          style={{
            display: 'inline-block',
            fontFamily: 'var(--font-family-mono)',
            fontSize: 'var(--font-size-xs)',
            color: 'var(--color-slate-600)',
            border: '1px solid var(--color-slate-200)',
            borderRadius: 'var(--radius-sm)',
            padding: '2px var(--space-2)',
          }}
        >
          運用モード: {operationMode}
        </span>
      </header>
      <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
        <nav
          style={{
            width: '220px',
            flexShrink: 0,
            borderRight: '1px solid var(--border)',
            padding: 'var(--space-4) var(--space-2)',
            display: 'flex',
            flexDirection: 'column',
            gap: 'var(--space-1)',
          }}
        >
          {OPS_PORTAL_NAV.map((item) => (
            <div
              key={item.key}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 'var(--space-2)',
                padding: 'var(--space-2) var(--space-3)',
                borderRadius: 'var(--radius-sm)',
                fontSize: 'var(--font-size-sm)',
                fontFamily: 'var(--font-family-sans)',
                background: item.key === activeNavKey ? 'var(--hover-muted)' : 'transparent',
                fontWeight: item.key === activeNavKey ? 'var(--font-weight-bold)' : 'var(--font-weight-regular)',
                color: 'var(--foreground)',
              }}
            >
              <Icon name={item.icon} size={16} />
              {item.label}
            </div>
          ))}
        </nav>
        <main style={{ flex: 1, minWidth: 0, padding: 'var(--space-6)' }}>{children}</main>
      </div>
      <footer
        style={{
          display: 'flex',
          justifyContent: 'flex-end',
          gap: 'var(--space-4)',
          padding: 'var(--space-2) var(--space-6)',
          borderTop: '1px solid var(--border)',
          fontFamily: 'var(--font-family-mono)',
          fontSize: 'var(--font-size-xs)',
          color: 'var(--foreground-secondary)',
        }}
      >
        <span>map版: {mapVersion}</span>
        <span>実装版: {implVersion}</span>
      </footer>
    </div>
  )
}
