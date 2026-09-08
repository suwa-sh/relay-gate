# slot 実行モードを選択して runner を起動する - facade / slot runner ティア仕様

## 変更概要

`facade.sh` の入口(presentation)、slot 起動フロー(usecase)、起動可否・foreground 排他の判定表(domain)、feature flag / parallel_run の repository、runner プロセス起動と RDB クライアントの gateway を新規実装する。foreground 結果の中継は UC「foreground slot の結果をジョブスケジューラへ中継する」に委ねる。

## コマンド契約

### facade.sh

- **書式**: `facade.sh JOB_ID [PARAM...]`
- **アクセス権**: ジョブスケジューラの業務ジョブ定義から同期起動(OS ユーザーはジョブスケジューラの実行ユーザー)。運用者の直接起動も同じ契約

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| JOB_ID | string | Yes | なし | 業務ジョブ識別子。英数字・`_`・`-` のみ(run_id の区切りと衝突させないため) |
| PARAM... | string[] | No | なし(0 個) | ジョブスケジューラから渡す追加引数。順序を変えずに runner へ `--` の後ろに渡す。オプション(`--help` / `--verbose`)は JOB_ID より前にのみ置ける。JOB_ID(最初の `--` 始まりでない引数)以降はすべて PARAM として runner へ渡す(`--` 始まりを含む)。JOB_ID より前の未知の `--` 始まりは `error: unknown option option=--foo` で終了コード 2(契約 `option_placement`) |
| --help | boolean | No | false | 使い方を stdout に出して終了コード 0 |
| --verbose | boolean | No | false | `info:` を実行ログに出す(中継経路のため stderr には出さない) |

- **stdin**: なし(読まない。foreground runner にも渡さない)

#### 読み込む設定(feature flag env)

キーは元の方針資料の 9 キーだけ。設定版(`CONFIG_VERSION`)は持たない。

| キー | 値 | 必須 | 検証 |
|---|---|---|---|
| BLUE_MODE / GREEN_MODE | foreground / background / off | Yes | 列挙外は `error: invalid value key=<KEY> value=...` で終了コード 2。foreground がちょうど 1 slot でなければ(両方 foreground / 両方 background または off)`error: foreground slot must be exactly one blue_mode=... green_mode=...` で終了コード 2 |
| RAPID_CROSSCHECK_MODE | foreground / background / off | Yes | 列挙外は終了コード 2。foreground と background は同じ挙動(判定は「off か off 以外か」) |
| BLUE_IMPL / GREEN_IMPL | 実装版(非空文字列) | mode≠off の slot で Yes | 欠落・空は `error: option required option=<KEY> path: ...` で終了コード 2(mode=off の slot は検証しない)。自 slot の runner に環境変数で渡す(execution-spec.json の `slots.<role>.impl_version` の出所) |
| BLUE_RUNNER / GREEN_RUNNER | runner 実体スクリプトの絶対パス | mode≠off の slot で Yes | 絶対パスでなければ `error: path is not absolute key=<KEY> path=...`、実行可能ファイルでなければ `error: file not executable key=<KEY> path=...` で終了コード 2(mode=off の slot は検証しない) |
| RAPID_CROSSCHECK_RUNNER | 速報クロスチェック runner 実体の絶対パス | RAPID_CROSSCHECK_MODE≠off のとき Yes | 上と同じ絶対パス・実行可能検証。slot runner が完了通知(blue-completed / green-completed)を送る先として環境変数で渡す |
| RAPID_CROSSCHECK_WORKER | 速報クロスチェック worker 実体の絶対パス | RAPID_CROSSCHECK_MODE≠off のとき Yes | 上と同じ絶対パス・実行可能検証。facade は起動に使わない(検証のみ) |

