# 実装スクリプトを実行して Runner Result を出力する

## 概要

slot runner が解決済み(または `--execution-spec` から復元済み)の実行先ホストへ実行ユーザーで SSH 接続し、現行実装(blue)または新実装(green)のスクリプトを作業ディレクトリ・固定引数・追加引数付きで実行する。foreground / background を問わず `started-at.txt` を起動時に、`stdout.log` / `stderr.log` / `exitcode.txt` を実行終了後に一時ファイル経由で原子的に出力する。SSH 失敗・起動失敗でも 3 ファイルを揃え、exitcode.txt が 0 なら slot 実行を SUCCEEDED、非 0 なら FAILED とする。完了通知の送信は UC「速報クロスチェック runner へ完了通知を送信する」に委ねる。

## データフロー

```mermaid
graph LR
  subgraph FACADE["tier-facade"]
    U["usecase\nExecuteImplementationCommand"]
    D["domain\nSlotExecution(RUNNING → SUCCEEDED / FAILED)\nexitcode → status 判定"]
    R1["repository\nExecutionSpecRepository(復元起動時の読み込み)"]
    R2["repository\nRunnerResultRepository(3 ファイル + started-at.txt)"]
    R3["repository\nSlotExecutionRepository(on のみ)"]
    G1["gateway\nSshAdapter(ssh exec_user@host)"]
    G2["gateway\nFilesystemAdapter(一時 → mv)"]
    G3["gateway\nRdbClientAdapter"]
    U -->|"function 呼び出し"| D
    U --> R1
    U --> R2
    U --> R3
    U -->|"SSH 実行"| G1
    R2 --> G2
    R3 --> G3
  end
  subgraph SSH["リモート実行ホスト(SSH)"]
    IMPL["現行実装(blue) / 新実装(green)\nscript_path args..."]
  end
  subgraph FS["FS(成果物ディレクトリ)"]
    ART[("facade/run_id/role/\nstarted-at.txt stdout.log stderr.log exitcode.txt")]
    SPEC[("facade/run_id/execution-spec.json")]
  end
  subgraph RDB["RDB(管理 DB)"]
    SE[("slot_executions\nstatus=RUNNING → SUCCEEDED / FAILED")]
  end
  G1 -->|"ssh -n exec_user@host 'cd work_dir && script_path args'"| IMPL
  IMPL -->|"stdout / stderr / 終了コード"| G1
  G2 -->|"ファイル書き込み"| ART
  R1 -->|"ファイル読み込み"| SPEC
  G3 -->|"SQL UPDATE(on のみ)"| SE
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| usecase | ExecuteImplementationCommand | started-at.txt 出力 → SSH 実行(stdout / stderr を一時ファイルへ)→ 終了コード取得 → 3 ファイル確定 → status 判定 → (on) slot_executions 更新 → 完了通知(次 UC)。`--execution-spec` 指定時はジョブマップを再解決せず `slots.<role>.*` と run 単位の `params` から復元 |
| domain | SlotExecution | `exit_code == 0 → SUCCEEDED`、それ以外 → FAILED の純粋関数。SSH 接続失敗は exit_code 6(ui-design.md の実行エラー。ssh 自身の 255 は 6 に読み替える。仮採用)を FAILED として扱う |
| repository | RunnerResultRepository / ExecutionSpecRepository / SlotExecutionRepository | 3 ファイルの原子的公開、spec の読み込み、slot_executions の条件付き UPDATE |
| gateway | SshAdapter / FilesystemAdapter / RdbClientAdapter | `ssh` コマンド起動(認証は credential_ref から実行環境の設定(`~/.ssh/config` の Host 別名。仮採用)に解決)、一時ファイル → `mv`、RDB クライアント CLI |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ(facade / background-rerun 経由)
  box rgb(240,255,240) tier-facade
    participant UC as usecase(runner)
    participant Dom as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(成果物)
  participant Host as リモート実行ホスト(SSH)
  participant DB as RDB(slot_executions)

  alt --execution-spec 指定あり(復元起動)
    UC->>Repo: execution-spec.json を読む(ジョブマップ再解決なし)
    Repo->>FS: 読み込み
    FS-->>UC: slots.<role>.host / exec_user / script_path / work_dir / fixed_args と run 単位の params
  else 通常起動
    UC->>UC: 前 UC の ExecutionTarget と保存済み spec を使う
  end
  UC->>Repo: started-at.txt を出力
  Repo->>GW: 一時 → mv
  GW->>FS: started-at.txt(UTC ISO 8601)
  UC->>GW: SSH 実行
  GW->>Host: ssh -n exec_user@host 'cd work_dir && script_path args...'(stdout → stdout.log.tmp、stderr → stderr.log.tmp)
  alt 実行成功(終了コード取得)
    Host-->>GW: 終了コード N
  else SSH 接続失敗 / 起動失敗
    GW->>GW: stderr.log.tmp に "error: ssh failed host=... user=... exit_code=6" を追記
    GW-->>UC: 終了コード 6
  end
  UC->>Repo: 3 ファイルを確定公開
  Repo->>GW: mv stdout.log.tmp stdout.log、mv stderr.log.tmp stderr.log、exitcode.txt.tmp → exitcode.txt(最後)
  GW->>FS: 確定名
  UC->>Dom: exitcode → status
  alt Runner Result 完備条件: exitcode.txt=0
    Dom-->>UC: SUCCEEDED
  else 非 0
    Dom-->>UC: FAILED
  end
  alt RAPID_CROSSCHECK_MODE=on
    UC->>Repo: slot_executions を更新
    Repo->>GW: RDB
    GW->>DB: UPDATE slot_executions SET status=?, exit_code=?, completed_at=now WHERE run_id=? AND slot=? AND status='RUNNING'
    opt 更新件数 0(facade の INSERT が無い)
      GW-->>UC: 実行ログ ERROR(INSERT しない。終了コードは変えない)
    end
    UC->>UC: 完了通知(UC「速報クロスチェック runner へ完了通知を送信する」)
  end
  UC-->>Sched: runner 終了コード = exitcode.txt の値
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 実装スロット | blue | 現行実装のスクリプトを起動。成果物 `facade/<run_id>/blue/` | tier-facade | usecase `execute_implementation` |
| 実装スロット | green | 新実装のスクリプトを起動。成果物 `facade/<run_id>/green/` | tier-facade | usecase `execute_implementation` |
| slot 実行モード | foreground | 同じ 3 ファイルを出力。facade が待機して中継する | tier-facade | usecase `execute_implementation` |
| slot 実行モード | background | 同じ 3 ファイルを出力。facade は待機しない。hang-detector が started-at.txt / exitcode.txt で監視 | tier-facade | usecase `execute_implementation` |
| Runner Result 成果物種別 | started-at.txt | 起動時に UTC ISO 8601 を 1 行 | tier-facade | repository `runner_result_repo` |
| Runner Result 成果物種別 | stdout.log | 実装の標準出力(SSH 経由) | tier-facade | gateway `ssh_adapter` |
| Runner Result 成果物種別 | stderr.log | 実装の標準エラー + SSH 失敗時の原因 | tier-facade | gateway `ssh_adapter` |
| Runner Result 成果物種別 | exitcode.txt | 数値 1 行。最後に確定する | tier-facade | repository `runner_result_repo` |
| run role(成果物ディレクトリ区分) | blue / green | `--role` の値をディレクトリ名に使う | tier-facade | repository `runner_result_repo` |
| 速報クロスチェックモード | on | slot_executions 更新 + 完了通知 | tier-facade | usecase `execute_implementation` |
| 速報クロスチェックモード | off | 管理 DB に触れず、完了通知を送らない。3 ファイルだけで完結 | tier-facade | usecase `execute_implementation` |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| Runner Result 完備条件 | 実行終了時に stdout.log / stderr.log / exitcode.txt を揃える。exitcode.txt は数値 1 行で runner の終了コードと一致。SSH 失敗・起動失敗でも 3 ファイルを出力。0 → SUCCEEDED、非 0 → FAILED | tier-facade | usecase `execute_implementation` / domain `judge_slot_status` | 実行終了後に 3 ファイルが揃う(SPEC-003-01) / SSH 失敗でも 3 ファイルを揃える(SPEC-003-02) |
| 成果物公開判定 | 各ファイルは `.tmp` に書いてから `mv`。exitcode.txt を最後に確定する(exitcode.txt の存在 = 3 ファイル完備の合図) | tier-facade | repository `runner_result_repo` | 書き込み途中の確定名ファイルは存在しない(SPEC-003-03) |
| 引数連結規則 | 復元起動では `slots.<role>.fixed_args` + run 単位の `params` を、通常起動では前 UC の ArgumentList を、順序を変えずに SSH コマンドへ渡す。各引数は単一クォートでエスケープして 1 引数を維持 | tier-facade | gateway `ssh_adapter` | 空白を含む引数を 1 引数として実装へ渡す |
| 実装固有事項の runner への閉じ込め | SSH の接続方法(ポート・鍵・踏み台)、OS 差異、プロトコルは runner 実体と適用側の SSH 設定に閉じ込める。本 UC が定める契約は runner IF と 3 ファイルだけ | tier-facade | runner 実体 / gateway `ssh_adapter` | 実行終了後に 3 ファイルが揃う |
| リランの実行設定復元 | `--execution-spec <path>` があればジョブマップを読まず、`slots.<role>` の host / exec_user / script_path / work_dir / fixed_args と run 単位の `params` で起動する | tier-facade | usecase `execute_implementation` | 復元起動はジョブマップを再解決しない(SPEC-009-02) |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| exitcode → 状態 | exitcode.txt | `0 → SUCCEEDED`、`それ以外 → FAILED` | slot 実行 status | tier-facade |
| runner 終了コード | exitcode.txt | runner プロセスの終了コード = exitcode.txt の値(SSH 接続失敗は 6。仮採用: ui-design.md 実行エラー) | 終了コード | tier-facade |
| SSH コマンド | host、exec_user、work_dir、script_path、args | `ssh -n <exec_user>@<host> 'cd <work_dir> && <script_path> <arg1> <arg2> ...'`(契約 external_interfaces「SSH(実装スクリプトの実行)」の形式。`-n` で stdin を閉じる。各引数は単一クォートでエスケープ。BatchMode 等の対話禁止オプションは runner 実体 / SSH 設定に閉じ込める。仮採用) | コマンド文字列 | tier-facade |
| started_at | 起動時刻 | `date -u +%Y-%m-%dT%H:%M:%SZ` | started-at.txt | tier-facade |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| slot 実行 | RUNNING | SUCCEEDED | exitcode.txt に 0 を公開 | started-at.txt 出力済み | on のとき slot_executions 条件付き UPDATE、完了通知(次 UC) | tier-facade |
| slot 実行 | RUNNING | FAILED | exitcode.txt に非 0 を公開(SSH 失敗含む) | started-at.txt 出力済み | on のとき slot_executions 条件付き UPDATE、完了通知(次 UC)。hang-detector が実行エラーを通知 | tier-facade |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実装切替業務 | この UC が属する業務 |
| BUC | 実装切替ジョブ実行フロー | この UC を含む BUC |
| アクター | 運用者 | 受益者 |
| 情報 | 実行設定(execution-spec) | 実行先と引数の正本 |
| 情報 | slot 実行 | RUNNING → SUCCEEDED / FAILED |
| 情報 | Runner Result | 出力対象 |
| 情報 | 実行ログ | SSH 開始・終了・所要時間・成否 |
| 条件 | Runner Result 完備条件 / 成果物公開判定 / 引数連結規則 / 実装固有事項の runner への閉じ込め | 分岐条件一覧を参照 |
| 画面 | slot runner 実行出力(→ CLI 出力) | 3 ファイルと実行ログ |
| イベント | 実行先ホストへのリモート実行 / 現行実装スクリプトの起動 / 新実装スクリプトの起動 | SSH 実行 |
| 外部システム | リモート実行ホスト(SSH) / 現行実装(blue) / 新実装(green) | 実行先 |
| 状態 | slot 実行 | 状態遷移一覧を参照 |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-003 | SPEC-003-01 | 実行終了後に 3 ファイルが揃う / runner の終了コードは exitcode.txt と一致する / 起動時に started-at.txt を出力する |
| REQ-003 | SPEC-003-02 | SSH 失敗でも 3 ファイルを揃える |
| REQ-003 | SPEC-003-03 | 書き込み途中の確定名ファイルは存在しない |
| REQ-003 | SPEC-003-04 | background でも同じ 3 ファイルを残す |
| REQ-009 | SPEC-009-02 | 復元起動はジョブマップを再解決しない |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 実装スクリプトを実行して Runner Result を出力する

  Scenario: 実行終了後に 3 ファイルが揃う(SPEC-003-01)
    Given green のジョブマップが host=host-green-01 exec_user=batch script_path=/opt/app/bin/job001.sh work_dir=/var/app/work を解決する
    And job001.sh は stdout に "done" を出し終了コード 0 で終了する
    When facade が green runner を --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動し実行が終了する
    Then facade/20260830T113000Z-JOB001-3f9a1c2e/green/ に stdout.log stderr.log exitcode.txt が揃う
    And stdout.log の内容は "done"、exitcode.txt の内容は "0" の 1 行である
    And slot 実行は SUCCEEDED である

  Scenario: runner の終了コードは exitcode.txt と一致する(SPEC-003-01)
    Given job001.sh は終了コード 4 で終了する
    When green runner が実行を終える
    Then exitcode.txt の内容は "4" であり runner プロセスの終了コードも 4 である
    And slot 実行は FAILED である

  Scenario: 起動時に started-at.txt を出力する(SPEC-003-01)
    Given job001.sh は 120 秒かかる
    When green runner を --mode background で起動して 5 秒後に確認する
    Then facade/<run_id>/green/started-at.txt が存在し UTC ISO 8601(例 2026-08-30T11:30:05Z)の 1 行である
    And exitcode.txt はまだ存在しない

  Scenario: background でも同じ 3 ファイルを残す(SPEC-003-04)
    Given feature flag に GREEN_MODE=background がある
    When green の実行が終了する
    Then facade/<run_id>/green/ に stdout.log stderr.log exitcode.txt が残る

  Scenario: 空白を含む引数を 1 引数として実装へ渡す
    Given fixed_args=["p2 p3"] params=["a"] である
    And job001.sh は受け取った引数の個数と各値を stdout に出す
    When green runner が実行を終える
    Then stdout.log に "argc=2" と "p2 p3" と "a" が含まれる

  Scenario: 復元起動はジョブマップを再解決しない(SPEC-009-02)
    Given 元の execution-spec.json の slots.green が host=host-green-01 script_path=/opt/app/bin/job001.sh を持つ
    And 現在の green-job-map.tsv は JOB001 を host=host-green-02 に変更済みである
    When green runner を --execution-spec facade/20260830T150000Z-JOB001-9b8c7d6e/execution-spec.json 付きで起動する
    Then SSH 接続先は host-green-01 であり、実行ログに "job map resolved" は出ない
```

