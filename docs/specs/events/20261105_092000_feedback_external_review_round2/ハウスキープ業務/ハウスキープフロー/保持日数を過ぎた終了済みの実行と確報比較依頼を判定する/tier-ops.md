# 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する - 実行監視・復旧ティア仕様

## 変更概要

tier-ops に `housekeep.sh` を追加する。
この UC は、設定の読み込み、期限 cutoff の算出、成果物ルートと管理 DB の走査、実行の単位の組み立て、単位と確報比較依頼の判定を定義する。
置き場の残りの削除、単位の削除順序、トランザクション、stdout の件数は UC「[成果物と管理 DB の履歴を削除する](../成果物と管理%20DB%20の履歴を削除する/tier-ops.md)」が定義する。

| レイヤー | 責務 |
|---|---|
| presentation | 引数の検証、stdout / stderr / 終了コードへの写像 |
| usecase | 設定読込 → cutoff 算出 → 置き場の削除 → 管理 DB 接続 → 走査 → 単位の組み立て → 単位ごとの判定と削除 → 確報比較依頼 → 孤立した印 |
| domain | 単位の組み立て(`build_run_units`)、実行ごとの終端判定(`judge_member_db` / `judge_member_artifact`)、単位の判定(`judge_unit`)、確報比較依頼の判定 |
| repository | ハウスキープ設定、feature flag 設定、確報クロスチェック設定(`FINAL_DB_CONN_REF` の有無だけ)、成果物ルートの走査、管理 DB の SELECT |
| gateway | ファイルシステム、RDB クライアント(ハウスキープ専用 DB ロール housekeep_del) |

## コマンド契約

### housekeep.sh

- **書式**: `housekeep.sh [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラのハウスキープ定期ジョブ(1 日 1 回)。運用者が手動で起動してもよい。成果物ルートの読み書き権限と、`HOUSEKEEP_DB_CONN_REF` があるときハウスキープ専用 DB ロール housekeep_del の接続
- **起動しないもの**: `facade.sh` と他のスクリプトは `housekeep.sh` を呼ばない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--verbose` | boolean | No | false | 単位ごとの `info: unit kept ...` / `info: unit deleted ...` を stderr にも出す |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし
- 契約の正本は [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml) の `commands` の housekeep.sh と `shared_rules.housekeep_rules`

### 設定(housekeep.env)

`$RELAY_GATE_CONFIG_DIR/housekeep.env`。
所有者は基盤適用設計者(設定所有区分: ハウスキープ設定)。
キーの定義は契約 `config_files` の housekeep.env。
入力の守備範囲(NUL / UTF-8 / BOM / CR の拒否、引用符と空白の外し方、同じキーが 2 行以上ある設定の拒否)は契約 `config_input_rules` の `env_files` に従う。

| キー | 必須 | 既定値 | 起動時の検査 |
|---|---|---|---|
| `HOUSEKEEP_RETENTION_DAYS` | No | 90 | 値が `^[1-9][0-9]{0,8}$` に合わなければ `error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=... path: ...` + `hint: use a positive integer`(2) |
| `HOUSEKEEP_DB_CONN_REF` | 管理 DB を使う設置で Yes(下の表) | なし | 必須なのに欠落・空は `error: option required option=HOUSEKEEP_DB_CONN_REF path: ...`(2) |
| 上記以外 | — | — | `warn: unknown key key=<KEY> path: ...`(継続) |

- `RAPID_CROSSCHECK_MODE` は feature-flag.env から読む。値の検査と文言は契約 `config_files` の feature-flag.env `error_messages` と同じ。feature-flag.env の他のキー・未知キー・`FINAL_` で始まるキーは検査せず、warn も error も出さない(契約 feature-flag.env の `reader_scope`)
- `HOUSEKEEP_DB_CONN_REF` の要否の正本は契約 `shared_rules.housekeep_rules.db_requirement`。次の表の順に決める

| 順 | 条件 | 結果 |
|---|---|---|
| 1 | `HOUSEKEEP_DB_CONN_REF` がある | `RAPID_CROSSCHECK_MODE` によらず管理 DB に接続する。final-crosscheck.env は読まない |
| 2 | 無い・空で、`RAPID_CROSSCHECK_MODE` が off 以外 | 設定エラー(2) |
| 3 | 無い・空で off。`$RELAY_GATE_CONFIG_DIR/final-crosscheck.env` があり、その `FINAL_DB_CONN_REF` が欠落していない(キーがあり、値が空でない) | 確報クロスチェックを使う設置。設定エラー(2) |
| 4 | 無い・空で off。final-crosscheck.env が無い、またはキーが無い・値が空 | 管理 DB を一切使わない設置。管理 DB に接続しない(下記) |

