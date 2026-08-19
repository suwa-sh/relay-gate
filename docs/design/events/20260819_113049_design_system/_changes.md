# 変更内容 (20260819_113049_design_system)

feedback request `20260818_164000_rdra_followup_6078c4ed` の CR-6078c4ed-008 / 009 / 010 に対する design_system の追随反映。

## 変更

| 区分 | 対象 | 変更 | 由来 |
|---|---|---|---|
| states | background slot実行状態 | 4値 → 6値。STARTING(起動受付/violet)・UNKNOWN(結果不明/orange)を追加 | CR-6078c4ed-008 |
| components.domain | RunnerResultPanel | description に exitcode 全値透過・退避終了コード(125/124)・relay-gateエラー時の stderr 併記の表示契約を追記 | CR-6078c4ed-010 |
| nfr_decisions | 運用・保守性(relay-gateエラーと業務終了コードの区別) | 決定を1件追加 | CR-6078c4ed-010 |
| decisions | design-decision-004 | 追加 | CR-6078c4ed-008 / 010 |

## 変更なし

- `components.domain.RunnerResultPanel.states` / `StatusBadge` — 前回イベント `20260818_143057_design_system` で6値対応済み。今回の states セクション整合は既存トークン(status-badge-starting / status-badge-unknown)に一致させただけで、トークン・コンポーネント実装の変更は不要
- `screens` / `portals` / `tokens` / `assets` — 新規画面・新規トークンなし
- `storybook-app/` — RunnerResultPanel は exitCode をそのまま表示し stderr を文字列として表示するため、表示契約の明文化にコード変更を要しない
- 比較定義(CR-6078c4ed-009) — RDRA BUC に管理画面の定義が無く、CLI 出力・画面への新規要件が生じない。RDRA 整合性ルールにより画面を発明しない

## 関連 todo

- DIST-023 / DIST-024 は RDRA 状態モデルが6値になったことで解消。`docs/todo.md` で closed へ更新。