### 異常系

```gherkin
  Scenario: SSH 失敗でも 3 ファイルを揃える(SPEC-003-02)
    Given green のジョブマップが host=host-unreachable を解決する
    When green runner が起動し SSH 接続に失敗する
    Then facade/<run_id>/green/ に stdout.log(空) stderr.log exitcode.txt が揃う
    And exitcode.txt の内容は "6" であり runner の終了コードも 6 である
    And stderr.log に "error: ssh failed host=host-unreachable user=batch exit_code=6" が含まれる
    And slot 実行は FAILED である

  Scenario: 書き込み途中の確定名ファイルは存在しない(SPEC-003-03)
    Given job001.sh が stdout へ 10 MB を出力し続けている
    When 実行中に成果物ディレクトリを確認する
    Then stdout.log.tmp は存在してもよいが stdout.log と exitcode.txt は存在しない
    And 実行終了後に .tmp サフィックスのファイルは残らない
```

## ティア別仕様

- [facade / slot runner ティア](tier-facade.md)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(runner IF を uses)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(`slot-completed` の publish は次 UC)
- 完了通知: [速報クロスチェック runner へ完了通知を送信する](../../../クロスチェック業務/速報クロスチェックフロー/速報クロスチェック%20runner%20へ完了通知を送信する/spec.md)
- runner 実体の契約: [slot runner の実体スクリプトを割り当てる](../../../適用構成業務/適用構成定義フロー/slot%20runner%20の実体スクリプトを割り当てる/tier-facade.md)
