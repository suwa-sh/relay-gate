export type LogoVariant = 'full' | 'icon' | 'stacked'

export interface LogoProps {
  variant?: LogoVariant
  height?: number
  className?: string
}

const heightDefault: Record<LogoVariant, number> = { full: 32, icon: 32, stacked: 48 }

export const Logo = ({ variant = 'full', height, className = '' }: LogoProps) => (
  // eslint-disable-next-line @next/next/no-img-element
  <img
    src={`/assets/logo-${variant}.svg`}
    alt="RelayGate Ops"
    height={height ?? heightDefault[variant]}
    className={className}
    style={{ display: 'inline-block' }}
  />
)
