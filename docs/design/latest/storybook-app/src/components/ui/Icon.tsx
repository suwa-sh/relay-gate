export type IconName =
  | 'check'
  | 'x-circle'
  | 'alert-triangle'
  | 'clock'
  | 'refresh-cw'
  | 'terminal'
  | 'mail'
  | 'chevron-right'

export interface IconProps {
  name: IconName
  size?: number
  className?: string
}

export const Icon = ({ name, size = 20, className = '' }: IconProps) => (
  <img
    src={`/assets/icons/${name}.svg`}
    alt=""
    width={size}
    height={size}
    className={className}
    style={{ display: 'inline-block', verticalAlign: 'middle' }}
  />
)