- 順 3 と順 4 の判定は、確報系コマンドの管理 DB なしの判定(`abort-final-crosscheck.sh` の「final-crosscheck.env 不在または FINAL_DB_CONN_REF 欠落」)と同じ規則である。確報は速報のモードに依存しない
- final-crosscheck.env は順 3・4 の判定のときだけ読む。`FINAL_DB_CONN_REF` 以外のキーは検査せず、未知キーの warn も出さない。`FINAL_DB_CONN_REF` で管理 DB に接続せず、その値を stdout / stderr / 実行ログに出さない
- final-crosscheck.env があるのに読めないときは `error: config file is not readable path: $RELAY_GATE_CONFIG_DIR/final-crosscheck.env`(2)。入力の守備範囲の違反は契約 `config_input_rules` の文言で 2
- 設定エラー(2)は、どちらの理由で必須になったかを文言で区別しない
- 管理 DB に接続しないとき(順 4)は、成果物だけを判定する。処理の順序の 5(接続の判断)で、起動のたびに `warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)` を stderr に 1 行出す。確報比較依頼と管理 DB の行は判定も削除もしない。終了コードは変えない(ほかに失敗が無ければ 0)

## 出力契約

stdout の 8 行と削除の失敗行は UC「成果物と管理 DB の履歴を削除する」の tier-ops.md を参照する。

- **stderr**(走査前の設定エラー。終了コード 2。stdout は出さない。削除待ちの置き場の残りを含め何も削除しない):

| 条件 | 行 |
|---|---|
| housekeep.env が無い | `error: config file not found path: $RELAY_GATE_CONFIG_DIR/housekeep.env` |
| housekeep.env が読めない | `error: config file is not readable path: $RELAY_GATE_CONFIG_DIR/housekeep.env` |
| feature-flag.env が無い・読めない | `error: config file not found path: ...` / `error: config file is not readable path: ...` |
| 保持日数が不正 | `error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=... path: ...` + `hint: use a positive integer` |
| 管理 DB を使う設置(off 以外、または確報クロスチェックを使う設置)で接続参照名が無い・空 | `error: option required option=HOUSEKEEP_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/housekeep.env` |
| off で接続参照名が無い・空のとき、final-crosscheck.env があるのに読めない | `error: config file is not readable path: $RELAY_GATE_CONFIG_DIR/final-crosscheck.env` |
| 読んだ設定ファイルの入力の守備範囲の違反(NUL / UTF-8 / BOM / CR / invalid line / 同じキーの重複 `error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...`。同じキーの重複は読むキーに限らずファイル全体の全キーで判定する。final-crosscheck.env でも FINAL_DB_CONN_REF 以外のキーの重複を設定エラーにする) | 契約 `config_input_rules` の文言と報告の順(`env_files`) |
| `RELAY_GATE_ARTIFACT_ROOT` が無い(存在しない・存在確認の失敗・ディレクトリでない。契約 `shared_rules.artifact_root_entries.missing_root`) | `error: artifact root not found path: ...` |
| 未知のオプション / 余分な引数 | `error: unknown option option=...` / `error: unexpected argument value=...` |

- **stderr**(設定の警告。終了コードに影響しない):

| 条件 | 行 |
|---|---|
| housekeep.env に未知のキーがある | `warn: unknown key key=<KEY> path: ...` |
| 管理 DB を一切使わない設置(要否の表の順 4)で `HOUSEKEEP_DB_CONN_REF` が無い・空(起動のたびに 1 行) | `warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)` |

- **stderr**(判定の継続。終了コードに影響しない。その実行を含む単位を残す):

