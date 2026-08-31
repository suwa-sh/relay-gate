# Step3 Round 2 レビュー対応(G4: 監視調整 + 復旧)

- 対象レビュー: `step3-round-2-G4.md`
- 所有範囲: hang_detect_limit_minutes をジョブごとに調整する / 実行中止フロー(2 UC + buc-spec)/ background 側リランフロー(4 UC + buc-spec)
- 所有範囲外(`_cross-cutting/`、他 UC)は編集していない。契約側に必要な変更は末尾「契約側への要求」に列挙

## 指摘ごとの対応

| # | severity | 対応 | 変更ファイル(E 相対) | 理由・内容 |
|---|---|---|---|---|
| 1 | major | fixed | 速報比較依頼だけを新規作成する/spec.md, tier-ops.md, tier-rapid-crosscheck.md, _api-summary.yaml | (a) 「background-rerun 自身は作らない。比較実行時に worker が `facade/<新 run_id>/rapid-crosscheck/` を作る(execution-spec.json / blue / green 節は持たない)」に書き換え。BDD の Then を「background-rerun.sh 終了直後には存在しない」に限定。(b) tier-rapid-crosscheck.md L43 を「blue / green の成果物は元 run、rapid-crosscheck 成果物は新 run_id 配下」に修正し BDD に And を追加。(c) hang-detector の走査除外規則(`<role>/started-at.txt` の無い run ディレクトリは execution-spec.json を読まずに飛ばす)を spec.md 状態遷移一覧の運用注記と tier-ops.md クラッシュ耐性に引用 |
| 2 | major | fixed(UC 側) | 実行を ABORTED へ遷移させる/spec.md, tier-ops.md, _api-summary.yaml; 速報比較依頼だけを新規作成する/spec.md, tier-ops.md; 実行中止フロー/buc-spec.md | 併更新を「parallel_runs が STARTED / RUNNING なら併せて ABORTED。COMPLETED は変更しない(更新 0 件で可)」に統一(概要・データフロー表・状態遷移一覧・tier 併更新行・ビジネスルール・api-summary の exit 0 meaning・buc-spec)。BDD「RUNNING の速報比較依頼を中止する」の Given を通常 run(parallel_runs COMPLETED)に直し COMPLETED 不変を検証、rerun-rapid 由来 run の併更新シナリオを追加。tier BDD にも「COMPLETED の parallel_runs を変更しない」を追加。rerun-rapid の parallel_runs が RUNNING のまま残る運用注記を両 UC(実行中止 / 速報比較依頼だけを新規作成する)に同文で追加。契約 exit 0 meaning は別担当 |
| 3 | major | out-of-scope(契約側)+ tier md 側を補完 | リラン対象を検証する/tier-ops.md, _api-summary.yaml; リラン結果を parent_run_id で追跡する/tier-ops.md, _api-summary.yaml; hang_detect_limit_minutes をジョブごとに調整する/tier-ops.md | tier md の出力契約表を正として、契約に転記すべき全メッセージが tier md に載っていることを確認・補完した。background-rerun.sh: 終了コード 6 の `execution-spec is not readable` / `management db query failed`、`warn: mode mismatch`、入力エラー 2 のメッセージ行を出力契約に追加。run-lineage.sh: stderr を終了コード付きで全列挙(`lineage cycle detected`(6)/ `info: artifact_dir:`(--verbose)を含む)。hang-detect-trend.sh: stderr を全列挙。各 `_api-summary.yaml` の stderr も同期。契約 stderr / exit_codes.condition への転記は「契約側への要求」#1〜#3 |
| 4 | minor | fixed | 実行を ABORTED へ遷移させる/spec.md, tier-ops.md; 現在状態を確認して停止確認に応答する/tier-ops.md | `20260830T020000Z-FINAL-1a2b3c4d` → `20260830T020000Z-final-1a2b3c4d`(契約 shared_rules.final_crosscheck_id / asyncapi pattern の小文字に統一) |
| 5 | minor | deferred(UC 側は現状維持) | — | UC 側は `error: option required option=--run-id` / `option=--role` で、ui-design.md の語彙優先(`required`)と `key=value` 規約の両方を満たす。契約 rapid-crosscheck-runner.sh L309 の `missing option option=...` が唯一の不一致で、契約側(別担当)を `option required option=...` に揃える要求として記録(「契約側への要求」#4)。オーケストレータ指示の `error: option required: --xxx` 表記は `key=value` 規約に合わないため採用せず、判断を委ねる |
| 6 | minor | fixed | 現在状態を確認して停止確認に応答する/spec.md | 正常系 2 シナリオの Given に `started_at=2026-08-30T11:30:05Z` / `started_at=2026-08-30T11:46:00Z` を追加 |
| 7 | minor | fixed(UC 側) | 現在状態を確認して停止確認に応答する/tier-ops.md | 出力契約の `started_at` 出典に「成果物の started-at.txt は読まない。off では管理 DB が無いため成果物も読まず 3 で終了」を明記(RAPID_CROSSCHECK_MODE=off 節にも同旨)。契約 artifact_layout.files[started-at.txt].readers から abort-* を外すのは「契約側への要求」#5 |
| 8 | minor | fixed(UC 側) | 速報比較依頼だけを新規作成する/tier-rapid-crosscheck.md | 「payload は依頼レコードそのもの」を「依頼レコードの列 + 参照先の成果物 URI(rapid_runs / parallel_runs から JOIN した派生値で依頼テーブルの列ではない)」に修正。asyncapi.yaml の description 追記は「契約側への要求」#6 |
| 9 | minor | fixed | hang_detect_limit_minutes をジョブごとに調整する/tier-facade.md, spec.md, _api-summary.yaml | stdout を `map_path:` / `rows=` / `map_version=` / `impl_version=` の 4 行に修正。stderr 例を他 UC「slot ごとのジョブマップを定義する」の列検証メッセージ `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=... value=...` に揃えた(BDD も同様) |
| 10 | minor | fixed | hang_detect_limit_minutes をジョブごとに調整する/spec.md | Given 表に `hang_suspected_at`(1・2 行目に値、3 行目 `-`)と `judged_at`(3 行とも集計期間内)を追加し、`hang_suspected_count=2` / `run_count=3` を導出可能にした |
| 11 | minor | fixed(UC 側) | background 側リランフロー/buc-spec.md | データフロー図と CRUD 補足を「run_id / parent_run_id / restored_at を書き換え」に修正。契約 execution_spec_example への `restored_at` 追加は「契約側への要求」#7 |
| 12 | minor | fixed | 元の execution-spec.json から復元して新しい run_id で起動する/tier-facade.md, _api-summary.yaml | runner 自身のエラー出力先を `facade/<run_id>/<role>/stderr.log` 末尾の `error:` 1 行に統一(契約の runner IF stderr 規約と一致)。BDD の Then を stderr.log 末尾 + exitcode.txt=2 に修正 |
| 13 | minor | fixed(UC 側) | 元の execution-spec.json から復元して新しい run_id で起動する/tier-ops.md, spec.md | 手順 4 に「runner 実体が起動できない場合は background-rerun の gateway が started-at.txt / 空の stdout.log / 失敗理由の stderr.log / exitcode.txt=6 を書く(runner が自身で書いた場合は上書きしない)」を明記。spec.md の条件「Runner Result 完備条件」と異常系 BDD の Then を `exitcode.txt の中身が 6` に修正。契約 exitcode.txt content の追記は「契約側への要求」#8 |
| 14 | minor | fixed | リラン対象を検証する/spec.md, tier-ops.md, _api-summary.yaml; 速報比較依頼だけを新規作成する/spec.md; background 側リランフロー/buc-spec.md | off かつ `--role rapid-crosscheck` は管理 DB 接続前に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck`(3。契約 abort-* / run-lineage.sh と同じ文言、hint 無し)を返す行を出力契約表・事前検証表(理由コード `management_db_not_configured`)・分岐条件・BDD(E2E / tier)に追加。`request_not_found` は on 限定に変更。契約 stderr への転記は「契約側への要求」#1 |
| 15 | minor | fixed | 現在状態を確認して停止確認に応答する/spec.md; 実行を ABORTED へ遷移させる/spec.md | 関連 RDRA モデル表に条件「速報クロスチェック有効判定」(前半 UC)、「速報クロスチェック有効判定」「監視は通知のみ」(後半 UC)を追加 |
| 16 | minor | fixed | 元の execution-spec.json から復元して新しい run_id で起動する/spec.md | 関連 RDRA モデル表に条件「認証情報の非保存」「速報クロスチェック有効判定」、バリエーション「速報クロスチェックモード」を追加 |
| 17 | minor | out-of-scope | — | 他 G1 UC「実装スクリプトを実行して Runner Result を出力する」tier-facade.md の修正。本 G4 の所有範囲外のため未対応(横断整合として記録) |

## レビュー指摘以外の作業(オーケストレータ指示)

| 作業 | 対応 | 変更ファイル(E 相対) |
|---|---|---|
| uc-dependencies.md 暗黙参照 #2 | fixed | リラン対象を検証する/_api-summary.yaml に `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` を `role: uses`(hint 文面の参照のみ。起動しない)で追加 |
| uc-dependencies.md 暗黙参照 #4 | fixed | hang_detect_limit_minutes をジョブごとに調整する/_api-summary.yaml に `facade.sh` を `role: uses`(E2E 反映確認用。契約は UC「slot 実行モードを選択して runner を起動する」)で追加 |
| トレーサビリティ パターン A (a) リラン指示.指示日時 | fixed | リラン対象を検証する/spec.md 計算ルール一覧に「指示日時 = 新 run の parallel_runs.requested_at および実行ログ行の UTC 時刻列」を追加(速報比較依頼だけを新規作成する/spec.md にも同旨 1 行) |
| トレーサビリティ パターン A (b) ジョブスケジューラ起動ジョブ種別.background リラン専用ジョブ | fixed | リラン対象を検証する/spec.md バリエーション一覧と関連 RDRA モデル表に追加(tier-ops) |
| 実行ログ行形式(実行ログ.出力日時) | fixed | tier md に実行ログ記述がある 7 ファイル(現在状態確認 / ABORTED 遷移 / リラン対象検証 / 復元起動 / 速報依頼再作成 の各 tier-ops.md、追跡 tier-ops.md、hang-detect-trend tier-ops.md)に、ui-design.md のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う旨と「出力日時」= UTC 時刻列の対応を 1 行追記 |
| artifact_uri の `file://` 表記 | fixed | 速報比較依頼だけを新規作成する/spec.md, tier-ops.md, tier-rapid-crosscheck.md, _api-summary.yaml の BDD・出力契約を `file:///var/relay-gate/...` に統一 |
| abort-* の現在状態表示の出典 | fixed | 現在状態を確認して停止確認に応答する/tier-ops.md(#7 と同じ) |
| 復元起動時の PARAM 併用 | 確認のみ | tier-facade.md は「受け付けない(終了コード 2)」で契約と一致。変更なし |

## 契約側への要求(別担当。`_cross-cutting/` は本担当が編集していない)

| # | ファイル | 要求 | 根拠(UC 側の正) |
|---|---|---|---|
| 1 | cli-command-contract.yaml `commands[background-rerun.sh].stderr` / `exit_codes[3].condition` | stderr に `error: role is not supported by background-rerun run_id=... role=final-crosscheck` / `error: source request not found run_id=... role=rapid-crosscheck` / `error: run not found run_id=... role=...` / `error: execution-spec is not readable run_id=... path: ...`(6)/ `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck`(3)/ `warn: mode mismatch spec=... db=...` / `hint: abort the run with abort-{role}.sh --run-id ... before rerun` / `hint: abort the request with abort-rapid-crosscheck.sh --run-id ... before rerun` / `hint: request is still queued; wait for the worker` / `hint: rerun the scheduler job instead (...)` を追加。exit 3 condition に「RAPID_CROSSCHECK_MODE=off かつ role=rapid-crosscheck」を追加 | リラン対象を検証する/tier-ops.md「出力契約」表 + 追加 2 行 |
| 2 | cli-command-contract.yaml `commands[run-lineage.sh].stderr` | `error: lineage cycle detected run_id=...`(6)と `info: artifact_dir: {path} run_id=...`(--verbose)を追加 | リラン結果を parent_run_id で追跡する/tier-ops.md 出力契約 stderr |
| 3 | cli-command-contract.yaml `commands[hang-detect-trend.sh].exit_codes[2].condition` | 「job_id 形式不正(英数字・`_`・`-` 以外)」を追加 | hang_detect_limit_minutes をジョブごとに調整する/tier-ops.md 終了コード表 |
| 4 | cli-command-contract.yaml `commands[rapid-crosscheck-runner.sh].stderr`(L309)+ ui-design.md「メッセージ表現規約」 | 必須オプション欠落の定型文を `error: option required option=--x` に統一(契約 L309 の `missing option option=...` を置換し、ui-design.md に定型文として 1 行追加) | 現在状態確認 tier-ops.md BDD / リラン対象検証 tier-ops.md BDD(いずれも `option required option=`) |
| 5 | cli-command-contract.yaml `artifact_layout.files[started-at.txt].readers` | `abort-*(現在状態表示)` を外す(abort-* は slot_executions.started_at を読み、成果物は読まない。off は管理 DB 無しで 3) | 現在状態確認 tier-ops.md 出力契約 行 7 |
| 6 | asyncapi.yaml `RapidCrosscheckRequest` schema(`blue_artifact_uri` / `green_artifact_uri` / `parent_run_id`) | description に「rapid_runs / parallel_runs から JOIN した派生値(rapid_crosscheck_requests の列ではない)」を明記(または 3 プロパティを削除) | 速報比較依頼だけを新規作成する/tier-rapid-crosscheck.md 非同期イベント節 |
| 7 | cli-command-contract.yaml `execution_spec_example` | `restored_at`(通常起動は null)を追加し C1 との対応を読めるようにする | 復元起動 tier-ops.md「execution-spec.json(ファイル)」 |
| 8 | cli-command-contract.yaml `artifact_layout.files[exitcode.txt].content` | 「6 = SSH / 書き込み失敗 / runner 起動失敗(background-rerun の gateway が書く)」を追記。`readers` に `background-rerun.sh(off 時の事前検証)` を追加(uc-dependencies #3) | 復元起動 tier-ops.md 手順 4 / リラン対象検証 tier-ops.md 元状態の解決(off) |
| 9 | cli-command-contract.yaml `commands[abort-rapid-crosscheck.sh].exit_codes[0].meaning` / `commands[abort-blue.sh / abort-green.sh]` 同項 | 「parallel_runs が STARTED / RUNNING なら併せて ABORTED(COMPLETED は変更しない。更新 0 件で可)」に修正(オーケストレータ決定どおり) | 実行を ABORTED へ遷移させる/tier-ops.md 併更新行 |
| 10 | cli-command-contract.yaml `commands[validate-config.sh]`(--job-map の stderr 例) | 本 UC 側は他 UC の列検証メッセージ `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=... value=...` に揃えた。契約側に `invalid hang_detect_limit_minutes ... map=...` 形式が残っていれば同文に揃える | hang_detect_limit_minutes をジョブごとに調整する/tier-facade.md |

## 集計

| 区分 | 件数 |
|---|---|
| fixed(UC 側で修正完了) | 14(#1, #2, #4, #6, #7, #8, #9, #10, #11, #12, #13, #14, #15, #16) |
| deferred | 1(#5。UC 側は現状維持、契約側の統一を要求) |
| out-of-scope | 2(#3 契約側の転記、#17 他 G1 UC) |

## 検証結果

- `npx md-mermaid-lint`(所有範囲の md 19 ファイル): All Mermaid diagrams are syntactically correct
- `validateApiSummary.js` / `validateModelSummary.js`(7 UC ディレクトリ): すべて PASS
