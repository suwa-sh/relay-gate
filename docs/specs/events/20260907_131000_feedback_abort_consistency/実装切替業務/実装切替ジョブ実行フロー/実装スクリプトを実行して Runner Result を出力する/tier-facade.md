# 実装スクリプトを実行して Runner Result を出力する - facade / slot runner ティア仕様

## 変更概要

slot runner の実行フェーズ: usecase(SSH またはローカル実行 → 3 ファイル公開 → 状態導出 → (off 以外) slot_executions 更新 → (off 以外かつリラン由来 run) parallel_runs COMPLETED)、domain(状態導出規則: exitcode.txt / aborted.txt → 状態)、repository(Runner Result の原子的公開、execution-spec 読み込み、slot_executions / parallel_runs 更新)、gateway(SSH アダプタ、ファイルシステムアダプタ、RDB アダプタ)を新規実装する。完了通知の送信(gateway `completed_notifier`)は UC「速報クロスチェック runner へ完了通知を送信する」で定義する。

## コマンド契約

### $BLUE_RUNNER / $GREEN_RUNNER(runner IF。実行フェーズ)

- **書式**: `<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] -- [PARAM...]`
- **アクセス権**: 内部呼び出し(facade.sh / background-rerun.sh)。実行ユーザーは facade と同じ OS ユーザー。SSH 先の認証は SSH 鍵(CTP-002)

#### 引数・オプション(本フェーズで使う項目)

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --run-id / --role | string / enum | Yes | なし | 成果物ディレクトリ `facade/<run_id>/<role>/` |
| --mode | enum | Yes | なし | 実行方法は同じ。実行ログと slot_executions の `mode` に記録 |
| --execution-spec | string | No | なし | 指定時: ジョブマップを読まず、このファイルの `slots.<role>` の host / user / script / work_dir / fixed_params と run 単位の `params` で起動。未指定時: 前フェーズの解決結果 |
| -- PARAM... | string[] | No | 0 個 | 通常起動で使う。復元起動(`--execution-spec`)では spec の run 単位キー `params` を使い、`--` 以降に PARAM があれば受け付けない(exitcode.txt=2、stderr.log `error: params are not allowed with --execution-spec run_id=... role=...`。契約 `shared_rules.argument_concatenation.execution_spec`) |

- **stdin**: なし(SSH は `-n` で stdin を閉じる(契約 external_interfaces SSH: `ssh -n {user}@{host} 'cd {work_dir} && ...'`))
- **環境変数**(facade.sh / background-rerun.sh が feature-flag.env を読んで渡す。runner は feature-flag.env を読まない): 既存 4 つ `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE`(foreground / background / off。全 UC 共通)に加え、RAPID_CROSSCHECK_MODE が off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体。未設定・実行不可は実装起動前の設定検証で exitcode.txt=2(stderr.log `error: option required option=RAPID_CROSSCHECK_RUNNER` / `error: file not executable key=RAPID_CROSSCHECK_RUNNER path=...`。契約 runner IF exit_codes 2)。起動時に起動できなかった場合だけ完了通知失敗 = 条件「完了通知失敗の扱い」(実行ログ WARN、exit_code=127))、通常起動では自 slot の `BLUE_IMPL` / `GREEN_IMPL`(保存フェーズで使用)

#### 読み込む設定(管理 DB 接続。RAPID_CROSSCHECK_MODE が off 以外のときのみ)

| キー | 所在 | 必須 | 検証 |
|---|---|---|---|
| RAPID_DB_CONN_REF | `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`(情報「速報クロスチェック設定」。値は参照名のみ) | off 以外のとき Yes | ファイル不在・キー欠落は実装を起動せず exitcode.txt=2、stderr.log に `error: config file not found path: <path>` または `error: option required option=RAPID_DB_CONN_REF path: <path>`(3 ファイルは揃える)。off では読まない(契約 `config_files.rapid-crosscheck.env`) |

## 出力契約

- **stdout / stderr(プロセス)**: 出さない。実装の出力は成果物ファイルへ
- **成果物**(`facade/<run_id>/<role>/`):

