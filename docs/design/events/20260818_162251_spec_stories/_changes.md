# 変更一覧 (20260818_162251_spec_stories)

feedback request `20260818_113601_impl_feedback_6078c4ed` の差分反映(reconciliation)。
このstageはdirect work unitを持たない。上流の design_system stage(20260818_143057_design_system)が
ExecutionSpecCard / RunnerResultPanel / StatusBadge を拡張したことに伴い、その拡張を実際に使う
ページ Story 側の表示内容が spec.md の記述と乖離していないか確認し、乖離のあった3画面を更新した。

## 変更 (CR-6078c4ed-003 / CR-6078c4ed-005 起因)

| 画面 | 変更内容 | 根拠 |
|---|---|---|
| リラン実行画面 | 新規runのExecutionSpecCardをparent_run_id付きの構造化表示に変更(従来はstdoutテキスト埋め込みのみ)。RunnerResultPanelにattemptId/attemptNo/state="starting"を追加し、stdoutのstatusをRUNNING→STARTINGへ修正 | spec.md「execution-spec.jsonの実行設定を保ったまま再実行する」121行目: 標準出力はstatus=STARTINGを返す(RUNNINGへの遷移は起動確認成功後) |
| background role起動画面 | RunnerResultPanelにattemptId/attemptNo/state="starting"を追加し、stdoutのstatusをRUNNING→STARTINGへ修正。SSH起動タイムアウトによるUNKNOWN状態のStoryを新規追加(StartUnknownDashboard) | spec.md「background roleを起動する」103行目・118行目・131行目: 起動受付はSTARTING、SSH起動タイムアウトはUNKNOWN(推測でFAILEDへ確定しない) |
| リラン対象選定画面 | background候補データにattemptId/attemptNo/stateを追加(exitCode 130の中止済み候補にstate="aborted"を明示し、正しいバッジ表示に修正) | spec.md「再実行対象のbackground実行・速報比較依頼を選択する」45行目・74行目: 候補一覧はattempt_id/attempt_noを含めて出力する |

## 変更なし (CR-6078c4ed-004 / CR-6078c4ed-006)

audit_logsの非partition化・runner_result_events+runner_resultsの同一transaction併用は、design_system stage
(20260818_143057_design_system)で既に「バックエンド永続化内部の変更でありCLI出力・画面・コンポーネント契約に
影響しない」と判定済み。この判定はページStoryにも同様に適用され、影響なし。

## 確認したが変更不要と判断した画面

- background実行異常検知画面: RunnerResultPanelはhang-watch検知ジョブ自身の実行結果(SUCCEEDED/FAILED)を
  表示するものであり、検知対象のRunner実行結果のstate拡張とは無関係
- ハング異常通知確認画面: HangDetectionNotice/Bannerのみを使用し、拡張対象コンポーネント(ExecutionSpecCard /
  RunnerResultPanel / StatusBadge)を使用しない
- 並行稼働実行結果確認画面: 「並行稼働実行結果を確認する」UCは起動後の監視画面であり、exitCode={null}による
  RUNNING表示は起動確認成功後の実際の状態を反映しており妥当(STARTINGへの修正対象ではない)
- 起動slot選択画面・確報クロスチェック結果確認画面・確報クロスチェック実行画面・確報結果応答画面・
  速報クロスチェック結果確認画面・速報クロスチェック実行画面・実行結果応答管理画面・並行稼働実行結果確認画面・
  blue/green background中止依頼画面(拡張対象コンポーネントを使用する残り9画面): 起動受付時点のSTARTINGや
  SSH起動タイムアウトのUNKNOWNを扱う画面ではなく、いずれも完了後の結果確認・業務エラー(DB接続タイムアウト等)
  表示であり、追加された任意プロパティは後方互換のため表示内容に齟齬がない
