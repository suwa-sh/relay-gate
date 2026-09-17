# 元の execution-spec.json から復元して新しい run_id で起動する - 実行監視・復旧ティア仕様

## 変更概要

`background-rerun.sh` の `--role blue / green` 通過後の処理を定義する。新 run_id 発行 → (off 以外)parallel_runs INSERT(STARTED)→ execution-spec.json の復元コピー → (off 以外)slot_executions INSERT(RUNNING、pid=NULL)→ slot runner 起動 → (off 以外)slot_executions UPDATE(pid)→ parallel_runs UPDATE(RUNNING)→ 終了コード 0。slot_executions の順序は facade.sh と同じ「起動前 INSERT → 起動後 pid UPDATE」(契約 facade.sh idempotency / runner IF idempotency)。最新ジョブマップの repository は呼ばない(LP-018)。feature-flag.env は background-rerun が読み、runner へは環境変数で渡す。

## コマンド契約

### background-rerun.sh(UC「リラン対象を検証する」の契約を使う)

- **書式**: `background-rerun.sh --source-run-id <RUN_ID> --role blue|green`
- **アクセス権**: ジョブスケジューラの専用ジョブ / 運用者

#### 引数・オプション

UC「リラン対象を検証する」の tier-ops.md と同一。

- **stdin**: なし

### 内部呼び出し: slot runner(tier-facade の契約を使う)

`<$BLUE_RUNNER | $GREEN_RUNNER> --run-id <new_run_id> --job-id <job_id> --role blue|green --mode background --execution-spec <RELAY_GATE_ARTIFACT_ROOT>/facade/<new_run_id>/execution-spec.json`

- `--` 以降の PARAM は渡さない(元 spec の `params` に含まれる)
- 環境変数: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE`(background-rerun が feature-flag.env から解決した実効値)。RAPID_CROSSCHECK_MODE が off 以外なら `RAPID_CROSSCHECK_RUNNER` も渡す。`BLUE_IMPL` / `GREEN_IMPL` は渡さない(復元起動の runner は impl_version を spec から読む)
- 起動は非同期(バックグラウンドプロセス)。background-rerun は PID を取得したら待たない

## 出力契約

- **stdout**(固定順。最後の 2 行が追跡の起点):
  | 行順 | キー | 値 |
  |---|---|---|
  | 1 | `role` | blue / green |
  | 2 | `mode` | `background` |
  | 3 | `pid` | runner の PID |
  | 4 | `artifact_dir` | `key: value`。`$RELAY_GATE_ARTIFACT_ROOT/facade/<new_run_id>/<role>` |
  | 5 | `execution_spec` | `key: value`。新 execution-spec.json のパス |
  | 6 | `run_id` | 新 run_id |
  | 7 | `parent_run_id` | `--source-run-id` の値 |
- **stderr**: `error: runner failed to start run_id=... role=... runner=...` / `error: artifact dir is not writable path: ...` / `error: management db insert failed ...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | runner を起動し管理レコードを RUNNING にした(runner の完了は待たない) |
  | 3 | 業務エラー | 事前検証 NG(前段 UC) |
  | 6 | 実行エラー | 成果物ディレクトリ作成・spec 保存失敗、runner 起動失敗、管理 DB INSERT 失敗(起動前)、run_id 発行の再試行上限超過。起動後の pid UPDATE / STARTED→RUNNING UPDATE 失敗は終了コードに反映しない(契約 background-rerun.sh idempotency) |

## UC ロジック