- 未知キーは `warn: unknown key key=<KEY> path: ...`(終了コードは変えない)。上記 9 キー以外に必須キーは無い
- 設定ファイルの所在: `$RELAY_GATE_CONFIG_DIR/feature-flag.env`(仮採用: _inference.md #5)。起動のたびに読み込み、キャッシュしない

#### 読み込む設定(管理 DB 接続。RAPID_CROSSCHECK_MODE が off 以外のときのみ)

| キー | 所在 | 必須 | 検証 |
|---|---|---|---|
| RAPID_DB_CONN_REF | `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` | off 以外のとき Yes | ファイル不在は `error: config file not found path: <path>`、キー欠落は `error: option required option=RAPID_DB_CONN_REF path: <path>`。いずれも終了コード 2(runner を起動しない)。off では読まない(契約 `config_files.rapid-crosscheck.env`) |

- 値は接続情報の参照名のみ(arch CTP-002)。facade は値を実行ログ・stderr に出さない

#### 起動する runner IF(呼び出し側の契約)

`<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background -- [PARAM...]`

- background は `&` で起動し PID を記録する。foreground も `&` で起動して PID を記録し、すべて起動後に foreground の PID だけを `wait` する
- runner に引き継ぐ環境変数: 既存 4 つ `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE`(全 UC 共通)に加え、RAPID_CROSSCHECK_MODE が off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)、通常起動では自 slot の実装版 `BLUE_IMPL`(role=blue)/ `GREEN_IMPL`(role=green)。runner は feature-flag.env を読まない。RAPID_DB_CONN_REF は渡さず、runner が off 以外のとき `rapid-crosscheck.env` を自分で読む。復元起動(background-rerun の `--execution-spec`)では impl_version を spec から読むため BLUE_IMPL / GREEN_IMPL は渡さない
- runner の実体仕様は UC「slot runner の実体スクリプトを割り当てる」を参照

## 出力契約

- **stdout**: facade 自身は何も出さない。foreground の `stdout.log` の中継のみ(UC「foreground slot の結果をジョブスケジューラへ中継する」)
- **stderr**: relay-gate 自身の検証・実行エラーのみ `error: ... key=value` 1 行 + 任意の `hint:` 1 行。foreground 起動後は stderr を汚さず実行ログへ出す
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| foreground の exitcode.txt の値 | 中継 | foreground slot が終了し 3 ファイルが揃った(この UC の正常終了) |
| 2 | 入力・設定検証エラー | JOB_ID 欠落 / JOB_ID の文字種違反 / 未知のオプション / mode 列挙外 / foreground slot がちょうど 1 つでない(両方 foreground、または両方 background / off) / 必須キー(BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)の欠落・空 / 実体パスが絶対パスでない・実体なし・実行権限なし / RAPID_CROSSCHECK_MODE 列挙外 / feature flag ファイルなし(validate-config.sh --feature-flag と同じ検証関数。canonical C8)/ off 以外のとき rapid-crosscheck.env 不在・RAPID_DB_CONN_REF 欠落 |
| 6 | 実行エラー | runner 起動前の管理 DB 書き込み失敗(parallel_runs INSERT(STARTED)、rapid_runs INSERT、slot_executions INSERT)、runner プロセスの起動失敗(exec 不可)、成果物ディレクトリ作成失敗、run_id 発行失敗。全 slot 起動後の parallel_runs STARTED→RUNNING UPDATE 失敗、slot_executions.pid UPDATE 失敗、中継後の COMPLETED UPDATE 失敗は終了コードに反映しない(実行ログ ERROR のみ。契約 facade.sh exit 6 / UC「foreground slot の結果をジョブスケジューラへ中継する」) |

エラーメッセージ(固定文言):

| 状況 | stderr |
|---|---|
| JOB_ID なし | `error: JOB_ID required` + `hint: usage: facade.sh JOB_ID [PARAM...]` |
| 両 slot foreground | `error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground` |
| foreground なし | `error: foreground slot must be exactly one blue_mode=background green_mode=off` |
| mode 列挙外 | `error: invalid value key=BLUE_MODE value=parallel` + `hint: use foreground, background or off`(KEY が RAPID_CROSSCHECK_MODE / BLUE_MODE / GREEN_MODE のとき。契約 config_files.feature-flag.env.error_messages) |
| 必須キー欠落・空 | `error: option required option=GREEN_IMPL path: /etc/relay-gate/feature-flag.env` |
| 実体パスが絶対パスでない | `error: path is not absolute key=GREEN_RUNNER path=runners/green-runner.sh` |
| runner 実体なし・実行不可 | `error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/green-runner.sh` |
| 未知キー(warn。終了コードは変えない) | `warn: unknown key key=CONFIG_VERSION path: /etc/relay-gate/feature-flag.env` |
| 管理 DB 接続失敗(off 以外) | `error: management db connection failed run_id=... conn_ref=<RAPID_DB_CONN_REF>`(ui-design.md の定型文) |
| 管理 DB INSERT 失敗(off 以外、runner 起動前) | `error: management db insert failed table=parallel_runs|rapid_runs|slot_executions run_id=...`(定型文。UPDATE 失敗は runner 起動済みのため stderr に出さず実行ログ ERROR のみ) |
| 管理 DB 接続設定なし(off 以外) | `error: config file not found path: /etc/relay-gate/rapid-crosscheck.env` / `error: option required option=RAPID_DB_CONN_REF path: /etc/relay-gate/rapid-crosscheck.env` |

