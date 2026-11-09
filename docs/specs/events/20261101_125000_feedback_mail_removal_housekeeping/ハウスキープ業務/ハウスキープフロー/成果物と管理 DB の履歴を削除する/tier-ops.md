# 成果物と管理 DB の履歴を削除する - 実行監視・復旧ティア仕様

## 変更概要

`housekeep.sh` の削除部分を定義する。
対象は、削除待ちの置き場の残りの削除、実行の単位の削除順序、管理 DB のトランザクション、確報比較依頼の削除、孤立した通知済みの印の削除、失敗と回復、stdout / stderr / 終了コードである。
コマンドの書式・設定・判定は UC「[保持日数を過ぎた終了済みの実行と確報比較依頼を判定する](../保持日数を過ぎた終了済みの実行と確報比較依頼を判定する/tier-ops.md)」が定義する。

| レイヤー | 責務 |
|---|---|
| usecase | 削除の手順と順序を守る(LP-025)。単位の失敗を記録して次の単位へ続ける |
| domain | 単位内の parallel_runs の削除順(子孫から)、孤立した印の判定、件数の集計 |
| repository | 置き場への移動と削除、管理 DB の DELETE |
| gateway | ファイルシステム(同じファイルシステム内の rename)、RDB クライアント(housekeep_del) |

## コマンド契約

### housekeep.sh(削除部分)

- **書式**: `housekeep.sh [--verbose] [--help]`(UC「保持日数を過ぎた終了済みの実行と確報比較依頼を判定する」と同じ 1 回の実行)
- **アクセス権**: 成果物ルートの `facade/` / `hang-detector-notified/` / `housekeep-pending/` の書き込み権限。管理 DB の DELETE はハウスキープ専用 DB ロール housekeep_del(`HOUSEKEEP_DB_CONN_REF`)だけで行う
- 削除の規則の正本は [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml) の `shared_rules.housekeep_rules`

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 削除の有無はオプションで制御しない |

- **stdin**: なし

## 出力契約

- **stdout**(固定順の 8 行。終了コード 0 と 6 で出す。2 では出さない):

| 順 | 行 | 数えるもの |
|---|---|---|
| 1 | `retention_days=<N>` | 使った保持日数 |
| 2 | `cutoff=<ローカル日時>` | 期限(判定 UC の規則) |
| 3 | `purged_pending_entries=<N>` | 手順 1 で削除した置き場の直下のエントリ数 |
| 4 | `deleted_run_units=<N>` | 成果物の削除と管理 DB の COMMIT まで終えた単位の数 |
| 5 | `deleted_runs=<N>` | 4 の単位に含まれる run_id の数 |
| 6 | `deleted_final_crosscheck_requests=<N>` | COMMIT まで終えた確報比較依頼の件数 |
| 7 | `deleted_orphan_marks=<N>` | 削除した孤立した印のファイル数 |
| 8 | `kept_units=<N>` | 判定で残した単位の数(unfinished / within_retention / undeterminable) |

- 削除の途中で失敗した単位は 4・5・8 のどれにも数えない
- 管理 DB の接続・SELECT の失敗で単位を処理しなかった場合、4〜8 は 0

- **stderr**(失敗。終了コード 6。発生順に 1 件 1 行):

| 条件 | 行 | その後 |
|---|---|---|
| 置き場の残りの削除に失敗 | `error: pending entry delete failed path: <置き場のエントリ>` | 次のエントリと判定へ続ける |
| 置き場のディレクトリを作れない | `error: pending dir create failed path: $RELAY_GATE_ARTIFACT_ROOT/housekeep-pending` | 単位・確報比較依頼・孤立した印を処理しない |
| run ディレクトリまたは印の rename に失敗、または移動先が既にある | `error: artifact move failed run_id=<run_id> path: <移動元>` | その単位の残りの手順をしない |
| 置き場へ移したものの削除に失敗 | `error: artifact delete failed path: <置き場のエントリ>` | その単位の管理 DB の行を消さない |
| 単位の管理 DB の削除に失敗(外部キー違反を含む) | `error: management db delete failed run_ids=<run_id をカンマ区切り。昇順>` | ロールバック済み。次の単位へ |
| 確報比較依頼の削除に失敗 | `error: management db delete failed final_crosscheck_id=<id>` | 次の依頼へ |