| ファイル | 出力タイミング | 内容 |
|---|---|---|
| started-at.txt | SSH 実行の直前 | UTC ISO 8601 秒精度 Z 付き 1 行(Runner Result Contract。中身だけは UTC のまま。実行ログ・管理 DB・stdout に載せるときはローカルへ変換する) |
| stdout.log | 実行終了後(mv) | 実装の標準出力そのまま |
| stderr.log | 実行終了後(mv) | 実装の標準エラーそのまま。SSH 失敗時は末尾に `error: ssh failed host=... user=... exit_code=6` |
| exitcode.txt | 最後(mv) | 数値 1 行(改行 1 つ)。runner の終了コードと一致 |
| aborted.txt | runner は書かない | abort-blue / abort-green が中止時のみ生成(中止日時 1 行。UTC ISO 8601 秒精度 Z 付き)。状態導出規則で exitcode.txt が無いときの ABORTED 判定に使う。runner は削除も上書きもしない |

- **状態導出規則**(条件「slot 実行の状態導出規則」。runner・abort・background-rerun・hang-detector で共通): exitcode.txt があれば 0 = SUCCEEDED / 非 0 = FAILED。無く aborted.txt があれば ABORTED。どちらも無ければ RUNNING。両方あれば exitcode.txt を優先する(中止後に実装が終了した場合)
- **実行方式**: `slots.<role>.host` / `user` が非 null なら SSH(`ssh -n user@host 'cd work_dir && script args...'`)。両方 null(ジョブマップに host / user 列が無い・空)ならローカル実行: runner のプロセスユーザーで `cd work_dir && script args...` を直接起動する(stdin は `/dev/null`)。stdout / stderr / 終了コードの扱いと 3 ファイルは SSH と同じ
- **終了コード**: exitcode.txt の値をそのまま返す(実装の終了コード。SSH 接続失敗は 6。仮採用: ui-design.md の実行エラーに揃え、ssh の 255 は読み替える)。relay-gate の 4 分類は実装の終了コードには適用しない。例外: 3 ファイルを揃えられない書き込み失敗は 6。実装起動前の設定検証エラー(復元起動の spec 欠落・PARAM 併用・二重起動 / off 以外で rapid-crosscheck.env 不在・RAPID_DB_CONN_REF 欠落 / off 以外で RAPID_CROSSCHECK_RUNNER 未設定・実行不可)は 2(契約 runner IF exit_codes 2)

## UC ロジック

- **バリデーション**: 復元起動時は `slots.<role>` の必須フィールド(mode / host / user / script / work_dir / fixed_params。host / user はキーが存在し値は null 可。片方だけ null は不正)と run 単位の `params` を検証し、欠落は exitcode.txt=2 と stderr.log `error: execution-spec invalid path=... role=green missing=host` で終了。復元起動で `--` 以降に PARAM が 1 つでもあれば exitcode.txt=2 と stderr.log `error: params are not allowed with --execution-spec run_id=... role=...` で終了する(実装は起動しない)。RAPID_CROSSCHECK_MODE が off 以外のとき環境変数 `RAPID_CROSSCHECK_RUNNER` が未設定・実行不可なら実装を起動せず exitcode.txt=2 と stderr.log `error: option required option=RAPID_CROSSCHECK_RUNNER` / `error: file not executable key=RAPID_CROSSCHECK_RUNNER path=...` で終了する(契約 runner IF exit_codes 2)
- **確認プロンプト**: なし
- **冪等性**: 同じ run_id / role の成果物が既に確定(exitcode.txt あり)していれば実装を再実行せず、実行ログに WARN を出して既存の exitcode.txt の値で終了する(二重起動の防止。仮採用)。exitcode.txt が無く aborted.txt がある(中止済み)場合も実装を再実行せず、実行ログに `WARN slot already aborted run_id=... role=...` を出して終了コード 6(リランは background-rerun.sh で新 run_id にて行う)。started-at.txt だけがある(実行中または前回クラッシュ)場合、通常起動では上書きして再実行する(仮採用: 同一 run_id の再起動は運用上想定しないため保守的に再実行)。`--execution-spec` 指定の復元起動では二重起動とみなし exitcode.txt=2 と stderr.log `error: restored run already started run_id=... role=...` で終了する(契約 runner IF の idempotency / exit_codes 2)
- **エラーハンドリング**:
  - SSH 接続失敗(6)/ 実装の非 0: FAILED。3 ファイルを揃え、終了コードをそのまま返す
  - 3 ファイルの書き込み失敗: 実行ログに ERROR、終了コード 6。exitcode.txt が無い状態は hang-detector が上限超過でハング疑いとして拾う
  - slot_executions UPDATE 失敗(off 以外): 成果物は確定済みなので実行ログに ERROR を残し、完了通知は試みる。runner の終了コードは exitcode.txt の値を維持する(DB 失敗で業務結果を変えない)
  - slot_executions 終端 UPDATE の更新件数 0(off 以外。該当行が無い / 既に RUNNING でない。中止後に実装が終了し管理 DB が ABORTED の場合を含む): 実行ログに `WARN management db not updated run_id=... role=...`(契約 runner IF idempotency の文言。abort-blue / abort-green と同文。ERROR ではない)を残し、INSERT はしない(行の作成主体は facade / background-rerun。runner 起動前に INSERT するため通常は発生しない)。終了コード(exitcode.txt)は変えず、完了通知は試みる
  - リラン由来 run の parallel_runs COMPLETED UPDATE(off 以外。execution-spec.json の `parent_run_id` が非 null かつ自 slot が background): slot_executions 更新の後に `UPDATE parallel_runs SET status='COMPLETED', completed_at=now WHERE run_id=? AND status='RUNNING'`。失敗・0 件は実行ログに `ERROR management db update failed table=parallel_runs run_id=...` / `WARN management db not updated table=parallel_runs run_id=...` を残し、終了コードは変えない。通常起動(parent_run_id=null)では行わない(facade の中継 UC が担う)
  - 完了通知の送信失敗(off 以外): 条件「完了通知失敗の扱い」。実行ログに `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=...` を残し、Runner Result と終了コードは変えない(詳細は UC「速報クロスチェック runner へ完了通知を送信する」)
