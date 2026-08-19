# 変更一覧 (20260818_143057_design_system)

feedback request `20260818_113601_impl_feedback_6078c4ed` の差分反映。

## 変更 (CR-6078c4ed-003 / CR-6078c4ed-005)

| 種別 | 要素 | 内容 |
|---|---|---|
| 追加 | tokens.primitive.colors | cyan-600/cyan-100(starting用)、orange-600/orange-100(unknown用) |
| 追加 | tokens.component | status-badge-starting / status-badge-unknown(dark override 含む) |
| 変更 | components.ui.StatusBadge | variants に starting / unknown を追加(8バリアント) |
| 変更 | components.domain.RunnerResultPanel | props に attemptId/attemptNo/state を追加、states を6値(STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED)へ拡張、description に identity(run_id, slot, role, attempt)と UNKNOWN 規約を明記 |
| 変更 | components.domain.ExecutionSpecCard | run共通/slot別実行設定のセクション分離、props に parentRunId/slot/execUser/workDir を追加、再実行系譜(parent_run_id)表示を明記 |
| 追加 | nfr_decisions | timeout後の結果不明は unknown バッジで明示し推測 FAILED 表示を禁止 |
| 変更 | storybook-app | design-tokens.css / StatusBadge / RunnerResultPanel / ExecutionSpecCard / 各 stories / DesignTokens.mdx を design-event.yaml に追従 |

## 変更なし (CR-6078c4ed-004 / CR-6078c4ed-006)

- audit_logs の非partition化・runner_result_events+runner_results の同一transaction併用は
  バックエンド永続化内部の変更であり、CLI 出力・画面・コンポーネント契約に影響しない。

## 意図的に変更しなかったもの

- states セクション(RDRA 状態モデル由来): STARTING/UNKNOWN は RDRA 状態.tsv に存在しないため追加しない。
  RDRA 状態モデルへの追加提案を docs/todo.md に登録(確認推奨項目)。
