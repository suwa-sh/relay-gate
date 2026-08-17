import { Icon } from './Icon'
import { Button } from './Button'

export type ConfirmPromptVariant = 'default' | 'destructive'

export interface ConfirmPromptProps {
  variant?: ConfirmPromptVariant
  target: string
  message: string
  onConfirm?: () => void
  onCancel?: () => void
}

export const ConfirmPrompt = ({ variant = 'default', target, message, onConfirm, onCancel }: ConfirmPromptProps) => (
  <div
    style={{
      width: '480px',
      maxWidth: '100%',
      background: 'var(--confirm-prompt-bg)',
      border: `1px solid ${
        variant === 'destructive' ? 'var(--confirm-prompt-destructive-border)' : 'var(--confirm-prompt-border)'
      }`,
      borderRadius: 'var(--radius-sm)',
      padding: 'var(--space-4)',
      fontFamily: 'var(--font-family-sans)',
      color: 'var(--foreground)',
    }}
  >
    <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
      <Icon name="alert-triangle" size={16} />
      <span style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--font-size-xs)', color: 'var(--foreground-secondary)' }}>
        {target}
      </span>
    </div>
    <p style={{ margin: 'var(--space-3) 0', fontSize: 'var(--font-size-sm)' }}>{message}</p>
    <div style={{ display: 'flex', gap: 'var(--space-2)', justifyContent: 'flex-end' }}>
      <Button variant="secondary" size="sm" onClick={onCancel}>
        n (キャンセル)
      </Button>
      <Button variant={variant === 'destructive' ? 'destructive' : 'primary'} size="sm" onClick={onConfirm}>
        y (実行)
      </Button>
    </div>
  </div>
)