- **クラッシュ耐性**:
  - runner が SSH 実行中に落ちた場合: `.tmp` だけが残り exitcode.txt が無い。hang-detector が経過時間で判定。リモート側の実装プロセスは残る可能性がある(適用側の SSH 設定 / 実装側の責務)
  - `mv` の順序: stdout.log → stderr.log → exitcode.txt。exitcode.txt の存在で「3 ファイル完備」を判定できる
  - foreground の runner が落ちた場合: facade の `wait` は runner の異常終了コードを得る。exitcode.txt が無いので facade は中継できず終了コード 6(UC「foreground slot の結果をジョブスケジューラへ中継する」)
- **実行ログ**: SSH 実行は `INFO ssh exec started run_id=... role=green host=host-green-01 user=batch work_dir=/var/app/work script=/opt/app/bin/job001.sh` / `INFO ssh exec finished run_id=... role=green exit_code=0`。ローカル実行は同形で `INFO local exec started run_id=... role=... work_dir=... script=...` / `INFO local exec finished run_id=... role=... exit_code=N`(契約 slot runner IF 節の形式)。続けて `runner result published run_id=... role=green exit_code=0 status=SUCCEEDED` / `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=...`(リラン由来 run のみ)
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する

## 設定契約

- SSH 接続方法(鍵・ポート・踏み台・ホスト別名)は適用側の SSH 設定(実行ユーザーの `~/.ssh/config`)と runner 実体に閉じ込める。`credential_ref` は SSH 設定の Host 別名または鍵の参照名として runner 実体が解釈する(仮採用)
- relay-gate が定めるのは runner IF と Runner Result Contract のみ

## データモデル変更

### slot_executions(RAPID_CROSSCHECK_MODE が off 以外のみ。条件付き UPDATE(WHERE status='RUNNING')で一度だけ終端値を書く列。abort 後に exitcode.txt を公開した経路だけファイル正本の導出値と一致せず ABORTED のまま残る。正本: rdb-schema.yaml slot_executions.status / 契約 shared_rules.exitcode_to_status.slot_execution)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING → SUCCEEDED / FAILED(条件付き UPDATE。ファイル正本の状態導出規則と同じ値) | 追加 |
| completed_at | datetime | SUCCEEDED / FAILED / ABORTED へ遷移した日時(ローカル時刻。確定公開時に設定) | 追加 |
| exit_code | integer | exitcode.txt の値 | 追加 |