- **バリデーション**: 前段 UC で済み。復元前に元 spec の必須キー(job_id / params / slots.{role}.host / user / script / work_dir / fixed_params / hang_detect_limit_minutes / impl_version。host / user は null 可)の存在を確認し、欠落は 6(`error: execution-spec is not readable ... missing=...`)
- **確認プロンプト**: なし
- **処理順序(usecase。「off 以外」は RAPID_CROSSCHECK_MODE が foreground / background のとき)**:
  1. 新 run_id を発行(`facade/<run_id>/` が存在すれば乱数を取り直す。最大 3 回。超過は 6)
  2. off 以外: `parallel_runs` INSERT(run_id, parent_run_id=source_run_id, job_id, parameters=元の parameters, execution_spec_uri=新 spec パス, status=STARTED, requested_at=now)
  3. `facade/<run_id>/` と `facade/<run_id>/<role>/` を作成。元 spec を読み `run_id` / `parent_run_id` / `restored_at` を書き換えて(C1) `execution-spec.json.tmp` に書き `mv` で確定(既存があれば上書きしない → 6)
  4. off 以外: runner 起動「前」に `slot_executions` INSERT(run_id, slot=role, mode=background, pid=NULL, artifact_dir, status=RUNNING, started_at=now)。即時に終了する runner の終端 UPDATE(`WHERE status='RUNNING'`)が INSERT より先に走って 0 件になる競合を防ぐ(facade.sh と同じ規則。round-1 F-004)。INSERT 失敗は runner を起動せず 6
  5. runner を非同期起動し PID を取得(起動不能・即時終了で exitcode.txt が非 0 なら 6)。環境変数は「内部呼び出し」の項のとおり(off 以外は `RAPID_CROSSCHECK_RUNNER` を含む)。runner 実体が起動できず(実行権限なし・実体なし等)runner 自身が Runner Result を書けない場合は、**background-rerun の gateway(runner 起動アダプタ)が** `facade/<run_id>/<role>/` に started-at.txt / 空の stdout.log / 失敗理由の stderr.log(`error: runner failed to start ...`)/ `exitcode.txt=6` を一時ファイル → mv で書く(hang-detector は非 0 として background-exec-error を通知する)。runner が起動して自身で書いた場合は上書きしない。off 以外のとき手順 4 の行を `UPDATE slot_executions SET status='FAILED', completed_at=now WHERE run_id=? AND slot=? AND status='RUNNING'` でベストエフォートに閉じる(UPDATE 失敗は実行ログ ERROR のみ。終了コード 6 は不変)
  6. off 以外: `UPDATE slot_executions SET pid=? WHERE run_id=? AND slot=?`(pid UPDATE 失敗は実行ログ `ERROR management db update failed table=slot_executions run_id=...` を残し、終了コードには反映しない。runner は既に起動している)
  7. off 以外: `parallel_runs` UPDATE `status='RUNNING' WHERE run_id=? AND status='STARTED'`(UPDATE 失敗は実行ログ `ERROR management db update failed table=parallel_runs run_id=...` を残し、終了コードには反映しない。runner は既に起動している)
  8. stdout を出して 0
- **冪等性**: 同じ `--source-run-id --role` を再実行すると別の新 run_id で新たにリランする(各リランは独立した run。parent_run_id は同じ元 run を指す)。同一 run_id の spec を二重に書かない(一度きり保存)
- **エラーハンドリング**: 手順 2 以降の失敗は 6(手順 6 の pid UPDATE 失敗と手順 7 の STARTED→RUNNING UPDATE 失敗を除く。いずれも runner 起動済みのため実行ログ `ERROR management db update failed table=... run_id=...` のみで終了コード 0)。エラーは 1 回だけ出す
- **クラッシュ耐性**:
  | 落ちた時点 | 残るもの | 再実行時の振る舞い |
  |---|---|---|
  | 手順 1〜2 の間 | なし | やり直し |
  | 手順 2 の後 | parallel_runs STARTED(spec なし) | STARTED のまま残る。run-lineage.sh に STARTED として現れる。再実行は別 run_id(仮採用: STARTED 孤児の掃除は手動運用) |
  | 手順 3 の後 | + execution-spec.json | 同上。runner は起動していない(started-at.txt なし) |
  | 手順 4 の後 | + slot_executions RUNNING(pid=NULL) | 管理レコードは STARTED。runner は起動していない(started-at.txt なし)。hang-detector は成果物走査で started-at.txt が無いため対象外。abort-{role}.sh は成果物ファイルから未起動(`status=-`)と判定し 3 で拒否する(slot_executions の RUNNING 行は残る。仮採用: STARTED 孤児と同じく掃除は手動運用) |
  | 手順 5 の後 | + runner 実行中(started-at.txt) | 管理レコードは STARTED、slot_executions は RUNNING(pid=NULL)。hang-detector は成果物走査で監視できる。runner の終端 UPDATE は行が存在するため成功する。abort-{role}.sh は成果物ファイルから RUNNING と判定して aborted.txt を書き、slot_executions と parallel_runs(STARTED → ABORTED)を併せて ABORTED にできる |
  | 手順 6〜7 の後 | 完全 | 正常 |
- **実行ログ**(CLP-008): `INFO rerun started operator={OS ユーザー} source_run_id=R1 role=green new_run_id=R2 pid=23456`、各 gateway 呼び出しの開始・終了・所要時間、`ERROR management db update failed table=slot_executions run_id=...`(手順 6 の pid UPDATE 失敗)/ `ERROR management db update failed table=parallel_runs run_id=...`(手順 7 の STARTED→RUNNING UPDATE 失敗。いずれも終了コードは変えない)。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する