| 条件 | 行 |
|---|---|
| 成果物だけで判定する実行に execution-spec.json が無い | `warn: run kept execution-spec missing run_id=<run_id> path: <run_dir>/execution-spec.json` |
| 成果物だけで判定する実行の execution-spec.json が読めない・JSON として解析できない・`slots` に role が 1 つも無い・`parent_run_id` が null でも run_id 形式でもない・管理 DB に接続しないときに `rapid_crosscheck_mode` が foreground / background / off のどれでもない(キーが無いを含む) | `warn: run kept execution-spec invalid run_id=<run_id> path: <run_dir>/execution-spec.json` |
| 管理 DB に接続しないとき、execution-spec.json の `rapid_crosscheck_mode` が foreground / background(off 以外の期間に作られた実行) | `warn: run kept rapid crosscheck mode run_id=<run_id> mode=<foreground|background>` |
| 成果物だけで判定する実行で、`slots` に載っている role のディレクトリが無い | `warn: run kept slot artifact missing run_id=<run_id> role=<role> path: <run_dir>/<role>` |
| 管理 DB で判定する実行で、終端状態の行の completed_at が NULL | `warn: run kept completed_at missing run_id=<run_id> table=<table>` |

- **stderr**(実行エラー。終了コード 6):

| 条件 | 行 | その後 |
|---|---|---|
| 管理 DB の接続に失敗 | `error: management db connection failed conn_ref=<参照名>` | 単位・確報比較依頼・孤立した印を処理しない |
| 単位を作るための SELECT に失敗 | `error: management db query failed table=<table>` | 同上 |
| 確報比較依頼の SELECT に失敗 | `error: management db query failed table=final_crosscheck_requests` | 確報比較依頼だけを処理せず、孤立した印へ進む |
| `facade/` が読めない | `error: artifact root is not readable path: $RELAY_GATE_ARTIFACT_ROOT/facade` | 単位・確報比較依頼・孤立した印を処理しない |

- **stderr**(`--verbose` のときだけ。単位の判定順に 1 単位 1 行):
  - `info: unit kept root_run_id=<run_id> reason=unfinished|within_retention|undeterminable`
  - `info: unit deleted root_run_id=<run_id> run_ids=<N> latest_completed_at=<ローカル日時>`(削除し終えた単位)
- **実行ログ**(`$RELAY_GATE_LOG_DIR/housekeep.sh.log`。行形式は契約 `conventions.execution_log`):
  - `INFO housekeep started retention_days=<N> cutoff=<ローカル日時> db=connected|not_configured`(run_id 欄は `-`)
  - `INFO unit kept root_run_id=<run_id> reason=...`(run_id 欄は root_run_id。`--verbose` の有無によらず残す)
  - stderr の warn / error 行と同じ文言を WARN / ERROR で残す

## UC ロジック

### 処理の順序

1. 引数を検証する。
2. housekeep.env と feature-flag.env を読み、保持日数と接続参照名を確定する。off で接続参照名が無い・空なら final-crosscheck.env の `FINAL_DB_CONN_REF` の有無も読み、接続参照名の要否を決める(要否の表)。`RELAY_GATE_ARTIFACT_ROOT` があることも確かめる。ここまでの失敗は終了コード 2 で、手順 3 以降を行わない(契約 housekeep.sh `processing_order` の手順 0)。検査は 引数 → housekeep.env → feature-flag.env → 接続参照名の要否(必要なときだけ final-crosscheck.env)→ `RELAY_GATE_ARTIFACT_ROOT` の順に行い、最初に設定エラーを見つけた段で止める(以降の段は検査しない)。
3. cutoff を決める。
4. 削除待ちの置き場の残りを削除する(UC「成果物と管理 DB の履歴を削除する」)。手順 2 を通ったときだけ行う。
5. `HOUSEKEEP_DB_CONN_REF` があれば管理 DB に接続し、単位を作るための SELECT を行う。接続参照名が無い・空(要否の表の順 4。管理 DB を一切使わない設置)なら、ここで `warn: management db is not configured ...` を 1 行出して接続しない。管理 DB に接続しないときの実行ごとの判定は、手順 7 で成果物だけの判定表の順(順 2・順 3)に行う(契約 shared_rules.housekeep_rules.member_source)。
6. 成果物ルートを走査し、実行の単位を作る。
7. 単位ごとに判定し、削除対象なら続けて削除する(UC「成果物と管理 DB の履歴を削除する」)。
8. 管理 DB に接続したときだけ、確報比較依頼を判定して 1 件ずつ削除する。
9. 孤立した通知済みの印を削除する(UC「成果物と管理 DB の履歴を削除する」)。