### parallel_runs(RAPID_CROSSCHECK_MODE が off 以外、かつ execution-spec.json の parent_run_id が非 null の background slot のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING → COMPLETED(条件付き UPDATE。background slot リラン由来 run の終端) | 追加 |
| completed_at | datetime | slot 終端日時(ローカル時刻) | 追加 |

### ファイル(出力)

上記「出力契約」の 4 ファイル。変更種別はすべて「追加」。

## ビジネスルール

- 実行終了時に stdout.log / stderr.log / exitcode.txt を揃える。exitcode.txt は数値 1 行で runner の終了コードと一致する。SSH 失敗・起動失敗でも 3 ファイルを出力する。0 → SUCCEEDED、非 0 → FAILED(条件: Runner Result 完備条件)
- slot 実行の状態はファイル正本から導出する。exitcode.txt が無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING(条件: slot 実行の状態導出規則)。管理 DB slot_executions.status は条件付き UPDATE(WHERE status='RUNNING')で一度だけ終端値を書き、abort 後に実装が走り切って exitcode.txt を公開した経路だけ導出値(exitcode.txt 優先)と一致せず ABORTED のまま残る(再同期しない。正本: rdb-schema.yaml slot_executions.status)
- RAPID_CROSSCHECK_MODE が off 以外のときだけ管理 DB を更新し完了通知を送る。off では 3 ファイルだけで完結する(条件: 速報クロスチェック有効判定)
- background slot リラン由来 run は slot の終端時に runner が parallel_run を COMPLETED にする(状態: 並行稼働実行 RUNNING → COMPLETED)
- 一時ファイル → リネーム。確定名の存在で完了を判定(条件: 成果物公開判定)
- 引数は固定引数 + PARAM の順序を維持し、各引数の空白・カンマを保つ(条件: 引数連結規則)
- SSH・OS・プロトコルの差異は runner 実体に閉じ込める(条件: 実装固有事項の runner への閉じ込め)
- 復元起動は最新ジョブマップを再解決しない(条件: リランの実行設定復元)

## ティア完了条件(BDD)