## データモデル変更

### parallel_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK。新 run_id | 追加 |
| parent_run_id | string | `--source-run-id`(直前のリラン元) | 追加 |
| job_id | string | 元 spec の job_id | 追加 |
| parameters | text | 元 run の parameters(JSON。元 parallel_runs から複製。off 時や元行が無い場合は元 spec の params) | 追加 |
| execution_spec_uri | string | 新 execution-spec.json のパス | 追加 |
| status | string | STARTED → RUNNING | 追加 |
| requested_at | datetime | 作成日時 | 追加 |
| completed_at | datetime | NULL | 追加 |

### slot_executions

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK 1。新 run_id | 追加 |
| slot | string | PK 2。role | 追加 |
| mode | string | `background` 固定 | 追加 |
| pid | integer | INSERT 時は NULL(runner 起動前)。起動後に UPDATE で runner の PID を設定。起動失敗時は NULL のまま status=FAILED | 追加 |
| artifact_dir | string | 新成果物ディレクトリ | 追加 |
| status | string | `RUNNING`(起動失敗時はベストエフォートで `FAILED`) | 追加 |
| started_at | datetime | 起動日時(`RELAY_GATE_NOW` 設定時はその値) | 追加 |
| completed_at | datetime | 起動失敗時のベストエフォート更新のみ設定 | 追加 |

### execution-spec.json(ファイル)

| キー | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 新 run_id に置換 | 追加 |
| parent_run_id | string | 元 run_id(C1) | 追加 |
| restored_at | datetime | 復元日時(C1)。UTC ISO 8601 秒精度 Z 付き(execution-spec.json の中身は Runner Result Contract と同じく UTC のまま。例 `2026-08-30T12:45:00Z`。`RELAY_GATE_NOW` 設定時はその値をそのまま書く) | 追加 |
| その他すべて | — | 元 spec と同一(不変) | 追加 |

## 設定契約