### 期限 cutoff

| 項目 | 規則 |
|---|---|
| 現在時刻 | `RELAY_GATE_NOW` があればその値(UTC)、無ければシステム時刻 |
| cutoff | 現在時刻の epoch 秒 − 保持日数 × 86400(暦日では数えない) |
| 保持日数を過ぎた | 最も遅い終了日時の epoch 秒 < cutoff。同時刻は残す |
| 表記 | stdout・ログの cutoff と latest_completed_at は契約 `conventions.datetime` のローカル日時 |
| DB 日時の比較 | `*_at` 列はホストのローカル時刻で入っている。ホストのタイムゾーンで epoch 秒へ変換して比べる |

### 走査の対象

| 対象 | 規則 |
|---|---|
| run ディレクトリ | 契約 `shared_rules.artifact_root_entries.run_dir_enumeration` に合う `facade/` 直下のディレクトリだけ。`.tmp` で終わる名前と run_id 形式に合わない名前は無視する。`facade/` が無ければ run ディレクトリ 0 件とする |
| 管理 DB の実行 | parallel_runs の全行。あわせて slot_executions の全行と rapid_crosscheck_requests の全行の判定列を読む。1 日 1 回の起動で、行数は保持日数分に限られる |
| 確報比較依頼 | status が SUCCEEDED / FAILED / ABORTED で completed_at < cutoff の行 |

### 実行の単位の組み立て(domain `build_run_units`)

1. 実行の集合を作る: run ディレクトリの run_id と parallel_runs の run_id の和集合。
2. つながりを作る: 各実行について、parallel_runs.parent_run_id と execution-spec.json の parent_run_id(読めたものだけ)の非 null 値を親として、実行と親の run_id を結ぶ。
3. 親の run_id が実行の集合に無い場合も、その run_id を結び目として扱う(同じ親を持つ兄弟は 1 単位になる)。結び目そのものは単位の実行に数えない。
4. 結んだ連結成分ごとに 1 単位とする。
5. root_run_id は、単位内で親が単位内に無い実行のうち run_id が最小のもの。該当が無ければ単位内の最小の run_id。
6. 単位は root_run_id の昇順に処理する。

### 実行ごとの判定元(B-03)

| 実行の状態 | 判定元 |
|---|---|
| parallel_runs 行がある(速報比較依頼だけのリランで作られた run、成果物を削除したあとで管理 DB の行の削除に失敗して行だけが残った実行を含む) | 管理 DB の行(`judge_member_db`)。run ディレクトリ・execution-spec.json の有無と形式・slot のディレクトリと終了ファイルは判定に使わず、`warn: run kept execution-spec missing` / `execution-spec invalid` / `slot artifact missing` を出さない(execution-spec.json は読めた場合だけ単位のつながりに使う) |
| parallel_runs 行が無く run ディレクトリがある(off で作られた実行、または管理 DB に接続しない) | 成果物(`judge_member_artifact`)。下の表の順 1〜6 はこの実行にだけ適用する |

- 判定元の選択は、成果物だけの判定表の順 1(execution-spec.json の有無)より先に行う。契約 `shared_rules.housekeep_rules.member_source` の判定の順 (1)〜(3) は成果物だけで判定する実行の規則で、parallel_runs 行がある実行には適用しない(要求 SPEC-014-05 の「管理 DB の行の削除に失敗した単位を次回に削除する」と一致させるため)

### 管理 DB で判定する実行(domain `judge_member_db`)

| 条件 | 結果 |
|---|---|
| parallel_runs.status が STARTED / RUNNING | 終わっていない |
| その run_id の slot_executions に RUNNING がある | 終わっていない |
| その run_id の rapid_crosscheck_requests が REQUESTED / CLAIMED / RUNNING | 終わっていない |
| 上記に当たらず、終端状態の行の completed_at に NULL がある | 判定できない(warn: run kept completed_at missing) |
| 上記に当たらない | 終わっている。終了日時 = parallel_runs・slot_executions・rapid_crosscheck_requests の completed_at の最大 |

- slot_executions 行が 0 件の実行(速報比較依頼だけのリランで作られた run)は slot の条件を満たすものとする
- rapid_crosscheck_requests 行が無い実行は依頼の条件を満たすものとする
- rapid_runs と monitor_records は判定に使わない

