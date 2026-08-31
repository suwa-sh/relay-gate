# リラン対象を検証する - 実行監視・復旧ティア仕様

## 変更概要

`background-rerun.sh` のコマンド契約(引数・終了コード)と、起動直後に行う **事前検証表**(role × 元 slot mode × 元状態)を定義する。元実行の特定元は role で分岐する(blue / green: `execution-spec.json` 必須。rapid-crosscheck: `rapid_crosscheck_requests` のみで `execution-spec.json` は読まない。rapid-crosscheck リランで作られた run を再度リラン元にできる)。検証通過後の復元・起動は UC「元の execution-spec.json から復元して新しい run_id で起動する」、依頼再作成は UC「速報比較依頼だけを新規作成する」の tier-ops.md に書く。

## コマンド契約

### background-rerun.sh

- **書式**: `background-rerun.sh --source-run-id <RUN_ID> --role blue|green|rapid-crosscheck [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラの background リラン専用ジョブ(運用者が run_id と role を指定して起動)。運用者の直接起動も可。管理 DB(on 時)と成果物ディレクトリへのアクセスが必要

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--source-run-id` | string | Yes | なし | リラン元の run_id(`{UTC yyyymmddThhmmssZ}-{job_id}-{8 hex}`) |
| `--role` | enum(blue / green / rapid-crosscheck) | Yes | なし | リラン対象 role。`final-crosscheck` は run role だが background-rerun.sh の enum 外(確報は正規ジョブで再実行)。`final-crosscheck` を含む列挙外の値は引数不正(終了コード 2。`error: invalid value option=--role value=...`) |
| `--verbose` | boolean | No | false | `info:` を stderr に出す |
| `--help` | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: なし(対話しない。専用ジョブからの非 TTY 起動が主経路)

## 出力契約

- **stdout**: 検証段階では出力しない(通過後の出力は後続 UC。最終行は `run_id={新 run_id}` と `parent_run_id={元 run_id}`)
- **stderr**: 不可時は `error:` 1 行 + `hint:` 1 行
  | 判定結果 | error | hint |
  |---|---|---|
  | 元 mode が foreground | `error: source run is not rerunnable run_id=... role=... mode=foreground status=...` | `hint: rerun the scheduler job instead (foreground slot / final crosscheck are not handled by background-rerun.sh)` |
  | 元 mode が off(execution-spec.json に `slots.{role}` 節が無い) | `error: source run is not rerunnable run_id=... role=... mode=off status=-` | 同上 |
  | 元 slot が未起動(off 時に `started-at.txt` が無い) | `error: source run is not rerunnable run_id=... role=... mode=background status=-` | `hint: source run has not started; rerun the scheduler job instead` |
  | 元 slot が RUNNING | `error: source run is not rerunnable run_id=... role=... status=RUNNING` | `hint: abort the run with abort-{role}.sh --run-id {run_id} before rerun` |
  | 速報比較依頼が REQUESTED / CLAIMED / RUNNING | `error: source request is not rerunnable run_id=... role=rapid-crosscheck status=...` | RUNNING: `hint: abort the request with abort-rapid-crosscheck.sh --run-id {run_id} before rerun`。REQUESTED / CLAIMED: `hint: request is still queued; wait for the worker` |
  | 速報比較依頼が無い(rapid-crosscheck の元実行なし。execution-spec.json の有無は見ない) | `error: source request not found run_id=... role=rapid-crosscheck` | `hint: rapid crosscheck request is created only when both slots succeeded` |
  | execution-spec.json が無い(blue / green の元実行なし) | `error: execution-spec not found run_id=... path: {path}` | なし |
  | 元 slot の管理レコードが無い(on) | `error: run not found run_id=... role=...` | なし |
  | RAPID_CROSSCHECK_MODE=off かつ `--role rapid-crosscheck` | `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck`(管理 DB 接続前に判定。abort-* の off 時と同じ文言) | なし |
