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
| repository | ハウスキープ設定、feature flag 設定、成果物ルートの走査、管理 DB の SELECT |
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
入力の守備範囲(NUL / UTF-8 / BOM / CR の拒否、引用符と空白の外し方)は契約 `config_input_rules` の `env_files` に従う。

| キー | 必須 | 既定値 | 起動時の検査 |
|---|---|---|---|
| `HOUSEKEEP_RETENTION_DAYS` | No | 90 | 値が `^[1-9][0-9]{0,8}$` に合わなければ `error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=... path: ...` + `hint: use a positive integer`(2) |
| `HOUSEKEEP_DB_CONN_REF` | `RAPID_CROSSCHECK_MODE` が off 以外のとき Yes | なし | 欠落・空は `error: option required option=HOUSEKEEP_DB_CONN_REF path: ...`(2) |
| 上記以外 | — | — | `warn: unknown key key=<KEY> path: ...`(継続) |

- `RAPID_CROSSCHECK_MODE` は feature-flag.env から読む。値の検査と文言は契約 `config_files` の feature-flag.env `error_messages` と同じ
- off で `HOUSEKEEP_DB_CONN_REF` があれば、管理 DB の行(確報比較依頼と、off 以外の期間に作られた実行の行)も判定する
- off で `HOUSEKEEP_DB_CONN_REF` が無い・空なら、管理 DB に接続せず成果物だけを判定する。処理の順序の 5(接続の判断)で、起動のたびに `warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)` を stderr に 1 行出す。確報比較依頼と管理 DB の行は判定も削除もしない。終了コードは変えない(ほかに失敗が無ければ 0)。確報クロスチェックを使う構成では設定する

## 出力契約

stdout の 8 行と削除の失敗行は UC「成果物と管理 DB の履歴を削除する」の tier-ops.md を参照する。

- **stderr**(走査前の設定エラー。終了コード 2。stdout は出さない):

| 条件 | 行 |
|---|---|
| housekeep.env が無い | `error: config file not found path: $RELAY_GATE_CONFIG_DIR/housekeep.env` |
| housekeep.env が読めない | `error: config file is not readable path: $RELAY_GATE_CONFIG_DIR/housekeep.env` |
| feature-flag.env が無い・読めない | `error: config file not found path: ...` / `error: config file is not readable path: ...` |
| 保持日数が不正 | `error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=... path: ...` + `hint: use a positive integer` |
| off 以外で接続参照名が無い・空 | `error: option required option=HOUSEKEEP_DB_CONN_REF path: ...` |
| `RELAY_GATE_ARTIFACT_ROOT` が無い | `error: artifact root not found path: ...` |
| 未知のオプション / 余分な引数 | `error: unknown option option=...` / `error: unexpected argument value=...` |

- **stderr**(設定の警告。終了コードに影響しない):

| 条件 | 行 |
|---|---|
| housekeep.env に未知のキーがある | `warn: unknown key key=<KEY> path: ...` |
| off で `HOUSEKEEP_DB_CONN_REF` が無い・空(起動のたびに 1 行) | `warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)` |

- **stderr**(判定の継続。終了コードに影響しない。その実行を含む単位を残す):

