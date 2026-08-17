import { ConfirmPrompt } from '../ui/ConfirmPrompt'

export interface AbortConfirmDialogProps {
  runId: string
  target: string
  impactSummary: string
  onConfirm?: () => void
  onCancel?: () => void
}

export const AbortConfirmDialog = ({ runId, target, impactSummary, onConfirm, onCancel }: AbortConfirmDialogProps) => (
  <ConfirmPrompt
    variant="destructive"
    target={`run_id=${runId} target=${target}`}
    message={`${impactSummary} この操作は取消できません。ABORTEDへ遷移させてよろしいですか？`}
    onConfirm={onConfirm}
    onCancel={onCancel}
  />
)