## UC ロジック

- **バリデーション**(presentation → domain。runner を 1 つも起動する前にすべて実施):
  1. 引数: JOB_ID 必須、`^[A-Za-z0-9_-]+$`
  2. feature flag: ファイル存在 → 各キーの列挙 → foreground がちょうど 1 slot → 必須キー(mode≠off の slot の *_IMPL / *_RUNNER、RAPID_CROSSCHECK_MODE≠off の RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)の存在 → 実体パスの絶対パス・存在・実行権限 → 未知キー warn
  3. 検証 NG なら run_id を発行せず、成果物ディレクトリも作らない
- **確認プロンプト**: なし(非対話)
- **冪等性**: 起動のたびに新しい run_id を発行する。同じ JOB_ID を 2 回起動すると 2 つの run になる(重複防止はジョブスケジューラの責務)。parallel_runs.run_id は主キーであり衝突時は終了コード 6
- **起動順序**(usecase `launch_slots`):
  1. run_id 発行(`{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex}`。RAPID_CROSSCHECK_MODE によらず常に facade 単独で発行)→ `facade/<run_id>/` と起動対象 role のディレクトリを作成
  2. off 以外のとき parallel_runs INSERT(STARTED)と rapid_runs INSERT(completion_status=PENDING)を **同一トランザクション** で実行する(canonical C3。facade が INSERT の主体。速報側は UPDATE のみ)
  3. background slot をすべて起動(blue → green の固定順。仮採用)。slot ごとに: off 以外のとき runner 起動「前」に slot_executions INSERT(status=RUNNING, pid=NULL)→ runner 起動(環境変数 RAPID_CROSSCHECK_MODE / RAPID_CROSSCHECK_RUNNER(off 以外)/ 自 slot の BLUE_IMPL または GREEN_IMPL を渡す)→ PID 取得 → off 以外のとき `UPDATE slot_executions SET pid=? WHERE run_id=? AND slot=?`
  4. foreground slot を起動(step 3 と同じ順序: off 以外のとき INSERT(pid=NULL)→ 起動 → pid UPDATE)
  5. off 以外のとき parallel_runs を条件付き UPDATE(STARTED → RUNNING)
  - INSERT を起動前に行う理由: 即時に終了する runner(ジョブマップ未定義・SSH 即失敗)の終端 UPDATE(`WHERE status='RUNNING'`)が facade の INSERT より先に走って 0 件になる競合を防ぐ(round-1 F-004)
  6. foreground の PID を `wait`。background の PID は wait しない(`disown`)
- **エラーハンドリング**: domain / repository / gateway のエラーは usecase で 1 回だけ実行ログに ERROR を出し presentation に返す(CLR-001)。step 2 で失敗したら runner を起動しない。step 3〜4 の途中で runner 起動に失敗したら、起動済みの background runner はそのまま実行を継続させ(停止しない)、終了コード 6 で終了する。実行ログに起動済み PID を残す。起動に失敗した slot の slot_executions 行(pid=NULL・RUNNING)は `UPDATE ... SET status='FAILED', completed_at=now WHERE run_id=? AND slot=? AND status='RUNNING'` でベストエフォートに閉じる(失敗しても終了コード 6 は変えない)。slot_executions の INSERT 失敗は終了コード 6(当該 slot を起動しない)。pid UPDATE 失敗と全 slot 起動後の parallel_runs STARTED→RUNNING UPDATE 失敗は runner 起動済みのため実行ログ ERROR のみ(終了コードは変えない。契約 facade.sh exit 6)
- **クラッシュ耐性**:
  - step 1〜2 の間に落ちた場合: parallel_runs に STARTED の行が残ることがある。hang-detector は STARTED の run を走査対象にせず、運用者が run-lineage で確認できる。再実行はジョブスケジューラの正規ジョブ(新 run_id)
  - step 3〜6 の間に facade が落ちた場合: runner プロセスは親を失っても継続する(`setsid` で起動。仮採用)。成果物は runner が完結させる。parallel_runs は RUNNING のまま残り、foreground の中継は行われない(ジョブスケジューラには facade の異常終了が伝わる)
  - 管理 DB は STARTED / RUNNING の 2 段更新のみで、ロールバック不要