### 成果物だけで判定する実行(domain `judge_member_artifact`。parallel_runs 行が無い実行だけ)

| 順 | 条件 | 結果 |
|---|---|---|
| 1 | execution-spec.json が無い | 判定できない(warn: run kept execution-spec missing) |
| 2 | 読めない・解析できない・`slots` に role が無い・`parent_run_id` が不正。管理 DB に接続しないときは、`rapid_crosscheck_mode` が foreground / background / off のどれでもない(キーが無いを含む)場合も含む | 判定できない(warn: run kept execution-spec invalid) |
| 3 | 管理 DB に接続しない(要否の表の順 4。管理 DB を一切使わない設置で `HOUSEKEEP_DB_CONN_REF` が無い・空)かつ `rapid_crosscheck_mode` が foreground / background | 判定できない(warn: run kept rapid crosscheck mode。終了ファイルは見ない) |
| 4 | `slots` に載っている role のディレクトリ `<run_dir>/<role>/` が無い | 判定できない(warn: run kept slot artifact missing。role ごとに 1 行) |
| 5 | 載っている role のどれかに exitcode.txt も aborted.txt も無い | 終わっていない(warn は出さない) |
| 6 | 上記に当たらない | 終わっている。終了日時 = 各 role の exitcode.txt(無ければ aborted.txt)の更新時刻の最大 |

- `slots` に節が無い role(mode が off)は判定に含めない
- 終了ファイルは確定名だけを見る。`.tmp` は無視する
- 判定には started-at.txt と execution-spec.json の時刻を使わない
- 順 3 は契約 `shared_rules.housekeep_rules.member_source` の規則で、要求 SPEC-014-08 により管理 DB に接続しないときは順 4〜6 より優先する。管理 DB に接続するときは `rapid_crosscheck_mode` を判定に使わない(管理 DB に行が無い実行は off の期間に作られたものとして成果物で判定する)

### 単位の判定(domain `judge_unit`)

| 優先 | 条件 | 結果 | reason |
|---|---|---|---|
| 1 | 判定できない実行が 1 つ以上ある | 残す | undeterminable |
| 2 | 終わっていない実行が 1 つ以上ある | 残す | unfinished |
| 3 | 単位全体の最も遅い終了日時 ≥ cutoff | 残す | within_retention |
| 4 | 上記に当たらない | 削除対象 | — |

### 確報比較依頼の判定

| 条件 | 結果 |
|---|---|
| status が SUCCEEDED / FAILED / ABORTED で completed_at < cutoff | 削除対象(1 件ずつ。completed_at の昇順、同時刻は final_crosscheck_id の昇順) |
| status が REQUESTED / CLAIMED / RUNNING | 日数にかかわらず残す |
| 管理 DB に接続しない(管理 DB を一切使わない設置) | 判定しない(接続参照名が無いことは、起動時の `warn: management db is not configured ...` で知らせる) |

- `RAPID_CROSSCHECK_MODE=off` でも、確報クロスチェックを使う設置では接続参照名が必須のため、管理 DB に接続して同じ規則で判定する

### バリデーション・冪等性・競合

- **バリデーション**: 未知のオプションと余分な引数は終了コード 2。設定エラーは削除待ちの置き場の残りを含め何も削除しない
- **確認プロンプト**: なし(定期ジョブから非対話で起動する)
- **冪等性**: 判定は成果物と管理 DB の現在の内容と現在時刻だけで決まる。状態を更新せず、依頼を作らず、プロセスを停止しない
- **判定後の変化**: 判定のあとで単位に新しい実行が加わった場合の扱いは、UC「成果物と管理 DB の履歴を削除する」のトランザクションの規則で決まる

## ティア完了条件(BDD)

「管理 DB には接続しない」の確かめ方は spec.md の E2E 完了条件の冒頭と同じ(housekeep_del の接続が 1 件も記録されない)。

