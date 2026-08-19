# 推論メモ (20260818_162251_spec_stories)

## スコープの絞り込み方法

1. `docs/design/latest/storybook-app/src/stories/Pages/` 配下の全23画面Storyの存在を確認(欠落なし)。
2. 上流design_system stage(20260818_143057_design_system)が拡張した3コンポーネント
   (ExecutionSpecCard / RunnerResultPanel / StatusBadge)を使用する画面を `grep` で洗い出し(14画面)。
3. 各画面の対応UC spec.md(distillery-impl feedback disposition済みの最新版)を参照し、
   拡張されたprops(parentRunId, attemptId/attemptNo/state, execUser/workDir)が実際に必要な
   stdout契約・状態遷移と一致しているかを個別に突合。
4. 乖離を検出した3画面のみ変更、残り11画面(拡張コンポーネント使用の11 + 未使用9)は not_impacted。

## 判断根拠(乖離の実体)

- リラン実行画面・background role起動画面: 両UCとも「起動受付時点の標準出力はstatus=STARTING」が
  spec.md本文に明記されているが、既存Storyは`status=RUNNING`をハードコードしていた
  (CR-005拡張以前はRunnerResultPanelにstate propが存在せず、exitCode基準のフォールバック
  (`exitCode===null → running`)しか表現できなかったための設計制約であり、拡張後は是正可能になった)。
- background role起動画面: spec.mdはSSH起動タイムアウトをUNKNOWNとして記録し「推測でFAILEDへ確定しない」
  ことを明記(CR-005のNFR決定そのもの)。既存Storyにこのシナリオが存在しなかったため新規追加。
- リラン対象選定画面: spec.mdの候補一覧stdout契約は`attempt_id`/`attempt_no`を含むが、既存Storyの
  候補データにはこれらのフィールドがなかった(RunnerResultPanelにattemptId/attemptNo propが
  存在しなかったための制約)。追加時に、exitCode=130(中止)の候補が`state`未指定のまま
  exitCode基準フォールバックで「失敗」表示になっていた表示不整合も合わせて是正した
  (state="aborted"を明示)。

## 意図的にスコープ外とした判断

- CR-004/006(audit_logs非partition化・runner_result_events/runner_results同一transaction化)は
  バックエンド永続化の内部変更であり、design_systemスキルの判定(20260818_143057_design_system)を
  そのまま踏襲しnot_impactedとした。
- 並行稼働実行結果確認画面のRUNNING表示は「起動確認成功後の監視」UCの性質上妥当であり、
  STARTINGへの書き換え対象ではないと判断した。