- **stderr(終了コード 6 / 警告)**: `error: execution-spec is not readable run_id=... path: {path}`(存在するが読めない / JSON 不正 / 必須キー欠落。6)/ `error: management db connection failed run_id=... role=... conn_ref=...`(6。接続失敗)/ `error: management db query failed run_id=...`(6。SQL 失敗)/ `warn: mode mismatch spec=... db=...`(on で execution-spec.json と管理レコードの mode が食い違うとき。処理は継続)
- **stderr(入力エラー 2)**: `error: option required option=--source-run-id|--role` / `error: invalid value option=--role value=...`(`final-crosscheck` を含む enum 外) / `error: invalid value option=--source-run-id value=...` / `error: unknown option option=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 検証を通過し後続 UC の起動 / 依頼作成が完了した |
  | 2 | 入力エラー | `--source-run-id` / `--role` 欠落、role が enum 外(`final-crosscheck` / `foo` 等)、run_id 形式不正、未知オプション |
  | 3 | 業務エラー(事前検証 NG) | 上表のすべて(off かつ rapid-crosscheck の管理 DB 無しを含む)。状態は変更しない |
  | 6 | 実行エラー | execution-spec.json の読み取り失敗(存在するが読めない / JSON 不正)、管理 DB 接続・SQL 失敗 |

## 事前検証表(domain `is_rerunnable`)

| `--role` | 元 slot mode | 元状態 | 判定 | 理由コード |
|---|---|---|---|---|
| blue / green | background | SUCCEEDED / FAILED / ABORTED | 可 | — |
| blue / green | background | RUNNING | 不可(中止未確認) | `source_running` |
| blue / green | background | `-`(off 時に started-at.txt が無い = 未起動) | 不可 | `source_not_started` |
| blue / green | foreground | 任意 | 不可 | `mode_not_background` |
| blue / green | off(`slots.{role}` 節なし) | (slot 実行なし) | 不可 | `mode_not_background` |
| rapid-crosscheck | — | 依頼 SUCCEEDED / FAILED / ABORTED | 可 | — |
| rapid-crosscheck | — | 依頼 RUNNING | 不可(中止未確認) | `request_running` |
| rapid-crosscheck | — | 依頼 REQUESTED / CLAIMED | 不可(未開始・処理中) | `request_not_terminal` |
| rapid-crosscheck | — | 依頼なし(on。execution-spec.json の有無は判定に使わない) | 不可 | `request_not_found` |
| rapid-crosscheck | — | RAPID_CROSSCHECK_MODE=off(管理 DB なし) | 不可(管理 DB 接続前に判定。終了コード 3) | `management_db_not_configured` |
| blue / green | — | execution-spec.json なし(元実行なし) | 不可 | `source_not_found` |
| final-crosscheck / 列挙外の文字列 | — | — | 引数不正(2。`error: invalid value option=--role value=...`)。事前検証に入らない。確報は正規ジョブで再実行する | — |

元実行の特定元(role で分岐):
- blue / green: `facade/<source_run_id>/execution-spec.json` を必須とする(無ければ `source_not_found`)。`slots.{role}` 節が無ければ mode=off とみなす(契約 execution_spec_rules「mode が off の slot は節を持たない」)
- rapid-crosscheck: `rapid_crosscheck_requests(run_id)` を必須とし(無ければ `request_not_found`)、`execution-spec.json` とファイルシステムは読まない。rapid-crosscheck リランで作られた run(`facade/<run_id>/execution-spec.json` を持たない)を再度 `--source-run-id` に指定でき、parent_run_id の数珠つなぎが成立する。後続 UC「速報比較依頼だけを新規作成する」が `rapid_runs` の成果物 URI を読む

元 mode / 元状態の解決(blue / green):
- 元 mode: execution-spec.json の `slots.{role}` 節が存在しない → off。存在すれば `slots.{role}.mode`
- RAPID_CROSSCHECK_MODE=on: `slot_executions(run_id, slot)` の `mode` / `status`。execution-spec.json の mode と食い違う場合は管理レコードを正とし `warn: mode mismatch spec=... db=...` を出す
- RAPID_CROSSCHECK_MODE=off: execution-spec.json の mode と `facade/<run_id>/<role>/started-at.txt` / `exitcode.txt`。started-at.txt 無し → 未起動(status=`-`。`source_not_started` で拒否。契約 artifact_layout の readers「started-at.txt なし = 未起動」に対応)。started-at.txt あり かつ exitcode.txt 無し → RUNNING、`0` → SUCCEEDED、非 0 → FAILED。ABORTED は導出できないため、明示中止済みでも exitcode.txt が無ければ RUNNING 扱いで拒否する(仮採用 #7。off 時の中止・リラン運用は todo)。rapid-crosscheck は off では管理 DB 自体が無いため、依頼を探さず管理 DB 接続前に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck` で 3(`request_not_found` の hint「両系成功時のみ作成」は出さない。abort-blue / abort-green / abort-rapid-crosscheck / run-lineage.sh の off 時と同じ文言)

## UC ロジック

