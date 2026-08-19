# 変更内容 (20260819_125615_spec_stories)

feedback request `20260818_164000_rdra_followup_6078c4ed`(CR-6078c4ed-008/009/010)の spec_stories reconciliation。
このstageはdirect work unitを持たない。

## 変更 (CR-6078c4ed-010起因)

| 画面 | 変更内容 | 根拠 |
|---|---|---|
| 実行結果応答管理画面 | `UnresolvedDashboard` の mock データを旧写像(relay-gateエラー時にexitCode=1で代表)から退避終了コード125(実行結果未確定)へ修正。`UnknownDashboard`(125・UNKNOWN・stderr.log内容+relay-gateエラー内容併記)、`AbortedDashboard`(125・ABORTED・stderr.log取得不能時はrelay-gateエラー内容のみ)、`ValidationErrorDashboard`(124・run_id未指定バリデーションエラー・RunnerResultPanel非表示)の3バリエーションを新規追加 | spec.md「foreground roleの標準出力・標準エラー・終了コードを応答する」異常系Scenario 4件(141-172行目)、cli-command-contract.yaml `exit_code_convention_exception`(20行目)・`relaygate concurrent-run respond-foreground` exit_codes(186-190行目) |

`docs/design/latest/design-event.yaml` の該当screensエントリの `variants` を上記6件+`SucceededHeadless`の7件へ更新した。

## 変更なし (CR-6078c4ed-008: already_current)

- `RunnerResultPanel` の STARTING/UNKNOWN状態・attempt表示は前回spec_storiesイベント `20260818_162251_spec_stories` で既にStory実装済み(リラン実行画面・background role起動画面)
- design_systemイベント `20260819_113049_design_system` によるstatesセクション正式化・RunnerResultPanel説明追記は、既存の実装トークン(`--status-badge-starting-*`=cyan、`--status-badge-unknown-*`=orange。`docs/design/latest/storybook-app/src/styles/design-tokens.css` 108-111行目)と実コンポーネント(`StatusBadge.tsx`)に一致しており、バッジ色・表示名の齟齬は無い
- 実行結果応答管理画面以外(並行稼働実行結果確認画面等)のRunnerResultPanel使用画面は、respond-foregroundコマンドの`exit_code_convention_exception`(退避コード125/124)の対象外(結果確認・監視系画面であり終了コード応答系ではない)のため対象外

## 対象外 (CR-6078c4ed-009: not_impacted)

比較定義は画面を持たない設定マスタであり、RDRA BUCに対応画面が存在しない。design_systemイベント `20260819_113049_design_system` でも「画面への新規要件が生じない」と判定済みであり、Storybookドメイン(screens/components)に変更対象が無い

## 確認したが変更不要と判断した画面 (respond系。exit_code_convention_exception対象外)

- 確報結果応答画面(`relaygate final-crosscheck respond`): cli-command-contract.yaml 379-384行目の通り exit_codes は 0=正常終了/1=業務エラー(status=FAILED、またはstatus未確定)の通常規約のままであり、`exit_code_convention_exception` はrespond-foregroundにのみ適用される。既存の `UndeterminedHeadless`(exitCode=1)は仕様どおりで変更不要