- **環境変数**: `RELAY_GATE_CONFIG_DIR`(feature-flag.env / rapid-crosscheck.env の所在)/ `RELAY_GATE_ARTIFACT_ROOT`(`facade/<run_id>/` の親)/ `RELAY_GATE_LOG_DIR`(実行ログ)/ `RELAY_GATE_NOW`(テスト専用の現在時刻注入。契約 `environment_variables.RELAY_GATE_NOW`)
- **`RELAY_GATE_NOW` の適用先**: 新 run_id の時刻部(プロセスのローカルタイムゾーンへ変換した値。spec の例示は TZ=UTC 前提)、`restored_at`(UTC Z 付きのまま。ローカル変換しない)、`parallel_runs.requested_at`、`slot_executions.started_at`(日時はホストで生成して SQL にバインド値で渡す。RELAY_GATE_NOW 設定時はその変換値。conventions.datetime_generation)。未設定なら実時刻
- **runner へ引き継ぐ環境変数**: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE` の 4 つ(background-rerun が feature-flag.env から解決済みの実効値)に加え、RAPID_CROSSCHECK_MODE が off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)。`BLUE_IMPL` / `GREEN_IMPL` は渡さない(復元起動では impl_version を spec から読む)。`RELAY_GATE_NOW` は設定時のみ追加で引き継ぐ(値を変えない)。facade.sh の通常起動と同じ規則(契約 facade.sh notes / runner IF environment。通常起動だけが BLUE_IMPL / GREEN_IMPL を渡す)
- **feature-flag.env**(background-rerun が読む。runner は読まない): `RAPID_CROSSCHECK_MODE`(管理 DB 記録の有無)/ `BLUE_RUNNER` / `GREEN_RUNNER`(起動する runner 実体)/ `RAPID_CROSSCHECK_RUNNER`(off 以外のとき runner へ渡す)。off 以外のとき `rapid-crosscheck.env` の `RAPID_DB_CONN_REF` で管理 DB に接続する(不在は前段 UC の検証で終了)

## ビジネスルール

- 最新のジョブマップを再解決せず元の execution-spec.json から復元する(条件「リランの実行設定復元」、LP-018)
- 新 run の parent_run_id には直前のリラン元 run_id を設定する(条件「リラン系譜の追跡」)
- リランは常に新しい run_id を発行し、Runner Result を新しい成果物ディレクトリへ出力する(CTP-004、条件「Runner Result 完備条件」)
- execution-spec.json は一時ファイル → リネームで一度だけ作成する(条件「成果物公開判定」、LP-006 と同じ規則)
- RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(条件「速報クロスチェック有効判定」)。off でも aborted.txt で中止済みの元 run をリランできる(条件「slot 実行の状態導出規則」。前段 UC)
- リラン由来 run の parallel_run は background slot の終端時に runner が COMPLETED にする(状態「並行稼働実行」。他 UC)
- 認証情報は参照名のみ(元 spec に値が無いため復元でも入らない。条件「認証情報の非保存」)

## ティア完了条件(BDD)

```gherkin
Feature: 元の execution-spec.json から復元して新しい run_id で起動する - 実行監視・復旧ティア

  Scenario: 復元した spec で runner を起動し管理レコードを RUNNING にする
    Given 事前検証を通過した source_run_id=20260830T113000-JOB001-3f9a1c2e role=green(RAPID_CROSSCHECK_MODE=background)がある
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 0 で stdout の 6 行目が `run_id=` で始まり 7 行目が `parent_run_id=20260830T113000-JOB001-3f9a1c2e` である
    And parallel_runs(新 run_id).status=RUNNING かつ parent_run_id=20260830T113000-JOB001-3f9a1c2e、slot_executions(新 run_id, green).status=RUNNING mode=background で pid が stdout の `pid=` の値と一致する
    And 実行ログ上で slot_executions INSERT が runner 起動より前に記録されている
    And green runner のコマンドラインに `--mode background --execution-spec /var/relay-gate/facade/{新 run_id}/execution-spec.json` が含まれ `--` 以降の引数は無い
    And green runner の環境変数に RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE=background / RAPID_CROSSCHECK_RUNNER(feature-flag.env の値)があり、GREEN_IMPL は無い

  Scenario: RAPID_CROSSCHECK_MODE=off では runner に RAPID_CROSSCHECK_RUNNER を渡さず管理 DB にも触れない
    Given RAPID_CROSSCHECK_MODE=off で事前検証を通過した source_run_id=20260830T113000-JOB001-3f9a1c2e role=green がある
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 0 で green runner の環境変数に RAPID_CROSSCHECK_MODE=off があり RAPID_CROSSCHECK_RUNNER / GREEN_IMPL は無く、管理 DB への接続は行われない

  Scenario: 新 execution-spec.json は run_id / parent_run_id / restored_at 以外が元と同一
    Given 元 spec の job_id=JOB001 params=["20260830"] slots.green.host=app-host-01 user=batch work_dir=/opt/app fixed_params=["--mode","daily"] hang_detect_limit_minutes=60 map_version=v1 impl_version=v1.2.0 である
    When リランを実行する
    Then 新 spec の job_id=JOB001 params=["20260830"] slots.green.host=app-host-01 user=batch work_dir=/opt/app fixed_params=["--mode","daily"] hang_detect_limit_minutes=60 map_version=v1 impl_version=v1.2.0 かつ run_id が新 run_id、parent_run_id が元 run_id、restored_at が復元日時である(feature-flag.env の GREEN_IMPL が変わっていても新 spec の impl_version は元の値のまま)

  Scenario: 同じ元 run を 2 回リランすると別の run_id で 2 つの run ができる
    Given source_run_id=20260830T113000-JOB001-3f9a1c2e role=green のリランを 1 回実行し新 run_id R2 を得た(R2 は完了済み)
    When 再度 `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then R2 と異なる run_id R3 が発行され parallel_runs(R3).parent_run_id=20260830T113000-JOB001-3f9a1c2e である

  Scenario: runner 起動失敗時は起動前に INSERT した slot_executions を FAILED に閉じる
    Given RAPID_CROSSCHECK_MODE=background で GREEN_RUNNER が指すファイルに実行権限が無い
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 6 で stderr に `error: runner failed to start run_id=` で始まる 1 行が出る
    And slot_executions(新 run_id, green) は pid=NULL status=FAILED で completed_at が設定され、parallel_runs(新 run_id).status=STARTED のままである

  Scenario: 管理 DB INSERT 失敗は終了コード 6 で runner を起動しない
    Given RAPID_CROSSCHECK_MODE=background で管理 DB が接続を拒否する
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 6 で stderr に `error: management db insert failed` で始まる 1 行が出て、新しい成果物ディレクトリは作成されず runner も起動されない
```