- **stderr**(`--verbose` のとき): 削除し終えた単位ごとに `info: unit deleted root_run_id=<run_id> run_ids=<N> latest_completed_at=<ローカル日時>`
- **実行ログ**(`$RELAY_GATE_LOG_DIR/housekeep.sh.log`。行形式は契約 `conventions.execution_log`):

| 契機 | run_id 欄 | message |
|---|---|---|
| run を削除し終えた(単位の COMMIT 後。単位内の run_id ごとに 1 行) | 削除した run_id | `INFO run deleted root_run_id=<run_id> latest_completed_at=<ローカル日時>` |
| 確報比較依頼を削除し終えた | final_crosscheck_id | `INFO final crosscheck request deleted completed_at=<ローカル日時>` |
| 終了 | `-` | `INFO housekeep finished` に stdout の 3〜8 行目と同じ key=value を空白区切りで続ける |
| 失敗 | 該当 run_id または `-` | stderr と同じ文言を ERROR で残す |

- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 成功 | 失敗 0 件(削除件数 0 を含む。warn があっても 0) |
| 2 | 入力・設定検証エラー | 判定 UC の起動時検証(何も削除しない) |
| 6 | 実行エラー | 上表の失敗、または判定 UC の管理 DB 接続・SELECT・`facade/` 読み取りの失敗が 1 件以上(削除できたものは削除したうえで 6) |

## UC ロジック

### 手順 1: 置き場の残りの削除

1. `$RELAY_GATE_ARTIFACT_ROOT/housekeep-pending/` が無ければ作る。
2. 直下のエントリ(`notified-` で始まる印を含む)を判定せずにすべて削除する。
3. エントリごとに成否を数え、失敗は error を出して次のエントリへ続ける。

### 単位の削除手順(削除対象の単位ごと。root_run_id の昇順)

| 順 | 操作 | 既に無い場合 | 失敗した場合 |
|---|---|---|---|
| 1 | 単位内の各 run ディレクトリ `facade/<run_id>` を `housekeep-pending/<run_id>` へ rename する(run_id の昇順。同じファイルシステム内の 1 回の操作) | 削除済みとして飛ばす | 単位の残りの手順をしない |
| 2 | 単位内の各 run_id について、`hang-detector-notified/` の中で名前が `<run_id>.` で始まるエントリ(`<run_id>.<role>` と `<run_id>.<role>.tmp`)を `housekeep-pending/notified-<元の名前>` へ rename する | 飛ばす | 単位の残りの手順をしない |
| 3 | 1・2 で置き場へ移したこの単位のエントリを削除する | — | 管理 DB の行を消さない |
| 4 | 管理 DB に接続しているとき、単位内のすべての run_id の行を 1 トランザクションで削除する(下記) | 0 件の DELETE は成功として続ける | ロールバックして次の単位へ |

- 1 の移動先が既にある場合は上書きも入れ子への移動もせず、失敗として扱う
- run ディレクトリを先に移してから印を動かす。印の無い run ディレクトリを hang-detector が見て再び知らせることを防ぐ
- 管理 DB に接続しないとき(off で `HOUSEKEEP_DB_CONN_REF` が無い)は 3 で単位を削除し終えたものとする

### 単位の管理 DB の削除(1 トランザクション)

```text
BEGIN
DELETE FROM monitor_records            WHERE run_id IN (:run_ids)
DELETE FROM rapid_crosscheck_requests  WHERE run_id IN (:run_ids) AND status IN ('SUCCEEDED','FAILED','ABORTED')
DELETE FROM rapid_runs                 WHERE run_id IN (:run_ids)
DELETE FROM slot_executions            WHERE run_id IN (:run_ids) AND status IN ('SUCCEEDED','FAILED','ABORTED')
DELETE FROM parallel_runs              WHERE run_id = :run_id AND status IN ('COMPLETED','ABORTED')  -- 子孫から 1 行ずつ
COMMIT
```

