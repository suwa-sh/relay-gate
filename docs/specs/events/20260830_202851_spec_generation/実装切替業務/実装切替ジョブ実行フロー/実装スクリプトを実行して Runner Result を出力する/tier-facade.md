# 実装スクリプトを実行して Runner Result を出力する - facade / slot runner ティア仕様

## 変更概要

slot runner の実行フェーズ: usecase(SSH 実行 → 3 ファイル公開 → 状態判定 → (on) DB 更新)、domain(exitcode → 状態)、repository(Runner Result の原子的公開、execution-spec 読み込み、slot_executions 更新)、gateway(SSH アダプタ、ファイルシステムアダプタ、RDB アダプタ)を新規実装する。完了通知の送信(gateway `completed_notifier`)は UC「速報クロスチェック runner へ完了通知を送信する」で定義する。

## コマンド契約

### $BLUE_RUNNER / $GREEN_RUNNER(runner IF。実行フェーズ)

- **書式**: `<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] -- [PARAM...]`
- **アクセス権**: 内部呼び出し(facade.sh / background-rerun.sh)。実行ユーザーは facade と同じ OS ユーザー。SSH 先の認証は SSH 鍵(CTP-002)

#### 引数・オプション(本フェーズで使う項目)

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --run-id / --role | string / enum | Yes | なし | 成果物ディレクトリ `facade/<run_id>/<role>/` |
| --mode | enum | Yes | なし | 実行方法は同じ。実行ログと slot_executions の `mode` に記録 |
| --execution-spec | string | No | なし | 指定時: ジョブマップを読まず、このファイルの `slots.<role>` の host / exec_user / script_path / work_dir / fixed_args と run 単位の `params` で起動。未指定時: 前フェーズの解決結果 |
| -- PARAM... | string[] | No | 0 個 | 通常起動で使う。復元起動(`--execution-spec`)では spec の run 単位キー `params` を使い、`--` 以降に PARAM があれば受け付けない(exitcode.txt=2、stderr.log `error: params are not allowed with --execution-spec run_id=... role=...`。契約 `shared_rules.argument_concatenation.execution_spec`) |