- **実行ログ**(`$RELAY_GATE_LOG_DIR/facade.sh.log`。契約 facade.sh execution_log と同順): `INFO feature flag loaded blue_mode=... green_mode=... rapid_crosscheck_mode=... blue_impl=... green_impl=... operation_mode=parallel|green_only|next_gen_parallel|custom`(operation_mode は validate-config.sh と同じ導出関数で、値は英字コード(契約 config_files.feature-flag.env.derived)。UC「切り替えた運用モードで業務ジョブを実行する」が参照。`config_version=` は出さない)/ `INFO run started run_id=... job_id=...` / `INFO parallel_run status changed from=STARTED to=RUNNING run_id=...`(off 以外)/ `INFO slot started slot=green mode=background pid=12345` / `INFO waiting foreground slot=blue pid=12346` / `INFO foreground finished slot=blue exit_code=0` / `ERROR management db update failed table=slot_executions run_id=...`(pid UPDATE 失敗。終了コードは変えない)/ `ERROR management db update failed table=parallel_runs run_id=...`(全 slot 起動後の STARTED→RUNNING UPDATE 失敗。runner は起動済みのため終了コードは変えない。契約 facade.sh execution_log)
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## 設定契約

feature flag(env)の列定義と検証は UC「feature flag を設定する」の tier-facade.md を正本とする。この UC はその契約を読み取り専用で従う(arch CM-001 conformist)。

## データモデル変更

### parallel_runs(情報: 並行稼働実行。RAPID_CROSSCHECK_MODE が off 以外のみ。ジョブキュー兼管理 DB は relay-gate 内部のデータストア)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string(PK) | `{ローカル yyyymmddThhmmss}-{job_id}-{hex8}`(成果物ディレクトリ名と同じ値) | 追加 |
| parent_run_id | string(null 可) | リラン元。facade 起動では NULL | 追加 |
| job_id | string | JOB_ID | 追加 |
| parameters | text | PARAM... の JSON 配列文字列 | 追加 |
| execution_spec_uri | string | `<ARTIFACT_ROOT>/facade/<run_id>/execution-spec.json` | 追加 |
| status | string | STARTED / RUNNING / COMPLETED / ABORTED | 追加 |
| requested_at | datetime | 発行日時(UTC) | 追加 |
| completed_at | datetime(null 可) | 中継完了日時 | 追加 |

### slot_executions(情報: slot 実行。off 以外のみ。INSERT 順序は仮採用: _inference.md #7。status はファイル正本(条件「slot 実行の状態導出規則」)と同じ値を保持する二重マッピング)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string(PK) | run_id | 追加 |
| slot | string(PK) | blue / green | 追加 |
| mode | string | foreground / background | 追加 |
| pid | integer(null 可) | runner の PID。起動前の INSERT では NULL、起動後に UPDATE で設定 | 追加 |
| artifact_dir | string | `facade/<run_id>/<slot>/` | 追加 |
| status | string | RUNNING / SUCCEEDED / FAILED / ABORTED | 追加 |
| exit_code | integer(null 可) | 終了時に exitcode.txt の値。起動時は NULL | 追加 |
| started_at | datetime | 起動日時 | 追加 |
| completed_at | datetime(null 可) | SUCCEEDED / FAILED / ABORTED へ遷移した日時(UTC) | 追加 |

### rapid_runs(情報: 速報実行。off 以外のみ。parallel_runs と同一トランザクションで facade が INSERT。canonical C3)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string(PK) | run_id | 追加 |
| completion_status | string | PENDING で作成 | 追加 |
| blue_status / green_status | string(null 可) | 作成時 NULL | 追加 |

### ファイル

| ファイル | 説明 | 変更種別 |
|---|---|---|
| `facade/<run_id>/` | run ディレクトリ(facade が作成) | 追加 |
| `facade/<run_id>/<role>/` | role ディレクトリ(起動対象 role のみ。facade が作成) | 追加 |

## ビジネスルール

- blue と green の両方が foreground の構成は許可しない。入力検証で検出し、どの slot も起動しない(条件: foreground slot 排他)
- off の slot は起動しない(条件: slot 起動可否判定)
- background をすべて起動 → foreground 起動 → foreground の PID だけを待機(条件: slot 起動順序)
- RAPID_CROSSCHECK_MODE が foreground / background のときのみ parallel_run を作成し、off では管理 DB に接続も書き込みもしない(parallel_run も作らない)。run_id 自体はモードによらず facade 単独で発行する(成果物ディレクトリ名に必要)(条件: 速報クロスチェック有効判定)
- facade は確報クロスチェックを起動しない(条件: 確報クロスチェック非起動)
- facade は JOB_ID と PARAM... だけを受け取り、比較対象・実行先・起動方式を判断しない(条件: facade の責務限定 / 実装固有事項の runner への閉じ込め)