- `:run_ids` は単位内のすべての run_id(成果物だけで判定した実行も含む)。off の期間に作られた実行でも、off 以外の期間の hang-detector が書いた monitor_records を一緒に消す
- parallel_runs は、単位内の親子関係での深さが深いものから削除する。同じ深さは run_id の降順。parent_run_id の自己参照外部キーが RESTRICT のため
- 状態の条件は、判定のあとで終わっていない行が加わった場合に、その行を消さないための条件である。残った行が parallel_runs を参照していれば parallel_runs の DELETE が外部キー違反になり、トランザクション全体がロールバックする
- 判定のあとで単位内の run を親に持つ新しい run が作られた場合も、parallel_runs の DELETE が外部キー違反になりロールバックする。次回の走査では新しい run を含む単位として判定する
- ロールバック後、成果物は既に消えている。管理 DB の行が残るため、次回の走査で同じ単位を再び見つけ、既に無いファイルは削除済みとして扱って行の削除を続ける
- 日時はホストで生成し、SQL にはバインド値で渡す(契約 `conventions.datetime_generation`)

### 確報比較依頼の削除

- 判定 UC で削除対象とした依頼ごとに、1 件 1 トランザクションで削除する:
  `DELETE FROM final_crosscheck_requests WHERE final_crosscheck_id = ? AND status IN ('SUCCEEDED','FAILED','ABORTED') AND completed_at < ?`
- 1 件の失敗は error を出して次の依頼へ続ける

### 孤立した通知済みの印の削除

| 項目 | 規則 |
|---|---|
| 対象 | `hang-detector-notified/` 直下で、名前が `<run_id>.` で始まり `<run_id>` が run_id 形式に合うエントリ。合わない名前は触らない |
| 孤立の条件 | その run_id の run ディレクトリが `facade/` に無く、管理 DB に接続しているときは parallel_runs 行も無い |
| 手順 | `housekeep-pending/notified-<元の名前>` へ rename してから削除する |
| 失敗 | rename は `error: artifact move failed run_id=<run_id> path: ...`、削除は `error: artifact delete failed path: ...`。次のエントリへ続ける |

### 冪等性・競合・クラッシュ

- **確認プロンプト**: なし
- **冪等性**: 置き場の残りは次回の手順 1 で判定せずに消える。管理 DB の行が残った単位は次回の走査で再び見つかる。削除し終えた状態で再実行すると件数はすべて 0 で終了コード 0
- **途中終了**: rename は 1 回の操作なので、run ディレクトリは `facade/` か置き場のどちらかにある。トランザクションは COMMIT 前に終われば行が残る
- **リランとの競合**:

| 時点 | `--role blue|green` | `--role rapid-crosscheck` |
|---|---|---|
| run ディレクトリの rename の後 | `error: execution-spec not found ...`(3)。新しい run は作られない | 管理 DB の行が残っていれば依頼を再作成する。parallel_runs の DELETE が外部キー違反でロールバックし(6)、次回は単位を残す |
| run ディレクトリの rename の前に新しい run ができた | 管理 DB に接続していれば parallel_runs の DELETE が外部キー違反でロールバックし(6)、次回は単位を残す。off で接続しないときは、新しい run の execution-spec.json の親が無い単位として別に判定する | 同左 |
| 管理 DB の COMMIT の後 | `error: execution-spec not found ...`(3) | 依頼が無いため既存の `error: source request not found ...`(3)、または新しい run の INSERT が外部キー違反で失敗(6) |

- **hang-detector との並走**: housekeep は終端した実行の単位だけを移動・削除する。rename は 1 回の操作のため、hang-detector からは run ディレクトリがあるか無いかのどちらかに見える。housekeep の手順 2 の後に hang-detector が書いた印は、run ディレクトリも parallel_runs 行も無いため、同じ実行の手順「孤立した通知済みの印の削除」か次回の実行で消える
- **削除の所有**: 管理 DB の行と成果物を削除するのは housekeep だけ(arch CTR-008)。状態を更新せず、依頼を作らず、プロセスを停止しない(LP-025)

## ティア完了条件(BDD)