- **stdin**: なし(SSH は `-n` で stdin を閉じる(契約 external_interfaces SSH: `ssh -n {exec_user}@{host} 'cd {work_dir} && ...'`))
- **環境変数**: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE` の 4 つ(facade / background-rerun から引き継ぐ。全 UC 共通)

#### 読み込む設定(管理 DB 接続。RAPID_CROSSCHECK_MODE=on のときのみ)

| キー | 所在 | 必須 | 検証 |
|---|---|---|---|
| RAPID_DB_CONN_REF | `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` | on のとき Yes | ファイル不在・キー欠落は実装を起動せず exitcode.txt=2、stderr.log に `error: config file not found path: <path>` または `error: option required option=RAPID_DB_CONN_REF path: <path>`(3 ファイルは揃える)。off では読まない(契約 `config_files.rapid-crosscheck.env`) |

## 出力契約

- **stdout / stderr(プロセス)**: 出さない。実装の出力は成果物ファイルへ
- **成果物**(`facade/<run_id>/<role>/`):

| ファイル | 出力タイミング | 内容 |
|---|---|---|
| started-at.txt | SSH 実行の直前 | UTC ISO 8601 秒精度 1 行 |
| stdout.log | 実行終了後(mv) | 実装の標準出力そのまま |
| stderr.log | 実行終了後(mv) | 実装の標準エラーそのまま。SSH 失敗時は末尾に `error: ssh failed host=... user=... exit_code=6` |
| exitcode.txt | 最後(mv) | 数値 1 行(改行 1 つ)。runner の終了コードと一致 |

- **終了コード**: exitcode.txt の値をそのまま返す(実装の終了コード。SSH 接続失敗は 6。仮採用: ui-design.md の実行エラーに揃え、ssh の 255 は読み替える)。relay-gate の 4 分類は実装の終了コードには適用しない。例外: 3 ファイルを揃えられない書き込み失敗は 6

## UC ロジック

- **バリデーション**: 復元起動時は `slots.<role>` の必須フィールド(mode / host / exec_user / script_path / work_dir / fixed_args)と run 単位の `params` を検証し、欠落は exitcode.txt=2 と stderr.log `error: execution-spec invalid path=... role=green missing=host` で終了。復元起動で `--` 以降に PARAM が 1 つでもあれば exitcode.txt=2 と stderr.log `error: params are not allowed with --execution-spec run_id=... role=...` で終了する(実装は起動しない)
- **確認プロンプト**: なし
- **冪等性**: 同じ run_id / role の成果物が既に確定(exitcode.txt あり)していれば実装を再実行せず、実行ログに WARN を出して既存の exitcode.txt の値で終了する(二重起動の防止。仮採用)。started-at.txt だけがある(実行中または前回クラッシュ)場合、通常起動では上書きして再実行する(仮採用: 同一 run_id の再起動は運用上想定しないため保守的に再実行)。`--execution-spec` 指定の復元起動では二重起動とみなし exitcode.txt=2 と stderr.log `error: restored run already started run_id=... role=...` で終了する(契約 runner IF の idempotency / exit_codes 2)
- **エラーハンドリング**:
  - SSH 接続失敗(6)/ 実装の非 0: FAILED。3 ファイルを揃え、終了コードをそのまま返す
  - 3 ファイルの書き込み失敗: 実行ログに ERROR、終了コード 6。exitcode.txt が無い状態は hang-detector が上限超過でハング疑いとして拾う
  - slot_executions UPDATE 失敗(on): 成果物は確定済みなので実行ログに ERROR を残し、完了通知は試みる。runner の終了コードは exitcode.txt の値を維持する(DB 失敗で業務結果を変えない)
  - slot_executions UPDATE の更新件数 0(on。該当行が無い / 既に RUNNING でない): 実行ログに `ERROR slot_executions update affected 0 rows run_id=... role=...`(契約 runner IF idempotency の文言)を残し、INSERT はしない(行の作成主体は facade。facade は runner 起動前に INSERT するため通常は発生しない)。終了コード(exitcode.txt)は変えず、完了通知は試みる
- **クラッシュ耐性**:
  - runner が SSH 実行中に落ちた場合: `.tmp` だけが残り exitcode.txt が無い。hang-detector が経過時間で判定。リモート側の実装プロセスは残る可能性がある(適用側の SSH 設定 / 実装側の責務)
  - `mv` の順序: stdout.log → stderr.log → exitcode.txt。exitcode.txt の存在で「3 ファイル完備」を判定できる
  - foreground の runner が落ちた場合: facade の `wait` は runner の異常終了コードを得る。exitcode.txt が無いので facade は中継できず終了コード 6(UC「foreground slot の結果をジョブスケジューラへ中継する」)
- **実行ログ**: `ssh started host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work argc=3` / `ssh finished exit_code=0 duration_ms=4321` / `runner result published run_id=... role=green exit_code=0 status=SUCCEEDED`
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## 設定契約

- SSH 接続方法(鍵・ポート・踏み台・ホスト別名)は適用側の SSH 設定(実行ユーザーの `~/.ssh/config`)と runner 実体に閉じ込める。`credential_ref` は SSH 設定の Host 別名または鍵の参照名として runner 実体が解釈する(仮採用)
- relay-gate が定めるのは runner IF と Runner Result Contract のみ

## データモデル変更

### slot_executions(on のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING → SUCCEEDED / FAILED(条件付き UPDATE) | 追加 |
| completed_at | datetime | SUCCEEDED / FAILED / ABORTED へ遷移した日時(UTC。確定公開時に設定) | 追加 |
| exit_code | integer | exitcode.txt の値 | 追加 |

### ファイル(出力)

上記「出力契約」の 4 ファイル。変更種別はすべて「追加」。

## ビジネスルール

- 実行終了時に stdout.log / stderr.log / exitcode.txt を揃える。exitcode.txt は数値 1 行で runner の終了コードと一致する。SSH 失敗・起動失敗でも 3 ファイルを出力する。0 → SUCCEEDED、非 0 → FAILED(条件: Runner Result 完備条件)
- 一時ファイル → リネーム。確定名の存在で完了を判定(条件: 成果物公開判定)
- 引数は固定引数 + PARAM の順序を維持し、各引数の空白・カンマを保つ(条件: 引数連結規則)
- SSH・OS・プロトコルの差異は runner 実体に閉じ込める(条件: 実装固有事項の runner への閉じ込め)
- 復元起動は最新ジョブマップを再解決しない(条件: リランの実行設定復元)

## ティア完了条件(BDD)

```gherkin
Feature: 実装スクリプトを実行して Runner Result を出力する - facade / slot runner ティア

  Scenario: runner は SSH 経由で実装を実行し 3 ファイルを exitcode.txt を最後に公開する
    Given ローカルの sshd(または ssh をスタブする PATH)で host=localhost exec_user=<現在ユーザー> script_path=<stdout に "done" を出し終了コード 0 のスクリプト> が実行できる
    When `<runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 0 で終了し、green/ に started-at.txt stdout.log stderr.log exitcode.txt が揃う
    And stdout.log は "done"、exitcode.txt は "0" の 1 行、.tmp ファイルは残っていない
    And 実行ログの "ssh finished exit_code=0" は "runner result published" より前に出る

  Scenario: runner は SSH 接続失敗で exitcode.txt=6 と原因入り stderr.log を出す
    Given host=127.0.0.1 port=9(接続拒否)を解決するジョブマップがある
    When `<runner> ... --role green --mode background` を実行する
    Then 終了コード 6 で終了し、exitcode.txt は "6"、stderr.log は "error: ssh failed host=127.0.0.1 user=<user> exit_code=6" を含む

  Scenario: runner は空白を含む引数を 1 引数として SSH コマンドに渡す
    Given fixed_args_json=["p2 p3"] で PARAM が a である
    And 実装スクリプトは "$#" と "$1" を stdout に出す
    When runner を実行する
    Then stdout.log に "2" と "p2 p3" が含まれる

  Scenario: runner は --execution-spec 指定時にジョブマップを読まない
    Given RELAY_GATE_CONFIG_DIR/green-job-map.tsv が存在しない
    And facade/20260830T150000Z-JOB001-9b8c7d6e/execution-spec.json の slots.green が host=localhost script_path=<スクリプト> を持ち run 単位の params が ["x"] である
    When `<runner> --run-id 20260830T150000Z-JOB001-9b8c7d6e --job-id JOB001 --role green --mode background --execution-spec <そのパス>` を実行する
    Then 終了コード 0 で終了し、実行ログに "job map" を含む行は無い

  Scenario: runner は --execution-spec 指定時に PARAM の併用を終了コード 2 で拒否する
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json に slots.green と params=["20260830"] がある
    When `$GREEN_RUNNER --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background --execution-spec facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json -- 20260831` を実行する
    Then exitcode.txt は 2 で、stderr.log に "error: params are not allowed with --execution-spec run_id=20260830T113000Z-JOB001-3f9a1c2e role=green" が出る
    And SSH コマンドは実行されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=on で slot_executions を RUNNING から SUCCEEDED に更新する
    Given 管理 DB の slot_executions に run_id slot=green status=RUNNING の行がある
    And 環境変数 RAPID_CROSSCHECK_MODE=on で runner を起動する
    When 実装が終了コード 0 で終了する
    Then slot_executions の該当行は status=SUCCEEDED exit_code=0 で completed_at が設定されている

  Scenario: runner は slot_executions の更新件数が 0 でも exitcode.txt の値で終了する
    Given 管理 DB の slot_executions に run_id slot=green の行が無い
    And 環境変数 RAPID_CROSSCHECK_MODE=on で runner を起動する
    When 実装が終了コード 0 で終了する
    Then 終了コード 0 で終了し、実行ログに "ERROR slot_executions update affected 0 rows run_id=<run_id> role=green" が出る
    And slot_executions に行は作成されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=on で rapid-crosscheck.env が無ければ exitcode.txt=2 で終了する
    Given RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    And 環境変数 RAPID_CROSSCHECK_MODE=on で runner を起動する
    When `<runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、exitcode.txt は "2"、stderr.log に "error: config file not found path: <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env" が出る
    And SSH コマンドは実行されない

  Scenario: runner は RAPID_CROSSCHECK_MODE=off で RDB クライアントを呼ばない
    Given RDB クライアント CLI を呼び出し記録用スタブに置き換えている
    And 環境変数 RAPID_CROSSCHECK_MODE=off で runner を起動する
    When 実装が終了する
    Then RDB スタブの呼び出し記録は無く、3 ファイルは揃っている
```