## ティア完了条件(BDD)

```gherkin
Feature: slot 実行モードを選択して runner を起動する - facade / slot runner ティア

  Scenario: facade_sh は background を先に起動し foreground だけを wait する
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> がある
    And スタブ runner は起動引数・環境変数・起動時刻をファイルに記録し、green は 30 秒 sleep、blue は exitcode.txt に 0 を書いて即終了する
    When `facade.sh JOB001 20260830 full` を実行する
    Then 終了コード 0 で終了し、green の起動記録が blue より先である
    And green の起動引数は "--run-id <run_id> --job-id JOB001 --role green --mode background -- 20260830 full" である
    And green の記録した環境変数に GREEN_IMPL=v2 と RAPID_CROSSCHECK_MODE=off があり RAPID_CROSSCHECK_RUNNER は無い
    And <run_id> は正規表現 ^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$ に一致する
    And facade の終了時に green のスタブはまだ実行中である

  Scenario: facade_sh は両 slot foreground を終了コード 2 で拒否する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground がある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る
    And スタブ runner の起動記録は存在しない
    And RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=background で parallel_runs を STARTED から RUNNING へ更新する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> RAPID_CROSSCHECK_WORKER=<実行可能なスタブ> がある
    And 管理 DB が起動している
    When `facade.sh JOB001` を実行する
    Then parallel_runs に run_id job_id=JOB001 status=RUNNING parameters=[] の行が 1 件ある
    And parallel_runs.run_id は成果物ディレクトリ facade/<run_id>/ の名前と同じ値である
    And 実行ログに "parallel_run status changed from=STARTED to=RUNNING run_id=<run_id>" が出る
    And 実行ログの "feature flag loaded" 行に "blue_impl=v1" と "operation_mode=custom" が含まれ "config_version=" は含まれない
    And blue のスタブ runner が記録した環境変数に RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> がある

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=foreground を background と同じに扱う
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=foreground があり管理 DB が起動している
    When `facade.sh JOB001` を実行する
    Then parallel_runs に run_id の行が status=RUNNING で 1 件あり rapid_runs に completion_status=PENDING の行が 1 件ある

  Scenario: facade_sh は runner 起動前に slot_executions を pid=NULL で INSERT し起動後に pid を更新する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background があり管理 DB が起動している
    And RDB クライアント CLI のパスに SQL を順序つきで記録して実 DB へ転送するラッパーを置く
    And green のスタブ runner は起動直後に exitcode.txt=2 を書いて終了し、自分の slot_executions 行を RUNNING → FAILED に更新する
    When `facade.sh JOB001` を実行する
    Then 記録された SQL は slot_executions の INSERT(slot=green, pid NULL)が green runner 起動より前で、pid の UPDATE がその後である
    And 最終的に slot_executions の slot=green の行は status=FAILED exit_code=2 で pid が設定されている(runner 側の終端 UPDATE が 0 件にならない)

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=background で rapid-crosscheck.env が無ければ終了コード 2 で終了する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background がある
    And RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env" が出る
    And どの runner も起動されない

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=off で RDB クライアントを呼ばない
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off がある
    And RDB クライアント CLI のパスに呼び出し記録用スタブを置く
    When `facade.sh JOB001` を実行する
    Then 終了コード 0 で終了し、RDB クライアントスタブの呼び出し記録は存在しない

  Scenario: facade_sh は runner 実体が実行不可なら終了コード 2 で終了する
    Given feature-flag.env に BLUE_MODE=foreground BLUE_RUNNER=<実行可能な runner> GREEN_MODE=background GREEN_RUNNER=/opt/relay-gate/runners/missing.sh RAPID_CROSSCHECK_MODE=off がある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る
    And blue runner も起動されない

  Scenario: facade_sh は未知キーを warn にとどめ 9 キー以外を必須にしない
    Given feature-flag.env に 9 キーがすべて正しく定義され、加えて CONFIG_VERSION=2026-08-30 がある
    When `facade.sh JOB001` を実行する
    Then stderr に "warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env" が出るが終了コードは foreground の exitcode.txt の値である

  Scenario: facade_sh は JOB_ID 欠落を終了コード 2 で拒否する
    Given feature-flag.env が正しく定義されている
    When `facade.sh` を引数なしで実行する
    Then 終了コード 2 で stderr に "error: JOB_ID required" が出る
```
