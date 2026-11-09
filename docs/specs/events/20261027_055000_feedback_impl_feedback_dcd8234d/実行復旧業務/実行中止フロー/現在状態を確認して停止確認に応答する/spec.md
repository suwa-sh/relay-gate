# 現在状態を確認して停止確認に応答する

## 概要

運用者が通知メールやジョブスケジューラの実行結果から中止対象の run_id を特定し、`abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh` を `--run-id` 付きで起動する。スクリプトは対象の現在状態を plain 形式で表示し、「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」を stdin から読む。slot 系(abort-blue / abort-green)の現在状態は成果物ファイルから導出する(mode は `execution-spec.json` の `slots.<role>.mode`、status は条件「slot 実行の状態導出規則」: exitcode.txt があれば SUCCEEDED / FAILED、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING、started-at.txt が無ければ未起動)。RAPID_CROSSCHECK_MODE が off 以外なら管理 DB の `slot_executions` から PID を補う。依頼系(abort-rapid-crosscheck / abort-final-crosscheck)の現在状態は管理 DB の依頼レコード(status / worker_id / lease_until)から取る。運用者はプロセス・Pod・SSH 接続先の処理を自身で強制終了したことを確認して `yes` または yes 以外で応答する。本 UC は 4 スクリプト共通の前半(状態表示と対話確認)であり、`yes` 以降の状態更新は UC「実行を ABORTED へ遷移させる」が担う。

## データフロー