```gherkin
Feature: 成果物と管理 DB の履歴を削除する - 実行監視・復旧ティア

  Background:
    Given RELAY_GATE_NOW=2026-11-28T12:00:00Z で TZ=UTC である
    And RAPID_CROSSCHECK_MODE=background で housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep がある

  Scenario: リランの親子は子孫から parallel_runs を削除する
    Given run_id=20260830T110000-JOB001-3f9a1c2e、その子 20260830T113000-JOB001-5d6e7f80、孫 20260830T114000-JOB001-6e7f8091 がすべて終端し、completed_at の最大が 2026-08-30T11:50:00 である
    When `housekeep.sh --verbose` を実行する
    Then 終了コード 0 で 3 件の parallel_runs 行が無く、stderr に "info: unit deleted root_run_id=20260830T110000-JOB001-3f9a1c2e run_ids=3 latest_completed_at=2026-08-30T11:50:00" が出る
    And housekeep.sh.log に "INFO run deleted root_run_id=20260830T110000-JOB001-3f9a1c2e" を含む行が 3 行ある

  Scenario: run ディレクトリを移してから印を移す
    Given RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無く、facade/20260830T110000-JOB001-3f9a1c2e/ が削除対象で、hang-detector-notified/20260830T110000-JOB001-3f9a1c2e.green がある
    And housekeep-pending/ への rename を記録する
    When `housekeep.sh` を実行する
    Then rename の記録は facade/20260830T110000-JOB001-3f9a1c2e → housekeep-pending/20260830T110000-JOB001-3f9a1c2e、hang-detector-notified/20260830T110000-JOB001-3f9a1c2e.green → housekeep-pending/notified-20260830T110000-JOB001-3f9a1c2e.green の順である

  Scenario: 移動先が置き場に既にあれば単位を削除しない
    Given housekeep-pending/20260830T110000-JOB001-3f9a1c2e/ が削除できずに残り、facade/20260830T110000-JOB001-3f9a1c2e/ が削除対象である
    When `housekeep.sh` を実行する
    Then 終了コード 6 で stderr に "error: pending entry delete failed path: $RELAY_GATE_ARTIFACT_ROOT/housekeep-pending/20260830T110000-JOB001-3f9a1c2e" と "error: artifact move failed run_id=20260830T110000-JOB001-3f9a1c2e path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T110000-JOB001-3f9a1c2e" が出る
    And facade/20260830T110000-JOB001-3f9a1c2e/ と管理 DB の行は残る

  Scenario: 1 つの単位の失敗は次の単位の削除を止めない
    Given 削除対象の単位 20260830T090000-JOB007-01020304 と 20260830T110000-JOB001-3f9a1c2e があり、前者の管理 DB の削除がエラーになる
    When `housekeep.sh` を実行する
    Then 終了コード 6 で stderr に "error: management db delete failed run_ids=20260830T090000-JOB007-01020304" が出る
    And 20260830T110000-JOB001-3f9a1c2e の成果物と管理 DB の行は無く、stdout に deleted_run_units=1 と kept_units=0 が出る

  Scenario: 孤立した印を削除する
    Given RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無く、hang-detector-notified/20260520T080000-JOB008-0f0e0d0c.blue があり、facade/20260520T080000-JOB008-0f0e0d0c/ が無い
    And hang-detector-notified/README がある
    When `housekeep.sh` を実行する
    Then 終了コード 0 で hang-detector-notified/20260520T080000-JOB008-0f0e0d0c.blue が無く、hang-detector-notified/README は残る
    And stdout に deleted_orphan_marks=1 が出る

  Scenario: off で管理 DB に接続しないときは成果物だけを削除する
    Given RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無く、facade/20260830T110000-JOB001-3f9a1c2e/ が削除対象である
    When `housekeep.sh` を実行する
    Then 終了コード 0 で facade/20260830T110000-JOB001-3f9a1c2e/ が無く、管理 DB には接続しない
    And stdout に deleted_run_units=1 と deleted_final_crosscheck_requests=0 が出る

  Scenario: 管理 DB の削除はハウスキープ専用 DB ロールで行う
    Given HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep が housekeep_del の接続を指す
    When `housekeep.sh` が単位 20260830T110000-JOB001-3f9a1c2e を削除する
    Then DELETE を発行したセッションのロールは housekeep_del である
```