```gherkin
Feature: 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する - 実行監視・復旧ティア

  Background:
    Given RELAY_GATE_NOW=2026-11-28T12:00:00Z で TZ=UTC である
    And シナリオに記載が無ければ RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_DB_CONN_REF が無い
    And シナリオに記載が無ければ $RELAY_GATE_CONFIG_DIR/final-crosscheck.env は無い(管理 DB を一切使わない設置)

  Scenario: 保持日数 30 日で cutoff を算出する
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=30 があり RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無い
    When `housekeep.sh` を実行する
    Then 終了コード 0 で stdout の 1 行目が retention_days=30、2 行目が cutoff=2026-10-29T12:00:00 である

  Scenario: off 以外で接続参照名が無ければ何も削除せず 2
    Given RAPID_CROSSCHECK_MODE=background で housekeep.env に HOUSEKEEP_DB_CONN_REF が無い
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr に "error: option required option=HOUSEKEEP_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/housekeep.env" が出る
    And housekeep-pending/ の中身と facade/ の中身は変わらない

  Scenario Outline: off で接続参照名が無いとき final-crosscheck.env の FINAL_DB_CONN_REF の有無で要否を決める
    Given 前回の実行の残りとして housekeep-pending/20260801T090000-JOB006-a1b2c3d4/ がある
    And $RELAY_GATE_CONFIG_DIR/final-crosscheck.env が <final_env> である
    When `housekeep.sh` を実行する
    Then 終了コード <code> で、stderr に "<line>" が出る
    And housekeep-pending/20260801T090000-JOB006-a1b2c3d4/ は <pending>

    Examples:
      | final_env                                   | code | line                                                                                                  | pending |
      | 無い                                        | 0    | warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set) | 無くなる |
      | `FINAL_DB_CONN_REF=` の行だけを持つ          | 0    | warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set) | 無くなる |
      | `FINAL_POLL_LIMIT_SEC=3600` の行だけを持つ   | 0    | warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set) | 無くなる |
      | `FINAL_DB_CONN_REF=relay_gate_final` の行を持つ | 2 | error: option required option=HOUSEKEEP_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/housekeep.env      | 残る |
      | ある(読み取り権限が無い)                      | 2    | error: config file is not readable path: $RELAY_GATE_CONFIG_DIR/final-crosscheck.env                  | 残る |

  Scenario: 設定エラーが複数あれば最初の段のエラーだけを出す
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=0 があり HOUSEKEEP_DB_CONN_REF が無く、$RELAY_GATE_CONFIG_DIR/final-crosscheck.env が読み取り権限の無いファイルである
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=0 path: $RELAY_GATE_CONFIG_DIR/housekeep.env" と "hint: use a positive integer" の 2 行だけで、"final-crosscheck.env" を含む行は出ない

  Scenario: final-crosscheck.env に同じキーが 2 行あれば使わないキーでも何も削除せず 2
    Given RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_DB_CONN_REF が無く、前回の実行の残りとして housekeep-pending/20260801T090000-JOB006-a1b2c3d4/ がある
    And $RELAY_GATE_CONFIG_DIR/final-crosscheck.env の 1 行目が FINAL_POLL_INTERVAL_SEC=5、2 行目が FINAL_POLL_INTERVAL_SEC=10 で、FINAL_DB_CONN_REF の行が無い
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr の error 行は "error: duplicate key key=FINAL_POLL_INTERVAL_SEC lines=1,2 path: $RELAY_GATE_CONFIG_DIR/final-crosscheck.env" の 1 行だけである(契約 config_input_rules.env_files。読み手が使わないキーの重複も設定エラー)
    And stderr に "warn: management db is not configured" で始まる行は出ず、housekeep-pending/20260801T090000-JOB006-a1b2c3d4/ と facade/ の中身は変わらない

  Scenario: 接続参照名があれば final-crosscheck.env を読まない
    Given RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep があり、$RELAY_GATE_CONFIG_DIR/final-crosscheck.env が読み取り権限の無いファイルである
    When `housekeep.sh` を実行する
    Then 終了コード 0 で、stderr に "final-crosscheck.env" を含む行と "warn: management db is not configured" で始まる行は出ない

  Scenario: 確報クロスチェックを使う設置の判定では FINAL_DB_CONN_REF の値を出力しない
    Given $RELAY_GATE_CONFIG_DIR/final-crosscheck.env に `FINAL_DB_CONN_REF=relay_gate_final` と `UNKNOWN_FINAL_KEY=1` の行がある
    When `housekeep.sh` を実行する
    Then 終了コード 2 で、stdout・stderr・housekeep.sh.log のどれにも "relay_gate_final" と "UNKNOWN_FINAL_KEY" は出ない

  Scenario: housekeep.env が無ければ 2
    Given $RELAY_GATE_CONFIG_DIR/housekeep.env が無い
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: $RELAY_GATE_CONFIG_DIR/housekeep.env" が出る

  Scenario: 引用符と空白を外した保持日数を使う
    Given housekeep.env に `HOUSEKEEP_RETENTION_DAYS= "30" ` の行があり RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無い
    When `housekeep.sh` を実行する
    Then 終了コード 0 で stdout に retention_days=30 が出る

  Scenario: 未知キーは warn で継続する
    Given housekeep.env に RETENTION=30 の行がある
    When `housekeep.sh` を実行する
    Then stderr に "warn: unknown key key=RETENTION path: $RELAY_GATE_CONFIG_DIR/housekeep.env" が出て、stdout に retention_days=90 が出る

  Scenario: run_id 形式に合わないディレクトリと .tmp は無視する
    Given facade/ に tmp-work/ と 20260830T110000-JOB001-3f9a1c2e.tmp/ がある
    When `housekeep.sh` を実行する
    Then 両方のディレクトリは残り、stderr に両方の名前を含む行は出ない

  Scenario: 親が既に無い兄弟は 1 単位として判定する
    Given RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無い
    And facade/20260830T100000-JOB001-aaaa0001/ と facade/20260830T100500-JOB001-aaaa0002/ の execution-spec.json の rapid_crosscheck_mode がどちらも off、parent_run_id がどちらも 20260830T090000-JOB001-aaaa0000 で、facade/20260830T090000-JOB001-aaaa0000/ は無い
    And aaaa0001 は終了ファイルの最大更新時刻が 2026-08-30T10:10:00、aaaa0002 は green/ に終了ファイルが無い
    When `housekeep.sh --verbose` を実行する
    Then 両方のディレクトリが残り、stderr に "info: unit kept root_run_id=20260830T100000-JOB001-aaaa0001 reason=unfinished" が 1 行だけ出る

  Scenario: 判定できない実行を含む単位は reason=undeterminable で残す
    Given RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無く、facade/20260301T100000-JOB005-11223344/execution-spec.json が `{` だけの内容である
    When `housekeep.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "warn: run kept execution-spec invalid run_id=20260301T100000-JOB005-11223344 path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260301T100000-JOB005-11223344/execution-spec.json" と "info: unit kept root_run_id=20260301T100000-JOB005-11223344 reason=undeterminable" が出る

  Scenario: 管理 DB の接続に失敗したら単位を判定せず 6
    Given RAPID_CROSSCHECK_MODE=background で HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep が接続できない参照名である
    And facade/20260830T110000-JOB001-3f9a1c2e/ がすべて終了して保持日数を過ぎている
    When `housekeep.sh` を実行する
    Then 終了コード 6 で stderr に "error: management db connection failed conn_ref=relay_gate_housekeep" が出る
    And facade/20260830T110000-JOB001-3f9a1c2e/ は残り、stdout に deleted_run_units=0 と kept_units=0 が出る

  Scenario: off で接続参照名が空でも警告を 1 行出して継続する
    Given RAPID_CROSSCHECK_MODE=off で housekeep.env に `HOUSEKEEP_DB_CONN_REF=` の行がある
    When `housekeep.sh` を実行する
    Then 終了コード 0 で stderr に "warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)" が 1 行だけ出て、stdout に deleted_final_crosscheck_requests=0 が出る
    And 管理 DB には接続しない

  Scenario: 管理 DB の判定は slot_executions を成果物より優先する
    Given RAPID_CROSSCHECK_MODE=background で run_id=20260601T100000-JOB004-0a0b0c0d の green/exitcode.txt はあるが slot_executions の green が RUNNING のままである
    When `housekeep.sh --verbose` を実行する
    Then stderr に "info: unit kept root_run_id=20260601T100000-JOB004-0a0b0c0d reason=unfinished" が出る

  Scenario: 管理 DB に接続しないとき off 以外の期間に作られた実行は終了ファイルを見ずに残す
    Given facade/20260830T110000-JOB001-3f9a1c2e/execution-spec.json の rapid_crosscheck_mode が background で、slots に green があり、green/ ディレクトリが無い
    When `housekeep.sh --verbose` を実行する
    Then 終了コード 0 で facade/20260830T110000-JOB001-3f9a1c2e/ は残る
    And stderr に "warn: run kept rapid crosscheck mode run_id=20260830T110000-JOB001-3f9a1c2e mode=background" と "info: unit kept root_run_id=20260830T110000-JOB001-3f9a1c2e reason=undeterminable" が出て、"warn: run kept slot artifact missing" で始まる行は出ない

  Scenario: 管理 DB に接続しないとき rapid_crosscheck_mode が無い execution-spec.json は不正として残す
    Given facade/20260830T110000-JOB001-3f9a1c2e/execution-spec.json に rapid_crosscheck_mode のキーが無く、slots に green があり、green/exitcode.txt の更新時刻が 2026-08-30T11:40:00 である
    When `housekeep.sh` を実行する
    Then 終了コード 0 で facade/20260830T110000-JOB001-3f9a1c2e/ は残り、stderr に "warn: run kept execution-spec invalid run_id=20260830T110000-JOB001-3f9a1c2e path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T110000-JOB001-3f9a1c2e/execution-spec.json" が出る

  Scenario: 管理 DB に接続するときは rapid_crosscheck_mode によらず行の無い実行を成果物で判定する
    Given RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep があり、管理 DB に run_id=20260830T110000-JOB001-3f9a1c2e の行が無い
    And facade/20260830T110000-JOB001-3f9a1c2e/execution-spec.json の rapid_crosscheck_mode が background で、slots に green があり、green/exitcode.txt の更新時刻が 2026-08-30T11:40:00 である
    When `housekeep.sh` を実行する
    Then 終了コード 0 で facade/20260830T110000-JOB001-3f9a1c2e/ が無く、stderr に "warn: run kept rapid crosscheck mode" で始まる行は出ない

  Scenario: 成果物が無く parallel_runs 行だけが残った終了済みの実行は管理 DB の行で判定して削除する
    Given RAPID_CROSSCHECK_MODE=background で housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep がある
    And facade/20260830T110000-JOB001-3f9a1c2e/ も hang-detector-notified/20260830T110000-JOB001-3f9a1c2e.* も無く(前回の実行が成果物を削除したあとで管理 DB の行の削除に失敗した)、管理 DB に run_id=20260830T110000-JOB001-3f9a1c2e の parallel_runs(COMPLETED)・slot_executions(SUCCEEDED)・rapid_crosscheck_requests(SUCCEEDED)の行が残り、completed_at の最大が 2026-08-30T11:20:00 である
    When `housekeep.sh --verbose` を実行する
    Then 終了コード 0 で、管理 DB に run_id=20260830T110000-JOB001-3f9a1c2e の行が無い
    And stderr に "warn: run kept" で始まる行は出ず、"info: unit deleted root_run_id=20260830T110000-JOB001-3f9a1c2e run_ids=1 latest_completed_at=2026-08-30T11:20:00" が出る

  Scenario: parallel_runs 行がある実行は execution-spec.json が壊れていても成果物の warn を出さない
    Given RAPID_CROSSCHECK_MODE=background で housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep がある
    And 管理 DB の run_id=20260830T110000-JOB001-3f9a1c2e の行がすべて終端し completed_at の最大が 2026-08-30T11:20:00 で、facade/20260830T110000-JOB001-3f9a1c2e/execution-spec.json が JSON として解析できず、green/ ディレクトリが無い
    When `housekeep.sh` を実行する
    Then 終了コード 0 で facade/20260830T110000-JOB001-3f9a1c2e/ と管理 DB の行が無い
    And stderr に "warn: run kept execution-spec invalid" / "warn: run kept slot artifact missing" で始まる行は出ない

  Scenario: 成果物ルートがディレクトリでなければ走査前の設定エラーにして何も削除しない
    Given RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_RETENTION_DAYS=90 だけがあり、final-crosscheck.env が無く、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate が通常のファイルである
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stderr に "error: artifact root not found path: /var/relay-gate" が出て、何も削除しない

  Scenario: feature-flag.env の未知のキーと FINAL_ で始まるキーは housekeep.sh では検査しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off と "LEGACY_FLAG=1" と "FINAL_CROSSCHECK_MODE=on" があり、housekeep.env に HOUSEKEEP_RETENTION_DAYS=90 だけがあり、final-crosscheck.env が無く、削除対象が無い
    When `housekeep.sh` を実行する
    Then 終了コード 0 で stderr は "warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)" の 1 行だけである
```