| 条件 | 行 |
|---|---|
| 成果物だけで判定する実行に execution-spec.json が無い | `warn: run kept execution-spec missing run_id=<run_id> path: <run_dir>/execution-spec.json` |
| execution-spec.json が読めない・JSON として解析できない・`slots` に role が 1 つも無い・`parent_run_id` が null でも run_id 形式でもない | `warn: run kept execution-spec invalid run_id=<run_id> path: <run_dir>/execution-spec.json` |
| `slots` に載っている role のディレクトリが無い | `warn: run kept slot artifact missing run_id=<run_id> role=<role> path: <run_dir>/<role>` |
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
2. housekeep.env と feature-flag.env を読み、保持日数と接続参照名を確定する(ここまでの失敗は終了コード 2)。
3. cutoff を決める。
4. 削除待ちの置き場の残りを削除する(UC「成果物と管理 DB の履歴を削除する」)。
5. `HOUSEKEEP_DB_CONN_REF` があれば管理 DB に接続し、単位を作るための SELECT を行う。off で接続参照名が無い・空なら、ここで `warn: management db is not configured ...` を 1 行出して接続しない。このとき execution-spec.json の rapid_crosscheck_mode が off でない実行は判定できないものとして残し `warn: run kept rapid crosscheck mode run_id=... mode=...` を出す(契約 shared_rules.housekeep_rules.member_source)。
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
| parallel_runs 行がある(速報比較依頼だけのリランで作られた run を含む) | 管理 DB の行(`judge_member_db`) |
| parallel_runs 行が無く run ディレクトリがある(off で作られた実行、または管理 DB に接続しない) | 成果物(`judge_member_artifact`) |

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

### 成果物だけで判定する実行(domain `judge_member_artifact`)

| 順 | 条件 | 結果 |
|---|---|---|
| 1 | execution-spec.json が無い | 判定できない(warn: run kept execution-spec missing) |
| 2 | 読めない・解析できない・`slots` に role が無い・`parent_run_id` が不正 | 判定できない(warn: run kept execution-spec invalid) |
| 3 | `slots` に載っている role のディレクトリ `<run_dir>/<role>/` が無い | 判定できない(warn: run kept slot artifact missing。role ごとに 1 行) |
| 4 | 載っている role のどれかに exitcode.txt も aborted.txt も無い | 終わっていない(warn は出さない) |
| 5 | 上記に当たらない | 終わっている。終了日時 = 各 role の exitcode.txt(無ければ aborted.txt)の更新時刻の最大 |

- `slots` に節が無い role(mode が off)は判定に含めない
- 終了ファイルは確定名だけを見る。`.tmp` は無視する
- 判定には started-at.txt と execution-spec.json の時刻を使わない

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
| 管理 DB に接続しない | 判定しない(off で接続参照名が無いことは、起動時の `warn: management db is not configured ...` で知らせる) |

### バリデーション・冪等性・競合

- **バリデーション**: 未知のオプションと余分な引数は終了コード 2。設定エラーは何も削除しない
- **確認プロンプト**: なし(定期ジョブから非対話で起動する)
- **冪等性**: 判定は成果物と管理 DB の現在の内容と現在時刻だけで決まる。状態を更新せず、依頼を作らず、プロセスを停止しない
- **判定後の変化**: 判定のあとで単位に新しい実行が加わった場合の扱いは、UC「成果物と管理 DB の履歴を削除する」のトランザクションの規則で決まる

## ティア完了条件(BDD)

```gherkin
Feature: 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する - 実行監視・復旧ティア

  Background:
    Given RELAY_GATE_NOW=2026-11-28T12:00:00Z で TZ=UTC である
    And シナリオに記載が無ければ RAPID_CROSSCHECK_MODE=off で housekeep.env に HOUSEKEEP_DB_CONN_REF が無い

  Scenario: 保持日数 30 日で cutoff を算出する
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=30 があり RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無い
    When `housekeep.sh` を実行する
    Then 終了コード 0 で stdout の 1 行目が retention_days=30、2 行目が cutoff=2026-10-29T12:00:00 である

  Scenario: off 以外で接続参照名が無ければ何も削除せず 2
    Given RAPID_CROSSCHECK_MODE=background で housekeep.env に HOUSEKEEP_DB_CONN_REF が無い
    When `housekeep.sh` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr に "error: option required option=HOUSEKEEP_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/housekeep.env" が出る
    And housekeep-pending/ の中身と facade/ の中身は変わらない

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
    And facade/20260830T100000-JOB001-aaaa0001/ と facade/20260830T100500-JOB001-aaaa0002/ の execution-spec.json の parent_run_id がどちらも 20260830T090000-JOB001-aaaa0000 で、facade/20260830T090000-JOB001-aaaa0000/ は無い
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
```
