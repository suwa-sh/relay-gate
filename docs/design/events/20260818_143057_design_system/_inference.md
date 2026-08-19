# 推論根拠 (20260818_143057_design_system)

## 入力

- stage packet: docs/pipeline/feedback-runs/20260818_113601_impl_feedback_6078c4ed/stage-packets/design_system.md
- arch 正本: docs/arch/latest/arch-design.yaml
  - 起動試行(attempt)定義: 「実行状態STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTEDを遷移し、timeout後は推測でFAILEDを確定せずUNKNOWNとする」
  - run共通 execution spec と slot別実行設定(host/exec_user/script/work_dir/impl_version)の分離
- RDRA 正本: docs/rdra/latest/状態.tsv
  - 再実行行: 「新しいrun_idの実行を新規作成しparent_run_idで元run_idに関連付ける。元の実行のレコードと履歴は変更しない」
  - background slot実行状態は RUNNING/SUCCEEDED/FAILED/ABORTED の4値のまま(STARTING/UNKNOWN なし)

## 影響判定

| CR | 判定 | 根拠 |
|---|---|---|
| CR-003 | changed | リラン実行画面の ExecutionSpecCard に系譜(parent_run_id)表示が必要。RDRA 状態.tsv に parent_run_id 関連付けが正式反映済み |
| CR-004 | not_impacted | audit_logs の DDL 構成はバックエンド永続化内部。CLI 出力・画面契約に非依存 |
| CR-005 | changed | RunnerResultPanel の states が4値のままで UNKNOWN/STARTING を表示できず、nfr_decision「未定義状態(空白)を許容しない」と矛盾する。ExecutionSpecCard が run共通/slot別を未分離 |
| CR-006 | not_impacted | event+snapshot の同一transaction永続化は repository 層の実装方式。表示契約に非依存 |

## 設計判断

- starting = cyan、unknown = orange: 既存6バッジ(blue/green/red/gray/amber/violet)と識別可能な残り色相を採用。
  unknown は「要注意・要回復」の意味論から warning 系だが、requested(amber) との混同を避け orange とした。
- 新規 props(parentRunId/slot/execUser/workDir/attemptId/attemptNo/state)は optional とし、
  既存23画面 stories の後方互換を維持した。
- states セクションは RDRA 状態モデルのマッピングであり、RDRA に無い状態の自動追加は整合性ルールで禁止のため、
  コンポーネント層でのみ6値を反映し、RDRA への追加提案を todo 登録した。
