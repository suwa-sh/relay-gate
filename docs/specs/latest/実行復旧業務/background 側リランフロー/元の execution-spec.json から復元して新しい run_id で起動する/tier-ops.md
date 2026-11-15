# 元の execution-spec.json から復元して新しい run_id で起動する - 実行監視・復旧ティア仕様

## 変更概要

`background-rerun.sh` の `--role blue / green` 通過後の処理を定義する。新 run_id 発行 → (off 以外)parallel_runs INSERT(STARTED)→ execution-spec.json の復元コピー → (off 以外)slot_executions INSERT(RUNNING、pid=NULL)→ slot runner 起動 → (off 以外)slot_executions UPDATE(pid)→ parallel_runs UPDATE(RUNNING)→ 終了コード 0。slot_executions の順序は facade.sh と同じ「起動前 INSERT → 起動後 pid UPDATE」(契約 facade.sh idempotency / runner IF idempotency)。最新ジョブマップの repository は呼ばない(LP-018)。feature-flag.env は background-rerun が読み、runner へは環境変数で渡す。feature-flag.env から読むキーの範囲、起動の前に検査すること・しないこと、検査の順、runner の起動失敗の扱いは、CLI 契約 `background-rerun.sh` の `feature_flag_reading` に従う(起動の前に runner の実体を検査せず、起動に失敗したら終了コード 6)。

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
- **stderr**: `error: runner failed to start run_id=... role=... runner=...`(`runner=` は解決後のパス)/ `error: artifact dir is not writable path: ...` / `error: management db insert failed ...`。feature-flag.env と rapid-crosscheck.env(RAPID_CROSSCHECK_MODE が off 以外のとき)の読み取りと検査の error 行(終了コード 2)は契約 `background-rerun.sh` の `feature_flag_reading.checks` の文言
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | runner を起動し管理レコードを RUNNING にした(runner の完了は待たない) |
  | 2 | 入力エラー | 引数不正(前段 UC)、feature-flag.env の読み取りと検査の違反、off 以外のときの rapid-crosscheck.env の読み取りと検査の違反(契約 `feature_flag_reading.checks`。事前検証より前。元の実行の状態を読まず、新しい成果物ディレクトリも管理 DB の行も作らない) |
  | 3 | 業務エラー | 事前検証 NG(前段 UC) |
  | 6 | 実行エラー | 成果物ディレクトリ作成・spec 保存失敗、runner 起動失敗、管理 DB INSERT 失敗(起動前)、run_id 発行の再試行上限超過。起動後の pid UPDATE / STARTED→RUNNING UPDATE 失敗は終了コードに反映しない(契約 background-rerun.sh idempotency) |

## UC ロジック