```mermaid
graph LR
  subgraph OPS["tier-ops"]
    OPS_Pres["presentation\nabort-* 引数 (--run-id / --yes)\n停止確認プロンプト"]
    OPS_UC["usecase\nAbortConfirmationFlow"]
    OPS_Domain["domain\nAbortTargetState\n(mode / status 導出) / StopConfirmationAnswer (yes / no)"]
    OPS_Repo["repository\nExecutionSpecRepository / SlotExecutionRepository / CrosscheckRequestRepository"]
    OPS_GW["gateway\nファイルシステム / RDB クライアントアダプタ"]
    OPS_Pres --> OPS_UC --> OPS_Repo --> OPS_GW
    OPS_UC --> OPS_Domain
  end
  subgraph FS["FS(成果物ディレクトリ。slot 系の正本)"]
    FS_Spec["facade/<run_id>/execution-spec.json\njob_id / slots.<role>.mode"]
    FS_Art["facade/<run_id>/<role>/\nstarted-at.txt / exitcode.txt / aborted.txt"]
  end
  subgraph DB["内部データストア: ジョブキュー兼管理 DB(RDB)"]
    DB_SE[("slot_executions\npid(off 以外のみ参照)")]
    DB_RR[("rapid_crosscheck_requests\nstatus / worker_id / lease_until")]
    DB_FR[("final_crosscheck_requests\nstatus / worker_id / lease_until")]
  end
  OPS_GW -->|"ファイル読み取り(abort-blue / abort-green)"| FS_Spec
  OPS_GW -->|"ファイル読み取り(abort-blue / abort-green)"| FS_Art
  OPS_GW -->|"SQL: SELECT pid WHERE run_id = ? AND slot = ?(off 以外)"| DB_SE
  OPS_GW -->|"SQL: SELECT ... WHERE run_id = ?"| DB_RR
  OPS_GW -->|"SQL: SELECT ... WHERE final_crosscheck_id = ?"| DB_FR
  FS_Art --> OPS_GW --> OPS_Repo --> OPS_Domain --> OPS_UC --> OPS_Pres
  OPS_Pres -->|"stdout: 現在状態 / stderr: プロンプト"| Operator["運用者"]
  Operator -->|"stdin: yes / no"| OPS_Pres
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| ops presentation | 引数(`--run-id 20260830T113000-JOB001-3f9a1c2e`, `--yes`) | 引数検証 → AbortConfirmationFlow。stdin の TTY 判定 |
| ops usecase | AbortConfirmationFlow(run_id / target kind) | 対象種別(blue / green / rapid-crosscheck / final-crosscheck)に応じた状態取得 → 表示行 → 応答の取得 |
| ops domain | AbortTargetState(slot 系: mode / status / pid / started_at / artifact_dir。依頼系: status / worker_id / lease_until)、StopConfirmationAnswer(`yes` 完全一致のみ肯定) | slot 系の status はファイルの有無・値から導出する純粋関数(条件「slot 実行の状態導出規則」)。応答判定も純粋関数 |
| ops repository / gateway | slot 系: `execution-spec.json` + `started-at.txt` / `exitcode.txt` / `aborted.txt`(+ off 以外は `slot_executions.pid`)。依頼系: `rapid_crosscheck_requests` / `final_crosscheck_requests` の SELECT | 現在状態の取得(更新しない) |
| ops presentation(出力) | stdout `key=value`(固定順)、stderr プロンプト | 現在状態の提示。応答が `yes` なら後半 UC へ、それ以外は `status={現在状態}` を出して終了コード 3 |

## 処理フロー

```mermaid
sequenceDiagram
  actor Ops as 運用者
  participant Sched as ジョブスケジューラ / 通知メール
  box rgb(240,255,240) tier-ops
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(成果物ディレクトリ)
  participant DB as 管理 DB(RDB)

  Sched-->>Ops: 通知メール(run_id / job_id / role)または実行結果
  Ops->>Pres: abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e
  Pres->>Pres: 引数検証(run_id 必須・形式 / 未知オプション → 2)
  Pres->>Pres: stdin が非 TTY かつ --yes なし → error: interactive confirmation required (use --yes for non-interactive) / 終了コード 2
  Pres->>UC: AbortConfirmationFlow(run_id, kind=green)
  alt slot 系(abort-blue / abort-green)
    UC->>Repo: 現在状態を成果物ファイルから導出
    Repo->>GW: read facade/<run_id>/execution-spec.json
    GW->>FS: read
    alt execution-spec.json なし
      UC-->>Pres: 業務エラー
      Pres-->>Ops: stderr error: run not found run_id=... role=green / 終了コード 3
    else あり(slots.green 節なし = mode off / あり = slots.green.mode)
      Repo->>GW: read facade/<run_id>/green/{started-at.txt, exitcode.txt, aborted.txt}
      GW->>FS: 有無と中身
      GW-->>Repo: AbortTargetState(mode, status 導出: exitcode.txt → SUCCEEDED / FAILED、aborted.txt → ABORTED、どちらも無し → RUNNING、started-at.txt なし → 未起動 `-`)
      opt RAPID_CROSSCHECK_MODE が off 以外
        Repo->>GW: SELECT pid FROM slot_executions WHERE run_id = ? AND slot = 'green'
        GW->>DB: SQL
        DB-->>GW: pid(行なしは -)
      end
    end
  else abort-rapid-crosscheck
    alt RAPID_CROSSCHECK_MODE=off(依頼レコードは管理 DB にしか無い)
      UC-->>Pres: 業務エラー
      Pres-->>Ops: stderr error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... / 終了コード 3
    else off 以外
      Repo->>GW: SELECT rapid_crosscheck_requests WHERE run_id = ?
      GW->>DB: SQL
      DB-->>GW: 行(または 0 行 → error: request not found run_id=... / 3)
    end
  else abort-final-crosscheck(RAPID_CROSSCHECK_MODE は参照しない)
    alt final-crosscheck.env / FINAL_DB_CONN_REF なし
      UC-->>Pres: 業務エラー
      Pres-->>Ops: stderr error: management db is not configured run_id=... / 終了コード 3
    else あり
      Repo->>GW: SELECT final_crosscheck_requests WHERE final_crosscheck_id = ?
      GW->>DB: SQL
      DB-->>GW: 行(または 0 行 → 3)
    end
  end
  opt 対象あり
    Repo-->>UC: AbortTargetState
    UC-->>Pres: 現在状態の表示行
    Pres-->>Ops: stdout run_id / job_id / role / mode / status / pid / started_at / artifact_dir
    alt --yes 指定
      Pres->>Domain: answer=yes(--yes)
    else 対話
      Pres-->>Ops: stderr 対象ジョブのプロセスは強制終了してありますか？ [yes/no]:
      Ops->>Pres: stdin 1 行
      Pres->>Domain: StopConfirmationAnswer 判定(yes 完全一致のみ肯定)
    end
    alt 応答が yes 以外
      Pres-->>Ops: stdout status={現在状態} / stderr info: aborted by operator#59; status not changed / 終了コード 3
      Note over UC: 実行ログ INFO operator=ops01 answer=no run_id=... role=green
    else yes
      Note over Pres,UC: UC「実行を ABORTED へ遷移させる」へ続く
    end
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 中止対象種別 | background slot 実行 | `abort-blue.sh` / `abort-green.sh`。`execution-spec.json` の mode と成果物ファイルから導出した status、成果物ディレクトリ、started-at.txt の開始時刻、(off 以外)`slot_executions.pid` を表示 | tier-ops | abort-blue.sh / abort-green.sh |
| 中止対象種別 | 速報比較依頼 | `abort-rapid-crosscheck.sh`。`rapid_crosscheck_requests` の status / worker_id / lease_until を表示。REQUESTED / CLAIMED / RUNNING の依頼はいずれも停止確認へ進む(REQUESTED には worker プロセスが無いが確認は省略しない。可否判定は後半 UC の条件「依頼中止可否判定」) | tier-ops | abort-rapid-crosscheck.sh |
| 中止対象種別 | 確報比較依頼 | `abort-final-crosscheck.sh`。`final_crosscheck_requests` の status / worker_id / lease_until を表示(中止可は RUNNING のみ。可否判定は後半 UC) | tier-ops | abort-final-crosscheck.sh |
| 停止確認応答 | yes | 小文字完全一致のみ肯定。後半 UC(状態更新)へ進む | tier-ops | 4 スクリプト共通のプロンプト処理 |
| 停止確認応答 | no | `no`・空 Enter・`y`・`YES` 等 yes 以外はすべて no 扱い。状態を変えず終了コード 3 | tier-ops | 同上 |
| run role(成果物ディレクトリ区分) | blue / green / rapid-crosscheck / final-crosscheck | 表示行の `role=` と実行ログの `role=`。スクリプト名で確定する | tier-ops | 4 スクリプト |
| クロスチェック依頼状態 | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | 依頼系の現在状態として `status=` に表示。表示後の中止可否(速報: REQUESTED / CLAIMED / RUNNING = 可、終端 = 3。確報: RUNNING のみ可)は後半 UC の判定表に従う | tier-ops | abort-rapid-crosscheck.sh / abort-final-crosscheck.sh |
| slot 実行モード | foreground / background / off | slot 系の現在状態として `mode=` に表示(`execution-spec.json` の `slots.<role>.mode`。節が無ければ off。可否判定は後半 UC) | tier-ops | abort-blue.sh / abort-green.sh |
| Runner Result 成果物種別 | started-at.txt / exitcode.txt / aborted.txt | slot 系の status 導出に使う(stdout.log / stderr.log は読まない) | tier-ops | repository `resolve_slot_state` |
| 速報クロスチェックモード | foreground / background | slot 系は成果物ファイルに加えて `slot_executions.pid` を表示に補う。依頼系(rapid)は管理 DB を参照できる | tier-ops | abort-blue.sh / abort-green.sh / abort-rapid-crosscheck.sh |
| 速報クロスチェックモード | off | slot 系は成果物ファイルだけで現在状態を表示する(`pid=-`)。abort-rapid-crosscheck は依頼レコードが無いため終了コード 3 | tier-ops | 同上 |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 停止確認応答 | 現在状態を表示した後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」を stderr へ出し stdin を 1 行読む。`yes`(完全一致)のみ肯定。それ以外は状態を変更せず終了コード 3。`--yes` は `yes` とみなしプロンプトを省略する。非 TTY で `--yes` なしは終了コード 2 | tier-ops | 4 スクリプト共通 presentation(`confirm_stop`)/ domain(`is_affirmative`) | no と答えると状態は変わらない / 非 TTY で --yes なし |
| CLI とメールによる提示 | 現在状態は stdout に `key=value` 固定順で出し、プロンプトは stderr に出す(stdout をパイプしても混ざらない)。UI 画面は提供しない | tier-ops | 4 スクリプト共通 presentation | 現在状態を表示して yes と答える |
| slot 実行の状態導出規則 | slot 系の現在状態は成果物ファイルから導出する: `exitcode.txt` があれば 0 = SUCCEEDED / 非 0 = FAILED、無く `aborted.txt` があれば ABORTED、どちらも無ければ RUNNING。`started-at.txt` が無ければ未起動(`status=-`)。両方あるときは exitcode.txt を優先する | tier-ops | repository `resolve_slot_state` / domain `AbortTargetState` | RAPID_CROSSCHECK_MODE=off でも成果物ファイルから現在状態を表示する / aborted.txt がある slot は ABORTED と表示する |
| 速報クロスチェック有効判定 | abort-blue / abort-green は RAPID_CROSSCHECK_MODE によらず成果物ファイルから現在状態を表示する(off 以外は `slot_executions.pid` を補う。off は `pid=-`)。abort-rapid-crosscheck は依頼レコードが管理 DB にしか無いため、off では管理 DB 接続前に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=...` で終了コード 3。abort-final-crosscheck は RAPID_CROSSCHECK_MODE を参照せず、`final-crosscheck.env` の FINAL_DB_CONN_REF の有無だけで管理 DB 有無を判定する(無ければ `error: management db is not configured run_id=...` で 3) | tier-ops | abort-blue.sh / abort-green.sh の pid 補完判定、abort-rapid-crosscheck.sh の管理 DB 接続前判定(abort-final-crosscheck.sh は final-crosscheck.env の読み取り) | RAPID_CROSSCHECK_MODE=off でも成果物ファイルから現在状態を表示する / off では速報比較依頼を中止できない / 確報の中止は速報モードに依存しない |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 停止確認応答の判定 | stdin 1 行 | 末尾改行を除去した文字列が `yes` と完全一致なら肯定、それ以外(空・`y`・`YES`・`no`)は否定 | answer(yes / no) | tier-ops |
| slot 系の現在状態 | `facade/<run_id>/execution-spec.json`、`facade/<run_id>/<role>/{started-at.txt, exitcode.txt, aborted.txt}` | mode = `slots.<role>.mode`(節なし → off)。status = 条件「slot 実行の状態導出規則」。started_at = started-at.txt の中身(UTC Z 付き)をホストのローカルタイムゾーンへ変換した値(指示子なし。無ければ `-`)。artifact_dir = `$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/<role>`。job_id = spec の `job_id` | 表示行 | tier-ops |
| 実行ログの answer 値 | `--yes` の有無、stdin | `--yes` なら `answer=yes(--yes)`、対話なら `answer=yes` / `answer=no` | 実行ログ | tier-ops |
| 指示者 | OS ユーザー名 | `operator=$(id -un)` | 実行ログ | tier-ops |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 該当なし(本 UC は状態を変更しない。yes 応答後の遷移は UC「実行を ABORTED へ遷移させる」に載せる) | — | — | — | — | — | — |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行復旧業務 | この UC が属する業務 |
| BUC | 実行中止フロー | この UC を含む BUC(アクティビティ: プロセス停止の確認) |
| アクター | 運用者 | 現在状態を見て停止確認に応答する(受益者) |
| 情報 | 中止指示 | run_id(--run-id)・中止対象種別・表示した現在状態・停止確認応答・指示者・指示日時(abort-blue / abort-green の yes 応答は対象 run の REQUESTED の速報比較依頼の中止(競合窓の保険)も含む。abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING、abort-final-crosscheck は RUNNING を中止対象とする。更新は後半 UC) |
| 情報 | slot 実行 | abort-blue / abort-green が表示する現在状態(mode / PID / 成果物ディレクトリ / 状態 / 開始時刻)。状態は成果物のファイル正本から導出する |
| 情報 | Runner Result | started-at.txt / exitcode.txt / aborted.txt の有無と値が slot 実行の状態の導出元(spec 参照。BUC.tsv 上の紐づけは後半 UC) |
| 情報 | 速報比較依頼(rapid_crosscheck_request) | abort-rapid-crosscheck が表示する現在状態(status / worker_id / lease_until) |
| 情報 | 確報比較依頼(final_crosscheck_request) | abort-final-crosscheck が表示する現在状態 |
| 情報 | 通知メール | 中止対象 run_id の特定元 |
| 条件 | 停止確認応答 | yes のときだけ後半へ進む |
| 条件 | CLI とメールによる提示 | stdout / stderr / 終了コードで提示 |
| 条件 | slot 実行の状態導出規則 | slot 系の現在状態の導出(spec 参照。BUC.tsv 上の紐づけは後半 UC) |
| 条件 | 速報クロスチェック有効判定 | off では slot 系は成果物ファイルだけで表示し、abort-rapid-crosscheck は管理 DB が無く終了コード 3(abort-final-crosscheck は対象外) |
| バリエーション | 速報クロスチェックモード | foreground / background は pid を管理 DB から補い、off は成果物ファイルだけで表示する |
| 画面 | abort 現在状態確認出力(→ CLI 出力: 4 スクリプトの stdout `key=value` と stderr プロンプト) | 運用者が読む出力 |
| イベント | 中止対象 run_id の特定 | 外部システム: ジョブスケジューラ(実行結果)/ 通知メール |
| イベント | 実行先ホストのプロセス停止確認 | 外部システム: リモート実行ホスト(SSH)。運用者が自身で行う(スクリプトは停止しない) |
| 外部システム | ジョブスケジューラ | run_id の特定元(実行結果・実行履歴) |
| 外部システム | リモート実行ホスト(SSH) | 運用者がプロセスを強制終了する対象 |
| 内部データストア | ジョブキュー兼管理 DB(RDB) | 依頼系の現在状態と slot 系の pid の参照先(BUC.tsv 上の紐づけは後半 UC 側) |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-010 | SPEC-010-01 | RAPID_CROSSCHECK_MODE=off でも成果物ファイルから現在状態を表示する(SPEC-010-01) / aborted.txt がある slot は ABORTED と表示する(SPEC-010-01) |
| REQ-010 | SPEC-010-03 | 現在状態を表示して yes と答える(SPEC-010-03) / no と答えると状態は変わらない(SPEC-010-03) |

> 機械可読の正本は `spec-event.yaml` の `use_cases[].usdm`(本表と同内容)。「対応 BDD Scenario」列は本 UC の `Scenario:` 名(接尾の SPEC ID を含む完全名)を「 / 」で区切って列挙し、Scenario 名以外の補足は「※」以降に置く。区切りは人が読む用で、Scenario 名自体に「 / 」を含むものがあるため機械分割には使わず、機械照合は `spec-event.yaml` の `scenarios[]` を使う。

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 現在状態を確認して停止確認に応答する

  Scenario: 現在状態を表示して yes と答える(SPEC-010-03)
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の job_id が JOB001、slots.green.mode が background である
    And facade/20260830T113000-JOB001-3f9a1c2e/green/started-at.txt の中身が 2026-08-30T11:30:05Z で、exitcode.txt と aborted.txt は無い
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green pid=12345 がある
    And 運用者 ops01 が green の実行プロセスを実行先ホストで強制終了した
    When 運用者が TTY から `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し、プロンプトに `yes` と入力する
    Then stdout の先頭 8 行が run_id=20260830T113000-JOB001-3f9a1c2e / job_id=JOB001 / role=green / mode=background / status=RUNNING / pid=12345 / started_at=2026-08-30T11:30:05 / artifact_dir: /var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green である
    And stderr に `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: ` が出る
    And UC「実行を ABORTED へ遷移させる」の処理へ進む
    And 実行ログ abort-green.sh.log に `operator=ops01 answer=yes run_id=20260830T113000-JOB001-3f9a1c2e role=green` を含む INFO 行が残る

  Scenario: RAPID_CROSSCHECK_MODE=off でも成果物ファイルから現在状態を表示する(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の job_id が JOB001、slots.blue.mode が background である
    And facade/20260830T113000-JOB001-3f9a1c2e/blue/started-at.txt の中身が 2026-08-30T11:30:05Z で、exitcode.txt と aborted.txt は無い
    When 運用者が TTY から `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行する
    Then stdout の先頭 8 行が run_id=20260830T113000-JOB001-3f9a1c2e / job_id=JOB001 / role=blue / mode=background / status=RUNNING / pid=- / started_at=2026-08-30T11:30:05 / artifact_dir: /var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/blue で、管理 DB への接続は行われない
    And stderr に `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: ` が出る

  Scenario: 速報比較依頼の現在状態を表示して --yes で確認を省略する
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 status=RUNNING worker_id=worker-01 lease_until=2026-08-30T12:10:00 started_at=2026-08-30T11:46:00 がある(日時はローカル時刻。TZ=UTC 前提)
    When ジョブスケジューラから非 TTY で `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then stdout の先頭 7 行が run_id=20260830T113000-JOB001-3f9a1c2e / job_id=JOB001 / role=rapid-crosscheck / status=RUNNING / worker_id=worker-01 / lease_until=2026-08-30T12:10:00 / started_at=2026-08-30T11:46:00 である
    And stderr にプロンプトは出ない
    And 実行ログに `answer=yes(--yes)` が残る

  Scenario: CLAIMED の速報比較依頼でも現在状態を表示して停止確認へ進む
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 status=CLAIMED worker_id=worker-01 lease_until=2026-08-30T12:10:00 started_at=NULL がある
    When 運用者が TTY から `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行する
    Then stdout の先頭 7 行が run_id=20260830T113000-JOB001-3f9a1c2e / job_id=JOB001 / role=rapid-crosscheck / status=CLAIMED / worker_id=worker-01 / lease_until=2026-08-30T12:10:00 / started_at=- である
    And stderr に `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: ` が出る(REQUESTED / CLAIMED / RUNNING のいずれでも省略しない)
```

### 異常系

```gherkin
  Scenario: no と答えると状態は変わらない(SPEC-010-03)
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background で、facade/20260830T113000-JOB001-3f9a1c2e/green/ に started-at.txt(2026-08-30T11:30:05Z)だけがある
    When 運用者が TTY から `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し、プロンプトに `no` と入力する
    Then 終了コード 3 で stdout の最終行が `status=RUNNING`、stderr に `info: aborted by operator; status not changed` が出る
    And facade/20260830T113000-JOB001-3f9a1c2e/green/aborted.txt は作成されず、slot_executions の status も RUNNING のままである

  Scenario: aborted.txt がある slot は ABORTED と表示する(SPEC-010-01)
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background で、facade/20260830T113000-JOB001-3f9a1c2e/green/ に started-at.txt と aborted.txt(中身 2026-08-30T12:40:00Z)があり exitcode.txt は無い
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then stdout の 5 行目が `status=ABORTED` であり、UC「実行を ABORTED へ遷移させる」が中止不可(既に中止済み)として終了コード 3 で終了する

  Scenario: 非 TTY で --yes なし
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background で green/ に started-at.txt だけがある
    When stdin を /dev/null にして `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行する
    Then 終了コード 2 で stderr に `error: interactive confirmation required (use --yes for non-interactive)` が出る
    And 状態は変更されない

  Scenario: 対象 run_id が存在しない
    Given facade/20260830T000000-JOB999-00000000/execution-spec.json が存在しない
    When `abort-blue.sh --run-id 20260830T000000-JOB999-00000000` を実行する
    Then 終了コード 3 で stderr に `error: run not found run_id=20260830T000000-JOB999-00000000 role=blue` が出る

  Scenario: off では速報比較依頼を中止できない
    Given RAPID_CROSSCHECK_MODE=off である
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=20260830T113000-JOB001-3f9a1c2e` が出て、管理 DB への接続は行われない

  Scenario: 確報の中止は速報モードに依存しない
    Given RAPID_CROSSCHECK_MODE=off で final-crosscheck.env に FINAL_DB_CONN_REF が設定され、final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=RUNNING がある
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 0 で stdout の先頭 4 行が run_id=20260830T020000-final-1a2b3c4d / job_id=- / role=final-crosscheck / status=RUNNING であり、stderr に `management db is not configured` は出ない
```

## ティア別仕様

- [tier-ops](tier-ops.md)(abort-* 4 スクリプト共通のコマンド契約: 引数・対話・終了コード)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(この UC は publish / subscribe しない)
