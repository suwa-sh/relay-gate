import type { ButtonHTMLAttributes } from 'react'

export type ButtonVariant = 'primary' | 'secondary' | 'destructive'
export type ButtonSize = 'sm' | 'md'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  size?: ButtonSize
}

const variantStyle: Record<ButtonVariant, { background: string; color: string; border: string }> = {
  primary: { background: 'var(--color-slate-900)', color: 'var(--color-white)', border: 'var(--color-slate-900)' },
  secondary: { background: 'var(--color-white)', color: 'var(--color-slate-900)', border: 'var(--border)' },
  destructive: { background: 'var(--destructive)', color: 'var(--color-white)', border: 'var(--destructive)' },
}

const sizeStyle: Record<ButtonSize, string> = {
  sm: 'var(--font-size-xs)',
  md: 'var(--font-size-sm)',
}

export const Button = ({ variant = 'primary', size = 'md', style, children, ...rest }: ButtonProps) => {
  const v = variantStyle[variant]
  return (
    <button
      {...rest}
      style={{
        background: v.background,
        color: v.color,
        border: `1px solid ${v.border}`,
        borderRadius: 'var(--radius-sm)',
        padding: size === 'sm' ? 'var(--space-1) var(--space-2)' : 'var(--space-2) var(--space-4)',
        fontSize: sizeStyle[size],
        fontFamily: 'var(--font-family-sans)',
        fontWeight: 'var(--font-weight-medium)',
        cursor: 'pointer',
        transition: 'opacity var(--duration-fast)',
        ...style,
      }}
    >
      {children}
    </button>
  )
}