- **バリデーション**: 引数と事前検証は前段 UC で済み。feature-flag.env の読み取りと検査は、引数の検査の後・事前検証の前に行う(順は契約 `feature_flag_reading.order`)。`--role blue|green` で読むキーは、`RAPID_CROSSCHECK_MODE`、リラン対象 role の runner(`--role blue` なら `BLUE_RUNNER`、`--role green` なら `GREEN_RUNNER`)、off 以外のときの `RAPID_CROSSCHECK_RUNNER` だけで、検査するのは読むキーの値の有無と `RAPID_CROSSCHECK_MODE` の列挙まで(違反は 2。2 つ以上あるときは契約 `feature_flag_reading.first_violation` の順で最初の 1 つ)。runner / worker の実体(存在・実行権限・`--help` の応答)、読まないキー、未知キー、`FINAL_` で始まるキーは検査しない(契約 `feature_flag_reading.not_checked`)。`RAPID_CROSSCHECK_MODE` が off 以外のときは、feature-flag.env の検査の直後・事前検証の前に rapid-crosscheck.env を読み取って検査する(不在・読めない・`RAPID_DB_CONN_REF` の欠落は 2。契約 `feature_flag_reading.checks` の 6。BDD は UC「リラン対象を検証する」の tier-ops.md)。復元前に元 spec の必須キー(job_id / params / slots.{role}.host / user / script / work_dir / fixed_params / hang_detect_limit_minutes / impl_version。host / user は null 可)の存在を確認し、欠落は 6(`error: execution-spec is not readable ... missing=...`)
- **確認プロンプト**: なし
- **処理順序(usecase。「off 以外」は RAPID_CROSSCHECK_MODE が foreground / background のとき)**:
  1. 新 run_id を発行(`facade/<run_id>/` が存在すれば乱数を取り直す。最大 3 回。超過は 6)。新 run ディレクトリは `$RELAY_GATE_ARTIFACT_ROOT/facade/` 直下に run_id 形式の名前で作る。成果物ルート直下の `hang-detector-notified/`(通知済みの印)と `housekeep-pending/`(削除待ち)は読まず、書かず、run として扱わない
  2. off 以外: `parallel_runs` INSERT(run_id, parent_run_id=source_run_id, job_id, parameters=元の parameters, execution_spec_uri=新 spec パス, status=STARTED, requested_at=now)
  3. `facade/<run_id>/` と `facade/<run_id>/<role>/` を作成。元 spec を読み `run_id` / `parent_run_id` / `restored_at` を書き換えて(C1) `execution-spec.json.tmp` に書き `mv` で確定(既存があれば上書きしない → 6)
  4. off 以外: runner 起動「前」に `slot_executions` INSERT(run_id, slot=role, mode=background, pid=NULL, artifact_dir, status=RUNNING, started_at=now)。即時に終了する runner の終端 UPDATE(`WHERE status='RUNNING'`)が INSERT より先に走って 0 件になる競合を防ぐ(facade.sh と同じ規則。round-1 F-004)。INSERT 失敗は runner を起動せず 6
  5. runner を非同期起動し PID を取得する。起動するのは feature-flag.env のリラン対象 role の runner の解決後のパス。起動の失敗(6)に当たるのは、契約 `feature_flag_reading.launch_failure` の定義のとおり、解決後のパスの runner を OS が実行できなかったときだけ(パスに何も無い、ディレクトリなど通常ファイルでない、実行権限が無い、の 3 つ)。runner が動き出した後に runner 自身が終了した場合(すぐに非 0 で終わった場合を含む)は起動の失敗に数えず、runner の終了を待たずに手順 6 以降へ進んで 0 で終わる(結果は runner 自身の Runner Result に残る)。起動の失敗の error 行・残すものは契約 `feature_flag_reading.launch_failure` と同じ内容。環境変数は「内部呼び出し」の項のとおり(off 以外は `RAPID_CROSSCHECK_RUNNER` を含む)。起動に失敗して runner 自身が Runner Result を書けない場合は、**background-rerun の gateway(runner 起動アダプタ)が** `facade/<run_id>/<role>/` に started-at.txt / 空の stdout.log / 失敗理由の stderr.log(`error: runner failed to start ...`)/ `exitcode.txt=6` を一時ファイル → mv で書く(hang-detector は非 0 として background-exec-error を通知する)。runner が起動して自身で書いた場合は上書きしない。off 以外のとき手順 4 の行を `UPDATE slot_executions SET status='FAILED', completed_at=now WHERE run_id=? AND slot=? AND status='RUNNING'` でベストエフォートに閉じる(UPDATE 失敗は実行ログ ERROR のみ。終了コード 6 は不変)
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
- **runner へ引き継ぐ環境変数**: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE` の 4 つ(background-rerun が feature-flag.env から解決済みの実効値)に加え、RAPID_CROSSCHECK_MODE が off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)。`BLUE_IMPL` / `GREEN_IMPL` は渡さない(復元起動では impl_version を spec から読む)。`RELAY_GATE_NOW` は設定時のみ追加で引き継ぐ(値を変えない)。ジョブマップの場所(`BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV`)は feature-flag.env から読まず、runner へも渡さない(復元起動の runner はジョブマップを読まない。契約 `config_files.feature-flag.env.job_map_location`)。facade.sh の通常起動と同じ規則(契約 facade.sh notes / runner IF environment。通常起動だけが BLUE_IMPL / GREEN_IMPL とジョブマップの場所を渡す)
- **feature-flag.env**(background-rerun が読む。runner は読まない。読むキーの範囲と検査の正本は契約 `background-rerun.sh` の `feature_flag_reading`): `RAPID_CROSSCHECK_MODE`(管理 DB 記録の有無)/ リラン対象 role の runner(`--role blue` なら `BLUE_RUNNER`、`--role green` なら `GREEN_RUNNER`。起動する runner 実体)/ `RAPID_CROSSCHECK_RUNNER`(off 以外のとき runner へ渡す)。これ以外のキー(リラン対象でない slot の runner、`RAPID_CROSSCHECK_WORKER` など)は使わず、値を取り込まない。読んだ runner のキー(リラン対象 role の runner と `RAPID_CROSSCHECK_RUNNER`)の値が相対パスのときは、`$RELAY_GATE_CONFIG_DIR/feature-flag.env` のあるディレクトリを基準に解決し(プロセスの作業ディレクトリは基準にしない)、runner の起動・runner への受け渡し・`runner=` の表示に解決後のパスを使う(CLI 契約 `config_files.feature-flag.env.runner_path_resolution`)。解決後のパスの実体は起動の前に検査しない(割り当てられた実体が標準の slot runner か自作の runner かも区別しない)。off 以外のとき `rapid-crosscheck.env` の `RAPID_DB_CONN_REF` で管理 DB に接続する(rapid-crosscheck.env の不在・`RAPID_DB_CONN_REF` の欠落は、feature-flag.env の検査の直後・事前検証の前に終了コード 2 で止まる。契約 `feature_flag_reading.checks` の 6 と `order`)

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

  Scenario: background-rerun_sh は相対パスの runner を設定ファイルのあるディレクトリ基準で起動する
    Given 事前検証を通過した source_run_id=20260830T113000-JOB001-3f9a1c2e role=green(RAPID_CROSSCHECK_MODE=background)がある
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、feature-flag.env の GREEN_RUNNER=./green-runner.sh、RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh、RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh である
    And RELAY_GATE_CONFIG_DIR のディレクトリに、起動引数と環境変数を記録する実行可能なスタブ green-runner.sh と、実行可能な rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh がある(feature flag の検証も通る設定の例。background-rerun.sh は検証を通る状態を要求しない)
    And 作業ディレクトリにするディレクトリ work(RELAY_GATE_CONFIG_DIR とは別)に、起動されたら記録を残す別の実行可能な green-runner.sh がある
    When work を作業ディレクトリにして `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 0 で、RELAY_GATE_CONFIG_DIR のスタブ green-runner.sh が 1 回起動され、work の green-runner.sh は起動されていない
    And スタブが記録した環境変数 RAPID_CROSSCHECK_RUNNER は "<RELAY_GATE_CONFIG_DIR>/./rapid-crosscheck-runner.sh" である(契約 config_files.feature-flag.env.runner_path_resolution)

  Scenario: runner 起動失敗時は起動前に INSERT した slot_executions を FAILED に閉じる
    Given RAPID_CROSSCHECK_MODE=background で GREEN_RUNNER が指すファイルに実行権限が無い
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 6 で stderr に `error: runner failed to start run_id=` で始まる 1 行が出る
    And slot_executions(新 run_id, green) は pid=NULL status=FAILED で completed_at が設定され、parallel_runs(新 run_id).status=STARTED のままである

  Scenario: 実体が無い runner は起動の前に検査せず起動を試みて終了コード 6 になる
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate で、事前検証を通過する source_run_id=20260830T113000-JOB001-3f9a1c2e role=green がある
    And /etc/relay-gate/feature-flag.env は RAPID_CROSSCHECK_MODE=background、GREEN_RUNNER=./missing-runner.sh、RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で、/etc/relay-gate/missing-runner.sh は存在しない
    And /etc/relay-gate/rapid-crosscheck.env は RAPID_DB_CONN_REF=mgmt-db を持ち、管理 DB が起動している
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コードは 6 で(2 ではない)、stderr は `error: runner failed to start run_id={新 run_id} role=green runner=/etc/relay-gate/./missing-runner.sh` の 1 行だけである({新 run_id} は `^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$` に一致)
    And /var/relay-gate/facade/{新 run_id}/execution-spec.json があり、/var/relay-gate/facade/{新 run_id}/green/ に started-at.txt、0 バイトの stdout.log、stderr と同じ error 行の stderr.log、中身が 6 の exitcode.txt がある
    And slot_executions(新 run_id, green) は pid=NULL status=FAILED、parallel_runs(新 run_id).status=STARTED のままである

  Scenario: 解決後のパスがディレクトリの runner は起動の失敗として終了コード 6 になる
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate で、事前検証を通過する source_run_id=20260830T113000-JOB001-3f9a1c2e role=green がある
    And /etc/relay-gate/feature-flag.env は RAPID_CROSSCHECK_MODE=off と GREEN_RUNNER=/opt/relay-gate/runners の 2 行で、/opt/relay-gate/runners はディレクトリである
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コードは 6 で、stderr は `error: runner failed to start run_id={新 run_id} role=green runner=/opt/relay-gate/runners` の 1 行だけである({新 run_id} は `^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$` に一致)
    And stdout は 0 行である(`pid=` の行は出ない)
    And /var/relay-gate/facade/{新 run_id}/execution-spec.json があり、/var/relay-gate/facade/{新 run_id}/green/ に started-at.txt、0 バイトの stdout.log、stderr と同じ error 行の stderr.log、中身が 6 の exitcode.txt がある

  Scenario: 動き出した runner がすぐ非 0 で終わっても起動の失敗に数えず終了コード 0 で終わる
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate で、事前検証を通過する source_run_id=20260830T113000-JOB001-3f9a1c2e role=green がある
    And /etc/relay-gate/feature-flag.env は RAPID_CROSSCHECK_MODE=off と GREEN_RUNNER=<スタブ runner> の 2 行である
    And スタブ runner は実行可能で、起動されるとすぐに /var/relay-gate/facade/<渡された --run-id>/green/ へ started-at.txt、0 バイトの stdout.log、"stub failed" の 1 行の stderr.log、中身が 2 の exitcode.txt を書いて終了コード 2 で終了する
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 0 で、stderr に `error: runner failed to start` で始まる行は出ず、stdout の 3 行目が `pid=` で始まり 6 行目が `run_id=` で始まる
    And スタブ runner の終了後、/var/relay-gate/facade/{新 run_id}/green/exitcode.txt の中身は 2、stderr.log は "stub failed" の 1 行のままである(background-rerun.sh は runner の書いた Runner Result を上書きしない)

  Scenario: リラン対象でない slot の runner と速報クロスチェック worker に不備があっても green のリランは成功する
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate で、事前検証を通過する source_run_id=20260830T113000-JOB001-3f9a1c2e role=green がある
    And /etc/relay-gate/feature-flag.env の行は次の 6 行だけである: RAPID_CROSSCHECK_MODE=background、GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh(起動引数と環境変数を記録する実行可能なスタブ)、RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh、BLUE_RUNNER=/opt/relay-gate/runners/no-such-runner.sh(実体は無い)、UNKNOWN_KEY=1、FINAL_POLL_LIMIT_SEC=60
    And RAPID_CROSSCHECK_WORKER / BLUE_MODE / GREEN_MODE / BLUE_IMPL / GREEN_IMPL のキーは無い
    And /etc/relay-gate/rapid-crosscheck.env は RAPID_DB_CONN_REF=mgmt-db を持ち、管理 DB が起動している
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 0 で stdout の 6 行目が `run_id=` で始まり、スタブ green-runner.sh が 1 回起動されている
    And stderr は 0 行である(`warn: unknown key` も `error: final crosscheck key is not allowed` も `error: file not executable` も `error: option required` も出ない)
    And スタブが記録した環境変数に BLUE_RUNNER / UNKNOWN_KEY / FINAL_POLL_LIMIT_SEC / GREEN_JOB_MAP_CSV は無い

  Scenario Outline: リラン対象 role の runner のキーが無い設定は元の実行の状態を読む前に終了コード 2 で止める
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate で、/var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/ ディレクトリは存在しない
    And /etc/relay-gate/feature-flag.env は、RAPID_CROSSCHECK_MODE=off と BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh の 2 行に、<line> を加えた内容である(「(行なし)」は何も加えない)
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 2 で stderr は `error: option required option=GREEN_RUNNER path: /etc/relay-gate/feature-flag.env` の 1 行だけである(`error: execution-spec not found` は出ない)
    And /var/relay-gate/facade/ の下に新しいディレクトリは作られず、runner は起動されない

    Examples:
      | line           | note         |
      | (行なし)     | キーが無い   |
      | GREEN_RUNNER=  | 値が空       |

  Scenario: 違反が 2 つある設定では RAPID_CROSSCHECK_MODE の違反だけを出す
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate で、/etc/relay-gate/feature-flag.env は RAPID_CROSSCHECK_MODE=maybe を持ち、GREEN_RUNNER と RAPID_CROSSCHECK_RUNNER のキーが無い
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 2 で stderr は `error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe` と `hint: use foreground, background or off` の 2 行だけである(`error: option required option=GREEN_RUNNER ...` は出ない。契約 background-rerun.sh の feature_flag_reading.first_violation)

  Scenario: 管理 DB INSERT 失敗は終了コード 6 で runner を起動しない
    Given RAPID_CROSSCHECK_MODE=background で管理 DB が接続を拒否する
    When `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green` を実行する
    Then 終了コード 6 で stderr に `error: management db insert failed` で始まる 1 行が出て、新しい成果物ディレクトリは作成されず runner も起動されない
```