```gherkin
Feature: 実装スクリプトを実行して Runner Result を出力する - facade / slot runner ティア

  Scenario: runner は SSH 経由で実装を実行し 3 ファイルを exitcode.txt を最後に公開する
    Given ローカルの sshd(または ssh をスタブする PATH)で host=localhost user=<現在ユーザー> script=<stdout に "done" を出し終了コード 0 のスクリプト> が実行できる
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 0 で終了し、green/ に started-at.txt stdout.log stderr.log exitcode.txt が揃う
    And stdout.log は "done"、exitcode.txt は "0" の 1 行、.tmp ファイルは残っていない
    And 実行ログの "ssh exec finished run_id=20260830T113000-JOB001-3f9a1c2e role=green exit_code=0" は "runner result published" より前に出る

  Scenario: runner は SSH 接続失敗で exitcode.txt=6 と原因入り stderr.log を出す
    Given host=127.0.0.1 port=9(接続拒否)を解決するジョブマップがある
    When `<runner> ... --role green --mode background` を実行する
    Then 終了コード 6 で終了し、exitcode.txt は "6"、stderr.log は "error: ssh failed host=127.0.0.1 user=<user> exit_code=6" を含む

  Scenario: runner は空白を含む引数を 1 引数として SSH コマンドに渡す
    Given fixed_params=["p2 p3"] で PARAM が a である
    And 実装スクリプトは "$#" と "$1" を stdout に出す
    When runner を実行する
    Then stdout.log に "2" と "p2 p3" が含まれる

  Scenario: runner は --execution-spec 指定時にジョブマップを読まない
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv が存在しない
    And facade/20260830T150000-JOB001-9b8c7d6e/execution-spec.json の slots.green が host=localhost script=<スクリプト> を持ち run 単位の params が ["x"] である
    When `<runner> --run-id 20260830T150000-JOB001-9b8c7d6e --job-id JOB001 --role green --mode background --execution-spec <そのパス>` を実行する
    Then 終了コード 0 で終了し、実行ログに "job map" を含む行は無い

  Scenario: runner は --execution-spec 指定時に PARAM の併用を終了コード 2 で拒否する
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json に slots.green と params=["20260830"] がある
    When `$GREEN_RUNNER --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background --execution-spec facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json -- 20260831` を実行する
    Then exitcode.txt は 2 で、stderr.log に "error: params are not allowed with --execution-spec run_id=20260830T113000-JOB001-3f9a1c2e role=green" が出る
    And SSH コマンドは実行されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=background で slot_executions を RUNNING から SUCCEEDED に更新する
    Given 管理 DB の slot_executions に run_id slot=green status=RUNNING の行がある
    And 環境変数 RAPID_CROSSCHECK_MODE=background で runner を起動する
    When 実装が終了コード 0 で終了する
    Then slot_executions の該当行は status=SUCCEEDED exit_code=0 で completed_at が設定されている

  Scenario: runner は slot_executions の更新件数が 0 でも exitcode.txt の値で終了する
    Given 管理 DB の slot_executions に run_id slot=green の行が無い
    And 環境変数 RAPID_CROSSCHECK_MODE=background で runner を起動する
    When 実装が終了コード 0 で終了する
    Then 終了コード 0 で終了し、実行ログに "WARN management db not updated run_id=<run_id> role=green" が出る
    And slot_executions に行は作成されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=background で rapid-crosscheck.env が無ければ exitcode.txt=2 で終了する
    Given RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    And 環境変数 RAPID_CROSSCHECK_MODE=background で runner を起動する
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、exitcode.txt は "2"、stderr.log に "error: config file not found path: <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env" が出る
    And SSH コマンドは実行されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=off で RDB クライアントを呼ばない
    Given RDB クライアント CLI を呼び出し記録用スタブに置き換えている
    And 環境変数 RAPID_CROSSCHECK_MODE=off で runner を起動する(RAPID_CROSSCHECK_RUNNER は未設定)
    When 実装が終了する
    Then RDB スタブの呼び出し記録は無く、3 ファイルは揃っており、完了通知は送られない

  Scenario: runner は host / user が null の slot を SSH せずローカル実行する
    Given execution-spec.json の slots.blue が host=null user=null work_dir=<一時ディレクトリ> script=<pwd と id -un を stdout に出すスクリプト> である
    And PATH 上の ssh を呼び出し記録用スタブに置き換えている
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground` を実行する
    Then 終了コード 0 で終了し、ssh スタブの呼び出し記録は無い
    And stdout.log に <一時ディレクトリ> と runner のプロセスユーザー名が含まれ、実行ログに "INFO local exec started run_id=20260830T113000-JOB001-3f9a1c2e role=blue work_dir=<一時ディレクトリ> script=<スクリプト>" と "INFO local exec finished run_id=20260830T113000-JOB001-3f9a1c2e role=blue exit_code=0" が出る

  Scenario: judge_slot_status はファイル正本から状態を導出する
    Given 成果物ディレクトリの組合せ (exitcode.txt=0) / (exitcode.txt=4) / (aborted.txt のみ) / (どちらも無し) / (exitcode.txt=0 と aborted.txt の両方) を用意する
    When 状態導出関数をそれぞれに呼ぶ
    Then 結果は順に SUCCEEDED / FAILED / ABORTED / RUNNING / SUCCEEDED である

  Scenario: runner はリラン由来 run の background slot 終端で parallel_runs を COMPLETED にする
    Given 管理 DB の parallel_runs に run_id=20260830T150000-JOB001-9b8c7d6e parent_run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING の行と slot_executions の slot=green status=RUNNING の行がある
    And facade/20260830T150000-JOB001-9b8c7d6e/execution-spec.json の parent_run_id が非 null で slots.green.mode が background である
    And 環境変数 RAPID_CROSSCHECK_MODE=background で runner を --execution-spec 付きで起動する
    When 実装が終了コード 0 で終了する
    Then slot_executions の該当行は status=SUCCEEDED、parallel_runs の該当行は status=COMPLETED で completed_at が設定されている
    And 実行ログに "parallel_run status changed from=RUNNING to=COMPLETED run_id=20260830T150000-JOB001-9b8c7d6e" が出る

  Scenario: runner は通常起動(parent_run_id=null)では parallel_runs を更新しない
    Given 管理 DB の parallel_runs に run_id parent_run_id=NULL status=RUNNING の行がある
    And 環境変数 RAPID_CROSSCHECK_MODE=background で runner を --mode background で起動する
    When 実装が終了コード 0 で終了する
    Then parallel_runs の該当行は status=RUNNING のままである(COMPLETED は facade の中継 UC が行う)
```