- **バリデーション**: presentation で必須引数・列挙・形式を検証。NG は状態を読まず 2
- **確認プロンプト**: なし
- **冪等性**: 検証のみで書き込みは無い。同じ入力で同じ判定
- **エラーハンドリング**: 不可はすべて 3 で `error:` + `hint:`。ファイル読み取り失敗・DB 障害は 6。エラーは 1 回だけ出す(CLR-004)
- **クラッシュ耐性**: 検証段階で落ちても残るファイル・レコードは無い
- **実行ログ**(CLP-008): `background-rerun.sh {source_run_id} {UTC} INFO rerun requested operator={OS ユーザー} source_run_id=... role=...`、通過 `INFO precheck passed source_run_id=... role=... mode=... status=...`、不可 `INFO rerun rejected reason={理由コード} source_run_id=... role=... mode=... status=...`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」(= リラン指示の指示日時)はこの UTC 時刻列に対応する

## データモデル変更

読み取りのみ。

| テーブル / ファイル | 読む列・キー | 変更種別 |
|---|---|---|
| `facade/<source_run_id>/execution-spec.json` | `slots.{role}` 節の有無と mode(存在確認を兼ねる。blue / green のみ) | 追加(参照) |
| `facade/<source_run_id>/<role>/started-at.txt` | 有無(off 時の未起動判定。blue / green のみ) | 追加(参照) |
| `facade/<source_run_id>/<role>/exitcode.txt` | 中身(off 時の状態導出。blue / green のみ) | 追加(参照) |
| slot_executions | run_id, slot, mode, status(blue / green、on) | 追加(参照) |
| rapid_crosscheck_requests | run_id, status(rapid-crosscheck。元実行の特定元) | 追加(参照) |
| parallel_runs | run_id, job_id | 追加(参照) |

## ビジネスルール

- `--role blue / green` は元の slot mode が background のときだけリランする。foreground / off はリランせずエラー終了(条件「リラン事前検証」)
- 元の実行が RUNNING または中止未確認ならリランせずエラー終了し、中止を促す
- `--role rapid-crosscheck` は業務ジョブを再実行せず比較依頼だけを新規作成する(後続 UC)。元実行は管理 DB の依頼レコードで特定し、execution-spec.json を要求しない(数珠つなぎリランを成立させる。条件「リラン系譜の追跡」)
- foreground slot と確報クロスチェックはジョブスケジューラの正規ジョブを直接再実行する(条件「復旧手段の選択」)
- 検証段階では管理 DB・成果物を変更しない(CLR-004)

## ティア完了条件(BDD)

```gherkin
Feature: リラン対象を検証する - 実行監視・復旧ティア

  Scenario: background かつ FAILED の green は通過する
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json の green.mode が background で slot_executions(run_id, green) が mode=background status=FAILED である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を実行する
    Then 実行ログに `precheck passed ... role=green mode=background status=FAILED` が残り後続処理へ進む

  Scenario: off の slot は拒否する
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json に slots.blue 節が無く slot_executions に blue の行が無い
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role blue` を実行する
    Then 終了コード 3 で stderr の 1 行目が `error: source run is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=blue mode=off status=-` である

  Scenario: rapid-crosscheck は execution-spec.json が無い run でも依頼レコードだけで通過する
    Given RAPID_CROSSCHECK_MODE=on で facade/20260830T130000Z-JOB001-a1b2c3d4/ ディレクトリが存在せず rapid_crosscheck_requests に run_id=20260830T130000Z-JOB001-a1b2c3d4 status=FAILED がある
    When `background-rerun.sh --source-run-id 20260830T130000Z-JOB001-a1b2c3d4 --role rapid-crosscheck` を実行する
    Then 実行ログに `precheck passed source_run_id=20260830T130000Z-JOB001-a1b2c3d4 role=rapid-crosscheck` が残り後続処理へ進む

  Scenario: CLAIMED の速報比較依頼は拒否する
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e status=CLAIMED がある
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を実行する
    Then 終了コード 3 で stderr に `error: source request is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck status=CLAIMED` と `hint: request is still queued; wait for the worker` が出る

  Scenario: off の rapid-crosscheck は管理 DB 接続前に終了コード 3
    Given RAPID_CROSSCHECK_MODE=off である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を実行する
    Then 終了コード 3 で stderr の 1 行目が `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck` で、hint 行は無い

  Scenario: --role 欠落は終了コード 2
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e` を実行する
    Then 終了コード 2 で stderr に `error: option required option=--role` が出る

  Scenario: execution-spec.json が壊れている場合は終了コード 6
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json が存在するが JSON として不正である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 6 で stderr に `error: execution-spec is not readable run_id=20260830T113000Z-JOB001-3f9a1c2e path: /var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json` が出る
```
