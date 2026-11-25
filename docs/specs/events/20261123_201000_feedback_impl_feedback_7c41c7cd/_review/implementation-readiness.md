# 実装可能性の判定(2026-11-23 の差分更新: 入力の複製の作業名・共通ライブラリの呼び方・読めないジョブマップの報告)

対象は、今回の差分更新で変えた UC と CLI 契約。変えていない UC の判定は前イベントのまま。

| UC | 判定 | 根拠 |
|---|---|---|
| feature flag を設定する | ready | 決めた場所に何も無い・あるが読めない・通常のファイルでない・シンボリックリンクのときの文言と、error 行の位置(job map not found と同じ位置。blue → green)が、CLI 契約の `job_map_location.presence_report` と `error_order` から 1 つに決まる |
| slot runner の実体スクリプトを割り当てる | ready | 対応ジョブマップの検証項目の文言が、同じ規則から 1 つに決まる |
| slot ごとのジョブマップを定義する | ready | `--job-map` の無い・読めないの文言が規則と一致する。入力の複製の作業名は `snapshot.work_name` から 1 つに決まる |
| ジョブマップで JOB_ID から実行先を解決する | ready | slot runner の読めないジョブマップの文言と、共通ライブラリ 5 関数の名前・引数・結果の受け取り方・値が無い項目・知らせ方・環境変数・source の性質が、CLI 契約の `presence_report` と `runner_resolve_library` から 1 つに決まる |

## 反証レビューの結果

- round 1: major 3 / minor 4。すべて修正した(`round-1.yaml` の resolved)。
  - シンボリックリンクの判定、関数を呼んだ後の set / trap を約束しないこと、run_id が分からないときの終了コード 2、1 プロセス 1 複製の理由、RUNNER_RESOLVE_STATUS_NOT_RESOLVED の定義、facade.sh の説明、_api-summary の書き方。
- round 2: round 1 の 7 件の解消を確認。新規は minor 1 件(判断記録の場面の一覧の漏れ)で、修正した(`round-2.yaml` の resolved)。blocker 0 / 未解決 major 0 で収束。
- round 2 の minor の修正は、機械検証(YAML の parse、検証スクリプト)で確かめた。独立した再レビュー(round 3)は行っていない。

## 実装との関係

- feature flag の検証(`validate-config.sh --feature-flag`)の対応ジョブマップの検査は、存在の判定と読み取りの判定を分ける変更が要る(判断記録 spec-decision-043 の 7)。
- 入力の複製の作業名と、共通ライブラリの呼び方は、いまの実装の形を仕様にした(実装の変更は要らない)。テストの「暫定」の注記は外せる。
- ジョブマップの検証と slot runner の、読めないジョブマップの報告は変わらない。

## 残っている確認事項

- 確認推奨項目 5 件は、2026-11-23 に利用者が回答した。`build_argument_list` に JSON 配列として正しくない文字列を渡したときは、戻り値 1 で `ARGUMENT_LIST` を空にすることを約束した(判断記録 spec-decision-042 の 11)。ほかの 4 件は推奨のとおり。
- シンボリックリンクのジョブマップをリンク先で判定する規則は、2026-11-23 に利用者が確認した(判断記録 spec-decision-043 の 3a)。いまの実装がリンク先で判定しているかは確かめていない。
