# 推論根拠 (20260819_125615_spec_stories)

## CR-6078c4ed-010 (changed)

- `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml` の `exit_code_convention_exception`(20-22行目)は `relaygate concurrent-run respond-foreground` に限定される例外であり、他コマンド(例: `final-crosscheck respond`)には適用されない。両コマンドのexit_codesセクションを読み比べて対象範囲を確定した
- 同ファイル 161-194行目の `relaygate concurrent-run respond-foreground` の `exit_code_policy: passthrough` / `exit_codes`(125/124) / `exit_code_notes` を Story mock データの正本とした
- spec.md「foreground roleの標準出力・標準エラー・終了コードを応答する」異常系4シナリオ(141-172行目)から、mock文言(stderrメッセージ・次アクション)をそのまま採用し推測を避けた
- 既存 `実行結果応答管理画面.stories.tsx` の `UnresolvedDashboard` が `exitCode={1}` + `Error: foreground実行結果が未確定です` という、退避コード分離前の旧写像(relay-gateエラーを業務終了コード1として表現)のままだったことを確認し、これを125へ修正。UNKNOWN/ABORTED/バリデーションエラー(124)の3系統は既存Storyに存在しなかったため新規追加
- 起動slot選択画面.stories.tsx の `BothForegroundRejectedDashboard` / `JobMapUnresolvedDashboard` にある `Banner variant="error"` パターンを、run_id未指定時(RunnerResultPanel表示不能)の `ValidationErrorDashboard` に転用した

## CR-6078c4ed-008 (already_current)

- `docs/design/events/20260819_113049_design_system/design-event-diff.yaml` の states 6値化・RunnerResultPanel description 追記の内容と、`docs/design/latest/storybook-app/src/styles/design-tokens.css`(108-111行目)・`StatusBadge.tsx` の実装トークンを突合し、STARTING=cyan/UNKNOWN=orangeで一致することを確認した
- design-event.yaml トップレベルの `states:` セクション(660-680行目付近)は「background slot実行状態」モデルの参考ラベルであり、STARTING行に `color: violet` と記載されているが、これはコンポーネント実装(cyan)とは独立したドキュメント用メタデータであり、design_systemスキルの管轄(トークン/コンポーネント定義)に属する。spec_storiesが変更するsrc/stories配下の実体には影響しないため、Story側の追加変更は不要と判断した
- 前回spec_storiesイベント `20260818_162251_spec_stories` で STARTING/UNKNOWN・attempt表示のStoryは既に反映済み(リラン実行画面/background role起動画面)であることを確認した

## CR-6078c4ed-009 (not_impacted)

- `docs/design/latest/design-event.yaml` / `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml` を全文検索したが「比較定義」に対応するscreen/CLIコマンドは存在しない
- design_systemイベント `20260819_113049_design_system` の判定(「RDRA BUCに管理画面の定義が無く、CLI出力・画面への新規要件が生じない」)と整合する
