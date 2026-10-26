---
schema_version: distillery.feedback-request/v1
feedback_id: 20261027_053600_impl_feedback_dcd8234d
created_at: 2026-10-27T05:36:00+09:00
source: distillery-impl
uc_id: dcd8234d
---

# 実装からの変更要求

## CR-dcd8234d-008: 比較ツールの起動コマンドを、シェルに解釈させず引数ごとに分けて起動する決まりが無い

- severity: spec-gap
- related_ids: [SPEC-005-03, SPEC-006-02, SPEC-004-04, REQ-005, REQ-006]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md]

### 観測した事実

- 2026-10-10 の変更要求(クロスチェックの簡素化)を反映した現在の CLI 契約は、速報 worker(`rapid-crosscheck-worker.sh`)の起動コマンドの解決を次のように書く。「rapid-crosscheck.env の RAPID_COMPARE_COMMAND(1 行の文字列)のプレースホルダを依頼レコードの値で置換して起動する。`{job_id}`(必須)= job_id、`{run_id}` = run_id、`{params}` = parameters、`{blue_exit_code}` = blue_exit_code、`{green_exit_code}` = green_exit_code。置換後の文字列をコマンドとして起動し、stdout / stderr / exit_code を依頼レコードの列へ保存する」。`external_interfaces` の速報比較ツールの `launch` も同じ書き方である。
- 確報 worker(`final-crosscheck-worker.sh`)は「final-crosscheck.env の FINAL_COMPARE_COMMAND(1 行の文字列。プレースホルダ無し)をそのまま起動する」と書く。
- `{params}` に入る `rapid_crosscheck_requests.parameters` は、ジョブスケジューラから渡された PARAM... を順序どおりに保持した JSON 配列文字列である(引数無しは `[]`)。値の中身は relay-gate が決めず、任意の文字を含みうる。
- env ファイルは `source` せずに KEY=VALUE として解析する(`config_input_rules.env_files`)。値の中のクォートや空白をどう解釈して引数に分けるかの規則は無い。
- `validate-config.sh --rapid-crosscheck` / `--final-crosscheck` は、起動コマンドのコマンド部分(先頭の語)が絶対パスで存在・実行可能であることと、速報に `{job_id}` があることだけを検査する。「先頭の語」の区切り方は定義されていない。
- 自動のセキュリティレビュー(2026-10-11)が、この起動方法を「プレースホルダを置換した文字列をコマンドとして起動する設計で、コマンドインジェクションの余地がある」(重要度 medium)と指摘した。利用者は 2026-10-27 のレビューで、引数ごとに分けて起動する決まりを仕様に書く案(案 A)を選んだ。

### 現在の仕様と問題

- 「置換後の文字列をコマンドとして起動する」は、文字列をシェルに解釈させる実装(`eval`、`bash -c`、引用符なしの展開)を許してしまう。その実装では、パラメータに `;`、`|`、`$(...)`、バッククォート、空白、`*` などが入ると、意図しないコマンドの実行・引数の分割・ファイル名の展開が起きる。
- パラメータの JSON 配列を `{params}` にどう展開するか(1 項目 1 引数か、配列の文字列のまま 1 引数か)が書かれていないため、実装ごとに比較ツールが受け取る引数が変わる。
- 起動コマンドを引数に分ける規則が無いため、検証の「コマンド部分(先頭の語)」と worker が実際に起動するコマンドが一致する保証が無い。
- 置換に使う job_id と run_id は形式規則を持つが、置換の前に検査する決まりが無い。

### 変更してほしいこと

1. **起動コマンドを引数の並びとして解釈する規則を、CLI 契約の共通規則に 1 か所で定める。** 速報・確報の worker と `validate-config.sh` が同じ規則を参照する。
   - RAPID_COMPARE_COMMAND / FINAL_COMPARE_COMMAND の値を、設定を読んだ時点で空白(スペース・タブの 1 個以上の連続)で区切って引数の並びに分ける。クォート・エスケープ・`$` などのシェルの記法は解釈せず、文字として扱う。
   - 先頭の引数をコマンド部分とする。検証の「コマンド部分(先頭の語)」はこの規則で分けた先頭の引数と同じものである。
2. **プレースホルダの置換は、分けた引数 1 つの中だけで行う。** 置換の結果で引数の数や区切りが変わらない。
   - `{job_id}` / `{run_id}` / `{blue_exit_code}` / `{green_exit_code}` は、引数の一部としても置換できる(例: `--job={job_id}`)。
   - `{params}` は、引数 1 つ全体が `{params}` のときだけ使え、parameters の JSON 配列の各項目を順序どおりに 1 項目 1 引数へ展開する(`[]` なら引数 0 個)。それ以外の位置の `{params}` は設定の違反にする。違反文言は既存の `error: ... key=<KEY> value=...` の形式に合わせて仕様側で決める。
3. **起動は引数の並びをそのまま渡して行い、文字列をシェルに解釈させない。** `eval`、`bash -c`、`sh -c`、引用符なしの変数展開による起動を禁止すると明記する。確報の FINAL_COMPARE_COMMAND も同じ規則で分けて起動する。
4. **置換の前に値を検査する。** job_id と run_id は既存の形式規則(job_id の規則、`shared_rules.run_id`)に合うことを確かめ、合わなければ比較ツールを起動せずに依頼を FAILED にする。stderr の文言と依頼レコードへの保存内容は、既存の起動失敗と同じ扱いにするかどうかも含めて仕様側で決める。parameters は JSON 配列として読めない場合に同じく FAILED にする。
5. **反映先**: CLI 契約(`shared_rules` への規則の追加、`rapid-crosscheck-worker.sh` / `final-crosscheck-worker.sh` の起動コマンドの解決、`external_interfaces` の比較ツール 2 件の `launch`、`config_files` の RAPID_COMPARE_COMMAND / FINAL_COMPARE_COMMAND の説明、`validate-config.sh` の検証と違反文言)、速報 worker の UC「比較ツールでジョブ単位比較を実行して結果を登録する」、確報 worker の UC「比較ツールで日次全量比較を実行して結果を保存する」、起動コマンドを設定する UC「クロスチェックのジョブマップと比較定義を定義する」の検証ルールと BDD シナリオ。
6. **変えないこと**: 設定 1 行 + プレースホルダという形、必須・任意のプレースホルダの集合、検証の 2 点(コマンド部分が絶対パスで存在・実行可能、速報に `{job_id}` がある)、worker が依頼レコードと自分の設定だけを読むこと。記号を含む設定を検証で拒否する規則は追加しない(引数として渡せば記号は文字として届くため)。

### 完了条件

- CLI 契約に、起動コマンドを引数の並びに分ける規則が 1 か所だけあり、速報・確報の worker と `validate-config.sh` がその規則を参照している。
- 速報・確報の worker の仕様に、文字列をシェルに解釈させない(`eval` / `bash -c` / `sh -c` / 引用符なしの展開で起動しない)ことが明記されている。
- `{params}` の展開(引数 1 つ全体のときだけ、1 項目 1 引数、`[]` なら 0 個)と、それ以外の位置の `{params}` の違反文言が一意に決まっている。
- 速報 worker の UC に、パラメータに `;` や `$(...)` や空白を含む値が入っても、比較ツールがその値を 1 つの引数として受け取り、ほかのコマンドが実行されないことを確かめる BDD シナリオがある。
- job_id / run_id / parameters が形式に合わないときの worker の振る舞い(起動しない、依頼の状態、stderr の文言)が一意に決まっている。
- 仕様のどこにも「置換後の文字列をコマンドとして起動する」という書き方が残っていない。
