# 実行を ABORTED へ遷移させる

## 概要

停止確認に `yes` と応答されたとき(UC「現在状態を確認して停止確認に応答する」の後半)、`abort-blue.sh` / `abort-green.sh` は background かつ RUNNING(exitcode.txt も aborted.txt も無い)の slot 実行を中止する。中止の正本は成果物ディレクトリへの `aborted.txt`(中止日時 1 行)の書き込みであり、`.tmp` に書いてから `mv` で公開する。RAPID_CROSSCHECK_MODE が off 以外なら **加えて** 管理 DB の `slot_executions` を条件付き UPDATE で ABORTED にし、`parallel_runs` の行を無条件に `SELECT 1 ... FOR UPDATE` でロックしたうえで(dispatcher の FOR UPDATE との直列化。COMPLETED でも取る)、STARTED / RUNNING なら併せて ABORTED にする(COMPLETED は変更しない。更新 0 件で可)。さらに対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があれば、`rapid_crosscheck_requests` を条件付き UPDATE(`WHERE run_id = ? AND status = 'REQUESTED'`)で ABORTED にする(0 件は正常。競合窓の保険であり dispatcher 側の中止済み run 判定と併用する。CLAIMED / RUNNING の依頼は変更しない。確報比較依頼には適用しない。条件「slot 中止可否判定」)。off では管理 DB に触れず、aborted.txt だけで中止が成立し終了コード 0 で終わる。`abort-rapid-crosscheck.sh` は REQUESTED / CLAIMED / RUNNING の速報比較依頼を条件付き UPDATE(`status IN ('REQUESTED','CLAIMED','RUNNING')`)で ABORTED にし、`abort-final-crosscheck.sh` は RUNNING の確報比較依頼だけを条件付き UPDATE で ABORTED にする(依頼レコードは管理 DB にしか無い。条件「依頼中止可否判定」)。CLAIMED の速報比較依頼を中止すると、claim 済み worker の RUNNING への条件付き UPDATE が 0 件になり比較を開始しない。可否判定に合わない対象(foreground / off、速報比較依頼の終端状態、確報比較依頼の RUNNING 以外)は状態を変更せず終了コード 3 で終了する。スクリプト自身はプロセスを停止せず、状態更新だけを行い二重実行を防ぐ。ABORTED にした background slot 実行は、off でも background-rerun の対象になれる。

## データフロー

```mermaid
graph LR
  subgraph OPS["tier-ops"]
    OPS_Pres["presentation\nabort-* (yes 応答後)"]
    OPS_UC["usecase\nAbortExecutionCommand"]
    OPS_Domain["domain\nAbortEligibility\n(slot: mode x ファイル導出 status / 依頼: status)"]
    OPS_Repo["repository\nRunnerResultRepository / SlotExecutionRepository / CrosscheckRequestRepository / ParallelRunRepository"]
    OPS_GW["gateway\nファイルシステム(.tmp -> mv) / RDB クライアントアダプタ(条件付き UPDATE)"]
    OPS_Pres --> OPS_UC --> OPS_Domain
    OPS_UC --> OPS_Repo --> OPS_GW
  end
  subgraph FS["FS(成果物ディレクトリ。slot 中止の正本)"]
    FS_Art["facade/<run_id>/<role>/\nstarted-at.txt / exitcode.txt / aborted.txt(再確認)"]
    FS_Abort["facade/<run_id>/<role>/aborted.txt\n中止日時 1 行(.tmp -> mv)"]
  end
  subgraph DB["内部データストア: ジョブキュー兼管理 DB(RDB)"]
    DB_SE[("slot_executions\nstatus RUNNING -> ABORTED(off 以外)")]
    DB_RR[("rapid_crosscheck_requests\nstatus REQUESTED / CLAIMED / RUNNING -> ABORTED(abort-rapid-crosscheck)\nstatus REQUESTED -> ABORTED(abort-blue / abort-green。off 以外。競合窓の保険)")]
    DB_FR[("final_crosscheck_requests\nstatus RUNNING -> ABORTED")]
    DB_PR[("parallel_runs\nstatus STARTED / RUNNING -> ABORTED(off 以外)")]
  end
  subgraph LOG["FS(実行ログ)"]
    LOG_F["RELAY_GATE_LOG_DIR/abort-<role>.sh.log\noperator / answer / from / to"]
  end
  OPS_GW -->|"ファイル再確認(abort-blue / abort-green)"| FS_Art
  OPS_GW -->|"ファイル書き込み(abort-blue / abort-green)"| FS_Abort
  OPS_GW -->|"SQL: UPDATE ... WHERE run_id = ? AND slot = ? AND status = 'RUNNING'(off 以外)"| DB_SE
  OPS_GW -->|"SQL: UPDATE ... WHERE run_id = ? AND status IN ('REQUESTED','CLAIMED','RUNNING')(abort-rapid-crosscheck。0 件 = 終端済みで 3)"| DB_RR
  OPS_GW -->|"SQL: UPDATE ... WHERE run_id = ? AND status = 'REQUESTED'(abort-blue / abort-green。off 以外。0 件で可)"| DB_RR
  OPS_GW -->|"SQL: UPDATE ... WHERE final_crosscheck_id = ? AND status = 'RUNNING'"| DB_FR
  OPS_GW -->|"SQL: UPDATE ... WHERE run_id = ? AND status IN ('STARTED','RUNNING')"| DB_PR
  DB_SE -->|"更新件数"| OPS_GW --> OPS_Repo --> OPS_UC --> OPS_Pres
  OPS_UC -->|"ファイル書き込み(追記)"| LOG_F
  OPS_Pres -->|"stdout: status=ABORTED / aborted_at"| Operator["運用者"]
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| ops presentation | yes 応答(または `--yes`) | AbortExecutionCommand(run_id / kind / operator / answer) |
| ops domain | AbortEligibility: slot は `mode = background AND status = RUNNING`(status は条件「slot 実行の状態導出規則」でファイルから導出)、依頼はクロスチェック種別 × 依頼状態の判定表(速報 = `status IN (REQUESTED, CLAIMED, RUNNING)`、確報 = `status = RUNNING`) | 可否判定表(純粋関数。arch LP-019)。不可なら理由(mode / status)を返す |
| ops repository / gateway(slot) | 成果物再確認 → `aborted.txt` を `.tmp` → `mv` で公開 → (off 以外)`slot_executions` の条件付き UPDATE + `parallel_runs` の無条件行ロック(`SELECT 1 ... FOR UPDATE`)+ `parallel_runs` の UPDATE(`status IN ('STARTED','RUNNING')` のみ)+ `rapid_crosscheck_requests` の条件付き UPDATE(`status = 'REQUESTED'` のみ。未着手の速報比較依頼を ABORTED、completed_at=now) | ファイル正本の中止が成立すれば成功。slot_executions の UPDATE 0 件は `WARN management db not updated` を残して成功(0。ただし runner の終端 UPDATE が先に COMMIT 済みの場合は状態導出が exitcode.txt を優先するため中止は成立しない)、rapid_crosscheck_requests の UPDATE 0 件は正常(依頼が無い、または CLAIMED / RUNNING / 終端済み。ログなし)、DB 接続・SQL 失敗は 6(aborted.txt は残す) |
| ops repository / gateway(依頼) | 条件付き UPDATE(WHERE 句に現在状態を含める。速報は `status IN ('REQUESTED','CLAIMED','RUNNING')`、確報は `status = 'RUNNING'`)+ parallel_runs の UPDATE(`status IN ('STARTED','RUNNING')` のみ。速報のみ) | 対象の更新件数 1 で成功、0 は競合・不可(終端済み)として終了コード 3。parallel_runs の更新件数は 0 でも可(COMPLETED は変更しない) |
| ops usecase | 実行ログ行(`operator= answer= run_id= role= from={REQUESTED|CLAIMED|RUNNING} to=ABORTED`。from は表示時の現在状態。未着手の速報比較依頼を abort-blue / abort-green が ABORTED にしたときは加えて `INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=... answer=yes|yes(--yes)`(answer の表記は `status changed` 行と同じ規則)。0 件のときは出さない) | 監査用の記録(CLP-008) |
| ops presentation(出力) | `status=ABORTED`、`aborted_at={ローカル日時}`(aborted.txt の中止時刻(UTC Z 付き)をローカルタイムゾーンへ変換した同時刻。指示子なし) | 更新後状態の提示(off のときの表示元は成果物ファイル)。依頼の状態は出さない |

## 処理フロー

```mermaid
sequenceDiagram
  actor Ops as 運用者
  box rgb(240,255,240) tier-ops
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(成果物ディレクトリ)
  participant DB as 管理 DB(RDB)
  participant LOG as FS(実行ログ)

  Ops->>Pres: (前半で現在状態を表示し yes と応答済み)
  Pres->>UC: AbortExecutionCommand(run_id, kind, operator=ops01, answer=yes)
  alt slot(abort-blue / abort-green)
    UC->>Repo: 成果物再確認(started-at.txt / exitcode.txt / aborted.txt)
    Repo->>GW: read facade/<run_id>/<role>/
    GW->>FS: 有無
    UC->>Domain: 中止可否判定(mode, 導出 status)
    alt mode != background または status != RUNNING
      Domain-->>UC: 不可(理由)
      UC->>LOG: INFO abort rejected reason=mode|status mode=... status=...
      Pres-->>Ops: stderr error: run is not abortable run_id=... role=blue mode=foreground status=RUNNING / 終了コード 3(状態不変)
    else 表示後に exitcode.txt / aborted.txt が出現した(競合)
      Pres-->>Ops: stderr error: run is not abortable (state changed concurrently) run_id=... role=green / 終了コード 3
    else 可
      UC->>Repo: aborted.txt を書く
      Repo->>GW: write aborted.txt.tmp(中止日時 1 行)→ mv aborted.txt
      GW->>FS: 公開
      opt RAPID_CROSSCHECK_MODE が off 以外
        UC->>Repo: 管理 DB を ABORTED へ更新
        Repo->>GW: UPDATE slot_executions ... WHERE run_id=? AND slot=? AND status='RUNNING'
        GW->>DB: SQL(1 トランザクション)
        Repo->>GW: SELECT 1 FROM parallel_runs WHERE run_id=? FOR UPDATE
        GW->>DB: SQL(同一トランザクション。無条件の行ロック。dispatcher の FOR UPDATE と直列化。COMPLETED でも取る)
        Repo->>GW: UPDATE parallel_runs ... WHERE run_id=? AND status IN ('STARTED','RUNNING')
        GW->>DB: SQL(同一トランザクション。COMPLETED は更新しないため 0 でも可)
        Repo->>GW: UPDATE rapid_crosscheck_requests SET status='ABORTED', completed_at=now WHERE run_id=? AND status='REQUESTED'
        GW->>DB: SQL(同一トランザクション。未着手の速報比較依頼だけ。0 件は正常(依頼なし / CLAIMED / RUNNING / 終端済み)。COMMIT)
        opt rapid_crosscheck_requests の更新件数 1
          UC->>LOG: INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=ops01 answer=yes
        end
        alt slot_executions の更新件数 0(管理 DB 側が既に終端・中止済み)
          UC->>LOG: WARN management db not updated run_id=... role=...
        else 接続・SQL 失敗
          Pres-->>Ops: stderr error: management db update failed ... / hint: rerun abort-<role>.sh --run-id ... to reapply / 終了コード 6(aborted.txt は残す)
        end
      end
      UC->>LOG: INFO status changed from=RUNNING to=ABORTED operator=ops01 answer=yes run_id=... role=green
      Pres-->>Ops: stdout status=ABORTED / aborted_at=2026-08-30T12:40:00 / 終了コード 0
    end
  else 依頼(abort-rapid-crosscheck / abort-final-crosscheck)
    UC->>Domain: 中止可否判定(クロスチェック種別 × 現在状態。速報: REQUESTED / CLAIMED / RUNNING = 可、確報: RUNNING のみ可)
    alt 不可(速報: SUCCEEDED / FAILED / ABORTED の終端状態。確報: RUNNING 以外)
      Domain-->>UC: 不可(理由)
      Pres-->>Ops: stderr error: request is not abortable run_id=... role=... status=... / 終了コード 3(状態不変)
    else 可
      alt abort-rapid-crosscheck(速報)
        Repo->>GW: UPDATE rapid_crosscheck_requests SET status='ABORTED', completed_at=now WHERE run_id=? AND status IN ('REQUESTED','CLAIMED','RUNNING')
      else abort-final-crosscheck(確報)
        Repo->>GW: UPDATE final_crosscheck_requests SET status='ABORTED', completed_at=now WHERE final_crosscheck_id=? AND status='RUNNING'
      end
      GW->>DB: SQL(1 トランザクション)
      DB-->>GW: 更新件数
      alt 更新件数 0(表示後に終端した競合)
        UC->>LOG: WARN abort conflict updated_rows=0
        Pres-->>Ops: stderr error: request is not abortable (state changed concurrently) run_id=... / 終了コード 3
      else 更新件数 1
        Repo->>GW: UPDATE parallel_runs SET status='ABORTED', completed_at=now WHERE run_id=? AND status IN ('STARTED','RUNNING')(rapid のみ。0 件で可)
        GW->>DB: SQL(同一トランザクション。COMMIT)
        UC->>LOG: INFO status changed from={REQUESTED|CLAIMED|RUNNING} to=ABORTED operator=ops01 answer=yes run_id=... role=rapid-crosscheck
        Pres-->>Ops: stdout status=ABORTED / aborted_at=... / 終了コード 0
      end
      Note over DB: CLAIMED を中止した場合、claim 済み worker の RUNNING への条件付き UPDATE(status='CLAIMED' AND worker_id=?)は 0 件になり比較を開始しない(他 UC)
    end
  end
  Note over Pres,DB: スクリプトはプロセス・Pod・SSH 接続先の処理を停止しない
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 中止対象種別 | background slot 実行 | `facade/<run_id>/<role>/aborted.txt` を `.tmp` → `mv` で書く。off 以外は加えて `slot_executions` を `WHERE run_id = ? AND slot = ? AND status = 'RUNNING'` で ABORTED にし、対象 run の未着手の速報比較依頼を `rapid_crosscheck_requests` の `WHERE run_id = ? AND status = 'REQUESTED'` で ABORTED にする(0 件で可) | tier-ops | abort-blue.sh / abort-green.sh |
| 中止対象種別 | 速報比較依頼 | `rapid_crosscheck_requests` を `UPDATE ... SET status='ABORTED', completed_at=? WHERE run_id = ? AND status IN ('REQUESTED','CLAIMED','RUNNING')` で ABORTED(REQUESTED / CLAIMED / RUNNING のいずれからでも中止できる。CLAIMED / RUNNING の依頼の中止経路は本スクリプトのみ。更新件数 0 = 終端済みで 3) | tier-ops | abort-rapid-crosscheck.sh |
| 中止対象種別 | 確報比較依頼 | `final_crosscheck_requests` を `WHERE final_crosscheck_id = ? AND status = 'RUNNING'` で ABORTED(RUNNING のみ。REQUESTED / CLAIMED / 終端は状態を変更せず 3) | tier-ops | abort-final-crosscheck.sh |
| slot 実行モード | background | 中止可(ファイル導出 status = RUNNING のとき) | tier-ops | domain `is_slot_abortable` |
| slot 実行モード | foreground | 中止不可(ジョブスケジューラ側で扱う)。終了コード 3 | tier-ops | domain `is_slot_abortable` |
| slot 実行モード | off | 中止不可(`execution-spec.json` に `slots.<role>` 節が無く slot 実行が存在しない)。終了コード 3 | tier-ops | domain `is_slot_abortable` |
| 速報クロスチェックモード | foreground / background | aborted.txt を書いたうえで管理 DB(slot_executions / parallel_runs / REQUESTED の rapid_crosscheck_requests)も ABORTED にする | tier-ops | usecase(slot 系) |
| 速報クロスチェックモード | off | aborted.txt だけで中止が成立し終了コード 0。管理 DB に触れない。abort-rapid-crosscheck は前半 UC で 3 | tier-ops | usecase(slot 系) |
| Runner Result 成果物種別 | aborted.txt | 中止時のみ abort-blue / abort-green が生成する(中止日時 1 行。UTC ISO 8601 秒精度 Z 付き) | tier-ops | gateway(ファイル書き込み) |
| Runner Result 成果物種別 | exitcode.txt | 既にあれば終端済み(SUCCEEDED / FAILED)として中止不可。aborted.txt と両方あるときは exitcode.txt を優先する | tier-ops | domain `is_slot_abortable` |
| クロスチェック依頼状態 | REQUESTED / CLAIMED / RUNNING | 中止可(abort-rapid-crosscheck。速報比較依頼)。RUNNING は abort-final-crosscheck(確報比較依頼)でも中止可 | tier-ops | domain `is_request_abortable` |
| クロスチェック依頼状態 | SUCCEEDED / FAILED / ABORTED | abort-rapid-crosscheck / abort-final-crosscheck では中止不可(終端済み)。状態を変更せず終了コード 3 | tier-ops | domain `is_request_abortable` |
| クロスチェック依頼状態 | REQUESTED / CLAIMED(確報のみ) | abort-final-crosscheck では中止不可(ジョブスケジューラの正規ジョブが同期 polling 中。runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う)。状態を変更せず終了コード 3 | tier-ops | domain `is_request_abortable` |
| クロスチェック依頼状態 | REQUESTED(速報のみ) | abort-blue / abort-green の slot 中止に伴い、対象 run の未着手依頼を条件付き UPDATE で ABORTED にする(off 以外。0 件で可。競合窓の保険。依頼の状態は stdout に出さない) | tier-ops | usecase(slot 系)/ gateway の UPDATE WHERE 句 |
| 実装スロット | blue / green | 対象成果物ディレクトリ(`facade/<run_id>/<role>/`)と slot 列(`slot = ?`)をスクリプト名で確定 | tier-ops | abort-blue.sh / abort-green.sh |
| 停止確認応答 | yes | 本 UC の入口条件 | tier-ops | 前半 UC から引き継ぐ |
| クロスチェック種別 | 速報クロスチェック / 確報クロスチェック | テーブルとキー列が異なる(run_id / final_crosscheck_id) | tier-ops | abort-rapid-crosscheck.sh / abort-final-crosscheck.sh |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| slot 中止可否判定 | 縦軸 mode(foreground / background / off)× 横軸 status(RUNNING / SUCCEEDED / FAILED / ABORTED)。`background × RUNNING` のみ可。他は状態を変更せず終了コード 3。中止の記録は `aborted.txt`(ファイル正本)で行い、RAPID_CROSSCHECK_MODE が off 以外なら管理 DB の状態も ABORTED に更新する。off でも成果物ファイルだけで中止が成立する。yes で slot を ABORTED にするとき、対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があればそれも ABORTED にする(off 以外。条件付き UPDATE `status = 'REQUESTED'`。0 件は正常)。この REQUESTED → ABORTED は競合窓の保険である(状態「クロスチェック依頼」REQUESTED → ABORTED): 両系の完了通知で速報比較依頼が REQUESTED で作成された直後に運用者が slot を中止した場合の競合窓を塞ぐ。dispatcher 側の中止済み run 判定(UC「両系成功時に速報比較依頼を作成する」の条件「中止済み run の比較依頼作成除外」。並行稼働実行 ABORTED または完了通知の対象 slot の slot 実行 ABORTED を判定キーに含む)と併用する。dispatcher は parallel_runs を FOR UPDATE で読み、本スクリプトも parallel_runs の行を無条件に `SELECT 1 ... FOR UPDATE` でロックしてから条件付き UPDATE に進むため、parallel_runs が COMPLETED でも両者は直列化され、dispatcher が先に COMMIT した依頼を本 UPDATE が拾う(ロック順は slot_executions → parallel_runs(FOR UPDATE)→ parallel_runs 条件付き UPDATE → rapid_crosscheck_requests 条件付き UPDATE)。CLAIMED / RUNNING の依頼は本スクリプトでは変更しない。REQUESTED / CLAIMED / RUNNING の速報比較依頼の明示中止は abort-rapid-crosscheck(条件「依頼中止可否判定」。status IN 条件付き UPDATE)で行う。CLAIMED のまま残すと lease 失効で REQUESTED に戻り再 claim されるため、中止済み run の依頼は abort-rapid-crosscheck で止める | tier-ops | domain `is_slot_abortable`、gateway のファイル書き込みと UPDATE WHERE 句 | background かつ RUNNING の green を中止する / foreground の blue は中止できない / RAPID_CROSSCHECK_MODE=off でも aborted.txt を書いて中止が成立する / REQUESTED の速報比較依頼がある run を中止すると依頼も ABORTED になる / 依頼作成直後に slot を中止すると依頼も ABORTED になり完了通知で再作成されない / CLAIMED または RUNNING の速報比較依頼は slot の中止では変更されない |
| slot 実行の状態導出規則 | 可否判定の status は成果物ファイルから導出する: `exitcode.txt` があれば 0 = SUCCEEDED / 非 0 = FAILED、無く `aborted.txt` があれば ABORTED、どちらも無ければ RUNNING(両方あれば exitcode.txt 優先)。yes 応答直後に再確認し、表示後に終端・中止済みになっていれば競合として 3。RAPID_CROSSCHECK_MODE が off 以外では管理 DB の slot_executions.status を条件付き UPDATE(WHERE status='RUNNING')で一度だけ ABORTED にし、その後に実装が走り切って exitcode.txt を公開しても管理 DB は ABORTED のまま残す(ファイル正本の導出値へ再同期しない) | tier-ops | repository `resolve_slot_state`(前半と共通)/ usecase の再確認 | 直前に完了した slot への中止は競合として拒否する / 既に ABORTED の slot への再実行は中止不可として拒否する |
| 依頼中止可否判定 | 縦軸クロスチェック種別(速報 / 確報)× 横軸依頼状態(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)の判定表(arch LP-019)。速報 × REQUESTED / CLAIMED / RUNNING = 中止可(abort-rapid-crosscheck。停止確認 yes 後に `status IN ('REQUESTED','CLAIMED','RUNNING')` の条件付き UPDATE)。速報 × SUCCEEDED / FAILED / ABORTED = 不可(状態を変更せず 3)。確報 × RUNNING = 中止可(abort-final-crosscheck)。確報 × REQUESTED / CLAIMED / 終端 = 不可(状態を変更せず 3。確報の未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う)。REQUESTED の速報比較依頼には worker プロセスが無いが停止確認は省略しない。CLAIMED の速報比較依頼を中止すると claim 済み worker の RUNNING への条件付き UPDATE が 0 件になり比較を開始しない(競合規則。UC「比較ツールでジョブ単位比較を実行して結果を登録する」) | tier-ops | domain `is_request_abortable`、gateway の UPDATE WHERE 句 | RUNNING の速報比較依頼を中止する / REQUESTED または CLAIMED の速報比較依頼を中止すると worker は比較を開始しない / 終端状態の速報比較依頼は状態を変更せずエラー終了する / RUNNING でない確報比較依頼は状態を変更せずエラー終了する |
| 停止確認応答 | `yes` のときだけ本 UC を実行する。yes 以外は前半 UC で終了 | tier-ops | 前半 UC の `confirm_stop` | background かつ RUNNING の green を中止する |
| 依頼状態遷移規則 | 停止確認後の中止で ABORTED に遷移する。本 UC の遷移は REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck。速報比較依頼のみ)/ RUNNING → ABORTED(abort-final-crosscheck。確報比較依頼のみ)/ REQUESTED → ABORTED(abort-blue / abort-green。競合窓の保険。速報比較依頼のみ) | tier-ops | domain `is_request_abortable`、usecase(slot 系)の依頼 UPDATE | RUNNING の速報比較依頼を中止する / REQUESTED または CLAIMED の速報比較依頼を中止すると worker は比較を開始しない / REQUESTED の速報比較依頼がある run を中止すると依頼も ABORTED になる |
| 速報クロスチェック有効判定 | abort-blue / abort-green: off 以外は aborted.txt に加えて `slot_executions` / `parallel_runs` / `rapid_crosscheck_requests`(REQUESTED のみ)を条件付き UPDATE する。off は管理 DB に触れず aborted.txt だけで終了コード 0。abort-rapid-crosscheck: 依頼が管理 DB にしか無いため off では前半 UC で 3。abort-final-crosscheck は RAPID_CROSSCHECK_MODE を参照しない(管理 DB 有無は final-crosscheck.env の FINAL_DB_CONN_REF のみ) | tier-ops | usecase の管理 DB 更新の要否判定 | RAPID_CROSSCHECK_MODE=off でも aborted.txt を書いて中止が成立する / background かつ RUNNING の green を中止する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| aborted_at | now(テスト時は `RELAY_GATE_NOW`) | 中止時刻は 1 回の実行で 1 つ。`aborted.txt` の中身(1 行)は UTC ISO 8601 秒精度 Z 付き(Runner Result Contract)。`slot_executions.completed_at` / 依頼の `completed_at` / `parallel_runs.completed_at`(off 以外)と stdout の `aborted_at` には同時刻をホストのローカルタイムゾーン(ISO 8601 秒精度、指示子なし)へ変換して書く。テスト専用環境変数 `RELAY_GATE_NOW`(UTC ISO 8601 Z 付き。本番では未設定)が設定されていれば now() の代わりにその値を使い、内部でローカル時刻へ変換する(BDD の絶対時刻はこの変数を Given に置いて固定する。例示は TZ=UTC 前提) | aborted_at | tier-ops |
| aborted.txt の公開 | aborted_at | `facade/<run_id>/<role>/aborted.txt.tmp` に書いてから `mv` で `aborted.txt` に確定する(書き込み途中の読み取りを防ぐ。条件「成果物公開判定」と同じ規則) | aborted.txt | tier-ops |
| 更新件数判定(slot、off 以外) | UPDATE の影響行数 | 1 → 成功、0 → 管理 DB 側が既に終端・中止済み(`WARN management db not updated ...` を残し終了コード 0。aborted.txt は公開済み。ただし runner の終端 UPDATE が先に COMMIT 済みの場合は状態導出が exitcode.txt を優先するため中止は成立しない。再確認は abort-<role>.sh の現在状態表示(ファイル正本から導出))、2 以上 → 内部エラー(終了コード 6。主キー条件で起こり得ない) | 終了コード | tier-ops |
| 更新件数判定(依頼) | UPDATE の影響行数(速報: `status IN ('REQUESTED','CLAIMED','RUNNING')`、確報: `status = 'RUNNING'`) | 1 → 成功、0 → 表示後に終端した競合(終了コード 3。状態不変)、2 以上 → 内部エラー(終了コード 6) | 終了コード | tier-ops |
| 更新件数判定(未着手の速報比較依頼。slot 系、off 以外) | `rapid_crosscheck_requests` の `WHERE run_id = ? AND status = 'REQUESTED'` UPDATE の影響行数 | 1 → 実行ログに `INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=... answer=yes|yes(--yes)`(answer の表記は `status changed` 行と同じ規則。`--verbose` 時は stderr に `info: rapid request aborted run_id=...`)、0 → 正常(依頼が無い、または CLAIMED / RUNNING / 終端済み。ログを出さない)、2 以上 → 内部エラー(終了コード 6。主キー条件で起こり得ない)。終了コードには影響しない | 実行ログ | tier-ops |
| 再適用の判定(slot) | aborted.txt の有無、管理 DB の status | aborted.txt があり、RAPID_CROSSCHECK_MODE が off 以外で `slot_executions.status` が RUNNING(または `parallel_runs` が STARTED / RUNNING)のまま → aborted.txt を書き直さず管理 DB だけ更新し(未着手の速報比較依頼の条件付き UPDATE も同じく試みる。0 件で可)、stdout `status=ABORTED` / stderr `warn: aborted.txt already published; management db updated` で 0。aborted.txt があり管理 DB も更新済み(または off)→ 3(`error: run is not abortable ... status=ABORTED`) | 終了コード | tier-ops |
| 状態遷移の表示 | 旧状態・新状態 | 実行ログに `from=RUNNING to=ABORTED`(slot / 確報比較依頼)。abort-rapid-crosscheck は表示時の現在状態を from に書く(`from=REQUESTED|CLAIMED|RUNNING to=ABORTED`)。abort-blue / abort-green が未着手の速報比較依頼を併せて ABORTED にしたときは `INFO rapid request aborted ... from=REQUESTED to=ABORTED` | 実行ログ | tier-ops |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| slot 実行 | RUNNING | ABORTED | abort-blue.sh / abort-green.sh に yes と応答 | mode = background かつ status = RUNNING(exitcode.txt も aborted.txt も無い)。運用者がプロセス停止を確認済み | `aborted.txt`(中止日時 1 行)を .tmp → mv で公開。RAPID_CROSSCHECK_MODE が off 以外なら slot_executions.completed_at を記録し、parallel_run が STARTED / RUNNING なら併せて ABORTED。実行ログに operator / answer / from / to | tier-ops |
| クロスチェック依頼(速報) | RUNNING | ABORTED | abort-rapid-crosscheck.sh に yes と応答(速報) | rapid_crosscheck_requests.status = RUNNING。worker プロセスの停止を確認済み | 条件付き UPDATE `WHERE run_id = ? AND status IN ('REQUESTED','CLAIMED','RUNNING')` で completed_at 記録。parallel_run が STARTED / RUNNING なら併せて ABORTED(通常 run は foreground 中継完了で COMPLETED 済みのため変更しない)。比較中の worker は終端 UPDATE が 0 件になり comparison_results を INSERT しない(他 UC)。ハング検知はこの遷移を行わない | tier-ops |
| クロスチェック依頼(速報) | CLAIMED | ABORTED | abort-rapid-crosscheck.sh に yes と応答(速報。claim 済み速報比較依頼の中止) | rapid_crosscheck_requests.status = CLAIMED。worker プロセスの停止を確認済み(停止確認は省略しない) | 同じ条件付き UPDATE(`status IN ('REQUESTED','CLAIMED','RUNNING')`)で completed_at 記録。claim 済み worker は RUNNING への条件付き UPDATE(`status='CLAIMED' AND worker_id=?`)が 0 件になり比較を開始しない(条件「依頼中止可否判定」)。CLAIMED のまま残すと lease 失効で REQUESTED に戻り別 worker が再 claim して比較が実行されるため、中止済み run の依頼は本コマンドで止める。parallel_run の併更新は RUNNING → ABORTED と同じ。実行ログに `from=CLAIMED to=ABORTED` | tier-ops |
| クロスチェック依頼(速報) | REQUESTED | ABORTED | abort-rapid-crosscheck.sh に yes と応答(速報。未着手依頼の明示中止)/ abort-blue.sh / abort-green.sh に yes と応答(slot の中止に伴う競合窓の保険。速報比較依頼のみ。確報比較依頼には適用しない) | abort-rapid-crosscheck: rapid_crosscheck_requests.status = REQUESTED(worker プロセスは無いが停止確認は省略しない)。abort-blue / abort-green: 対象 run に status = REQUESTED(worker が claim していない未着手)の速報比較依頼がある。RAPID_CROSSCHECK_MODE が off 以外 | abort-rapid-crosscheck は `status IN ('REQUESTED','CLAIMED','RUNNING')` の条件付き UPDATE(0 件 = 終端済みで 3)。abort-blue / abort-green は条件付き UPDATE `WHERE run_id = ? AND status = 'REQUESTED'` で completed_at 記録(0 件は正常: 依頼なし / CLAIMED / RUNNING / 終端済み。CLAIMED / RUNNING の依頼は変更しない)。abort-blue / abort-green の本遷移は、両系の完了通知で依頼が REQUESTED で作成された直後に slot を中止した場合の競合窓を塞ぐ保険であり、dispatcher 側の中止済み run 判定(条件「中止済み run の比較依頼作成除外」)と併用する。実行ログに `from=REQUESTED to=ABORTED` | tier-ops |
| クロスチェック依頼(確報) | RUNNING | ABORTED | abort-final-crosscheck.sh に yes と応答(確報。RUNNING のみ) | final_crosscheck_requests.status = RUNNING。REQUESTED / CLAIMED / 終端の確報比較依頼は状態を変更せず 3(未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中で、runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う) | 条件付き UPDATE `WHERE final_crosscheck_id = ? AND status = 'RUNNING'` で completed_at 記録。polling 中の final runner は終端状態として検知し保存済み結果を中継する(他 UC) | tier-ops |
| 並行稼働実行 | STARTED | ABORTED | slot 実行または速報比較依頼の明示中止(facade / background-rerun が STARTED で作成した直後、RUNNING 更新前) | parallel_runs.status が STARTED。RAPID_CROSSCHECK_MODE が off 以外 | completed_at 記録。STARTED のまま残る実行を取りこぼさない | tier-ops |
| 並行稼働実行 | RUNNING | ABORTED | slot 実行または速報比較依頼の明示中止 | parallel_runs.status が RUNNING。RAPID_CROSSCHECK_MODE が off 以外。**COMPLETED の parallel_runs は更新しない(更新 0 件で可)** | completed_at 記録。リラン時は新 run_id の parent_run_id で追跡 | tier-ops |

運用注記(UC「速報比較依頼だけを新規作成する」と共通):

- 通常 run の速報比較依頼を `abort-rapid-crosscheck.sh` で中止するとき(REQUESTED / CLAIMED / RUNNING のいずれでも)、parallel_runs は foreground 中継完了で既に COMPLETED になっているため併更新は 0 件となり、COMPLETED のまま残る
- `background-rerun.sh --role rapid-crosscheck` で作られた run の parallel_runs は、依頼が終端(SUCCEEDED / FAILED)した時点で速報クロスチェック worker が COMPLETED にする(状態「並行稼働実行」RUNNING → COMPLETED、遷移 UC「比較ツールでジョブ単位比較を実行して結果を登録する」)。依頼が RUNNING の間に `abort-rapid-crosscheck.sh` で中止した場合は、併更新で parallel_runs も ABORTED になる
- `background-rerun.sh --role blue|green` で作られた run の parallel_runs は、background slot の終端(exitcode.txt 公開)時に slot runner が COMPLETED にする(遷移 UC「実装スクリプトを実行して Runner Result を出力する」)。slot が RUNNING の間に `abort-<role>.sh` で中止した場合は、併更新で parallel_runs も ABORTED になる

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行復旧業務 | この UC が属する業務 |
| BUC | 実行中止フロー | この UC を含む BUC(アクティビティ: 実行状態の中止更新) |
| アクター | 運用者 | 中止スクリプトに yes と応答する(受益者) |
| 情報 | 中止指示 | run_id・中止対象種別・停止確認応答・指示者・更新後状態(ABORTED)。中止対象は background slot 実行、REQUESTED / CLAIMED / RUNNING の速報比較依頼(abort-rapid-crosscheck)、RUNNING の確報比較依頼(abort-final-crosscheck)。abort-blue / abort-green は対象 run の REQUESTED の速報比較依頼も ABORTED にする(競合窓の保険) |
| 情報 | slot 実行 | RUNNING → ABORTED の更新対象(状態はファイル正本から導出) |
| 情報 | Runner Result | 中止時のみ `aborted.txt`(中止日時 1 行)を成果物ディレクトリに生成する。RAPID_CROSSCHECK_MODE=off でも中止を記録できる |
| 情報 | 速報比較依頼(rapid_crosscheck_request) | REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck。CLAIMED 中止後は worker が比較を開始しない)/ REQUESTED → ABORTED(abort-blue / abort-green による未着手依頼の中止。競合窓の保険)の更新対象 |
| 情報 | 確報比較依頼(final_crosscheck_request) | RUNNING → ABORTED の更新対象(RUNNING のみ) |
| 情報 | 並行稼働実行(parallel_run) | 併せて ABORTED にする(off 以外) |
| 情報 | 実行ログ | 指示者・応答・遷移を記録する |
| 状態 | slot 実行 | RUNNING → ABORTED(aborted.txt の書き込みと off 以外での管理 DB 更新) |
| 状態 | クロスチェック依頼 | REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck。速報比較依頼のみ。CLAIMED → ABORTED は本 UC が遷移 UC)/ RUNNING → ABORTED(abort-final-crosscheck。確報比較依頼のみ)/ REQUESTED → ABORTED(abort-blue / abort-green。競合窓の保険。速報比較依頼のみ) |
| 状態 | 並行稼働実行 | STARTED → ABORTED / RUNNING → ABORTED |
| 条件 | slot 中止可否判定 | background × RUNNING のみ可。記録先は aborted.txt、off 以外は管理 DB も更新。対象 run の REQUESTED の速報比較依頼も ABORTED にする(競合窓の保険。dispatcher 側の中止済み run 判定と併用。CLAIMED / RUNNING は変更せず、明示中止は abort-rapid-crosscheck) |
| 条件 | slot 実行の状態導出規則 | 可否判定の status をファイルから導出する |
| 条件 | 依頼中止可否判定 | クロスチェック種別 × 依頼状態の判定表。速報 = REQUESTED / CLAIMED / RUNNING 可(status IN 条件付き UPDATE)、確報 = RUNNING のみ可。中止できない状態は状態を変更せず 3。CLAIMED 中止時の競合規則(worker は RUNNING への条件付き UPDATE 0 件で比較を開始しない) |
| 条件 | 停止確認応答 | yes のときだけ更新(REQUESTED の依頼でも省略しない) |
| 条件 | 依頼状態遷移規則 | 停止確認後の中止で ABORTED(速報は REQUESTED / CLAIMED / RUNNING から、確報は RUNNING から。abort-blue / abort-green は未着手の速報比較依頼を REQUESTED から) |
| 条件 | 速報クロスチェック有効判定 | off では管理 DB に触れず aborted.txt だけで中止が成立する。off 以外は管理 DB も更新する |
| 条件 | 監視は通知のみ | ハング検知はこの遷移を行わない(明示中止だけが ABORTED にする) |
| バリエーション | Runner Result 成果物種別 | aborted.txt(中止時のみ生成) |
| バリエーション | 速報クロスチェックモード | foreground / background は管理 DB も更新、off は aborted.txt のみ |
| 画面 | abort 状態更新出力(→ CLI 出力: `status=ABORTED` / `aborted_at=`) | 運用者が読む出力 |
| イベント | 中止スクリプトの起動 | 外部システム: ジョブスケジューラ(`--yes` 付き非対話起動の経路) |
| 外部システム | ジョブスケジューラ | 非対話起動の経路(`--yes`) |
| 内部データストア | ジョブキュー兼管理 DB(RDB) | 条件付き UPDATE の対象(slot 系は off 以外のみ。依頼系は常に) |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-010 | SPEC-010-01 | 受け入れ条件 8 件: background かつ RUNNING の green を中止する(SPEC-010-01 / SPEC-010-03)(AC1 / AC5) / foreground の blue は中止できない(SPEC-010-01)(AC2) / RAPID_CROSSCHECK_MODE=off でも aborted.txt を書いて中止が成立する(SPEC-010-01)(AC3) / 既に ABORTED の slot への再実行は中止不可として拒否する(SPEC-010-01)(AC4。導出 ABORTED。ハング検知側の終端は UC「background 実行の経過時間と終了状態を判定する」) / REQUESTED の速報比較依頼がある run を中止すると依頼も ABORTED になる(SPEC-010-01)(AC6) / CLAIMED または RUNNING の速報比較依頼は slot の中止では変更されない(SPEC-010-01)(AC7) / 依頼作成直後に slot を中止すると依頼も ABORTED になり完了通知で再作成されない(SPEC-010-01)(AC8) |
| REQ-010 | SPEC-010-02 | 受け入れ条件 5 件: RUNNING の速報比較依頼を中止する(SPEC-010-02)(AC1) / REQUESTED または CLAIMED の速報比較依頼を中止すると worker は比較を開始しない(SPEC-010-02)(AC2) / 終端状態の速報比較依頼は状態を変更せずエラー終了する(SPEC-010-02)(AC4) / RUNNING でない確報比較依頼は状態を変更せずエラー終了する(SPEC-010-02)(AC5)。AC3(worker 側の RUNNING 条件付き UPDATE 0 件)は UC「比較ツールでジョブ単位比較を実行して結果を登録する」 |
| REQ-010 | SPEC-010-03 | background かつ RUNNING の green を中止する(SPEC-010-01 / SPEC-010-03)(プロセスを停止せず状態だけを更新する) |
| REQ-011 | SPEC-011-06 | STARTED のまま残った parallel_runs も slot の中止に伴い ABORTED になる(SPEC-011-06) |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 実行を ABORTED へ遷移させる

  Scenario: background かつ RUNNING の green を中止する(SPEC-010-01 / SPEC-010-03)
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background、green/ に started-at.txt だけがある(exitcode.txt / aborted.txt なし)
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green mode=background status=RUNNING pid=12345 があり、parallel_runs の同 run_id の status が RUNNING である
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    And 運用者 ops01 が PID 12345 の処理を実行先ホストで強制終了した
    When 運用者が `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行しプロンプトに `yes` と入力する
    Then 終了コード 0 で stdout の末尾 2 行が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` である
    And facade/20260830T113000-JOB001-3f9a1c2e/green/aborted.txt が存在し中身が `2026-08-30T12:40:00Z` の 1 行で、aborted.txt.tmp は残っていない
    And slot_executions の同行の status が ABORTED、completed_at が 2026-08-30T12:40:00(ローカル時刻。TZ=UTC 前提)である
    And parallel_runs の同 run_id の status が ABORTED である
    And 実行ログ abort-green.sh.log に `INFO status changed from=RUNNING to=ABORTED operator=ops01 answer=yes run_id=20260830T113000-JOB001-3f9a1c2e role=green` が残る
    And スクリプトは PID 12345 に対してシグナルを送っていない

  Scenario: REQUESTED の速報比較依頼がある run を中止すると依頼も ABORTED になる(SPEC-010-01)
    # 競合窓の保険: 両系の完了通知で依頼が REQUESTED で作成された直後に slot を中止した競合窓を塞ぐ。dispatcher 側の中止済み run 判定と併用する
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background、green slot が RUNNING(green/ に started-at.txt あり・exitcode.txt なし・aborted.txt なし)である
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green mode=background status=RUNNING があり、parallel_runs の同 run_id の status が RUNNING である
    And その run に rapid_crosscheck_requests の status=REQUESTED worker_id=NULL の速報比較依頼がある(dispatcher が中止直前に作成した競合ケース。成果物再確認の後に green の exitcode.txt 公開と dispatcher の COMMIT が割り込んだ状態を DB に再現する)
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When 運用者 ops01 が `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行しプロンプトに `yes` と入力する
    Then 終了コード 0 で stdout の末尾 2 行が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` であり、依頼の状態は stdout に出ない
    And green/aborted.txt が公開され、slot_executions の同行と parallel_runs の同 run_id の status が ABORTED である
    And rapid_crosscheck_requests の同 run_id の status が ABORTED、completed_at が 2026-08-30T12:40:00 である
    And 実行ログ abort-green.sh.log に `INFO rapid request aborted run_id=20260830T113000-JOB001-3f9a1c2e from=REQUESTED to=ABORTED operator=ops01 answer=yes` が残る

  Scenario: 依頼作成直後に slot を中止すると依頼も ABORTED になり完了通知で再作成されない(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background、green/ に started-at.txt だけがある
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green mode=background status=RUNNING があり、parallel_runs の同 run_id の status が COMPLETED である(foreground の blue の中継が完了済み)
    And rapid_runs の同 run_id が completion_status=BOTH_SUCCEEDED で、両系の完了通知により rapid_crosscheck_requests に status=REQUESTED worker_id=NULL の速報比較依頼が作成された直後である(成果物再確認の後に green の exitcode.txt 公開と dispatcher の COMMIT が割り込んだ競合窓を DB に再現する)
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When 運用者 ops01 が `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行しプロンプトに `yes` と入力する
    Then 終了コード 0 で green/aborted.txt が公開され、slot_executions の同行の status が ABORTED である
    And rapid_crosscheck_requests の同 run_id の status が ABORTED、completed_at が 2026-08-30T12:40:00 であり、parallel_runs の同 run_id は COMPLETED のままである
    And その後 green の完了通知(`rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green`)を再送しても、対象 slot の slot 実行が ABORTED のため速報比較依頼は再作成されず、rapid_crosscheck_requests の同 run_id の行は ABORTED の 1 件のままである(UC「両系成功時に速報比較依頼を作成する」の条件「中止済み run の比較依頼作成除外」)

  Scenario Outline: CLAIMED または RUNNING の速報比較依頼は slot の中止では変更されない(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background、blue/ に started-at.txt だけがある
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=blue mode=background status=RUNNING がある
    And rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=<status> worker_id=<worker_id> started_at=<started_at> がある
    When 運用者が `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で blue/aborted.txt が公開され、slot_executions の同行の status が ABORTED である
    And rapid_crosscheck_requests の同 run_id の status が <status> のまま、completed_at は NULL のままである
    And 実行ログ abort-blue.sh.log に `rapid request aborted` を含む行は残らず、依頼の明示中止は abort-rapid-crosscheck.sh で行う

    Examples:
      | status  | worker_id | started_at          |
      | CLAIMED | worker-01 | NULL                |
      | RUNNING | worker-01 | 2026-08-30T11:46:00 |

  Scenario Outline: REQUESTED または CLAIMED の速報比較依頼を中止すると worker は比較を開始しない(SPEC-010-02)
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 status=<status> worker_id=<worker_id> lease_until=<lease_until> started_at=NULL がある
    And parallel_runs の同 run_id の status が COMPLETED である(foreground 中継が完了済みの通常 run)
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When 運用者 ops01 が `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し、現在状態(status=<status>)の表示後のプロンプトに `yes` と入力する
    Then 終了コード 0 で stdout の末尾 2 行が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` である
    And rapid_crosscheck_requests の同行の status が ABORTED、completed_at が 2026-08-30T12:40:00 であり、parallel_runs の同 run_id は COMPLETED のままである
    And 実行ログ abort-rapid-crosscheck.sh.log に `INFO status changed from=<status> to=ABORTED operator=ops01 answer=yes run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck` が残る
    And その後 <worker_check> を行っても更新件数は 0 で、比較ツールは起動されず comparison_results に同 run_id の行は登録されない(UC「比較ツールでジョブ単位比較を実行して結果を登録する」)

    Examples:
      | status    | worker_id | lease_until         | worker_check |
      | REQUESTED | NULL      | NULL                | 別 worker worker-02 が claim の条件付き UPDATE(`SET status='CLAIMED', worker_id='worker-02', lease_until=? WHERE run_id=? AND status='REQUESTED'`) |
      | CLAIMED   | worker-01 | 2026-08-30T12:10:00 | claim 済み worker-01 が RUNNING への条件付き UPDATE(`WHERE run_id=? AND status='CLAIMED' AND worker_id='worker-01'`) |

  Scenario: RAPID_CROSSCHECK_MODE=off でも aborted.txt を書いて中止が成立する(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background、blue/ に started-at.txt だけがある(exitcode.txt / aborted.txt なし)
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    And 運用者が blue の実行プロセスを実行先ホストで強制終了した
    When 運用者が `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行しプロンプトに `yes` と入力する
    Then 終了コード 0 で stdout の末尾 2 行が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` である
    And facade/20260830T113000-JOB001-3f9a1c2e/blue/aborted.txt が存在し中身が `2026-08-30T12:40:00Z` の 1 行である
    And 管理 DB への接続は行われず、stderr に `management db` を含む行は出ない
    And その後 `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role blue` が事前検証(元状態 ABORTED)を通過する

  Scenario: RUNNING の速報比較依頼を中止する(SPEC-010-02)
    Given rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING worker_id=worker-01 がある
    And parallel_runs の同 run_id の status が COMPLETED である(foreground 中継が完了済みの通常 run)
    When 運用者が `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout に `status=ABORTED` が出る
    And rapid_crosscheck_requests の同行の status が ABORTED であり、parallel_runs の同 run_id の status は COMPLETED のままである

  Scenario: リランで再作成した速報比較依頼を中止すると parallel_runs も ABORTED になる
    Given `background-rerun.sh --role rapid-crosscheck` で作成された run_id=20260830T130000-JOB001-a1b2c3d4 の rapid_crosscheck_requests が status=RUNNING で、parallel_runs の同 run_id の status が RUNNING である
    When 運用者が `abort-rapid-crosscheck.sh --run-id 20260830T130000-JOB001-a1b2c3d4 --yes` を実行する
    Then 終了コード 0 で rapid_crosscheck_requests の同行の status が ABORTED、parallel_runs の同 run_id の status が ABORTED である

  Scenario: STARTED のまま残った parallel_runs も slot の中止に伴い ABORTED になる(SPEC-011-06)
    Given RAPID_CROSSCHECK_MODE=background で run_id=20260830T124500-JOB001-7b2d9e01 の parallel_runs の status が STARTED(background-rerun が RUNNING 更新前に落ちた)、slot_executions(run_id, green) が mode=background status=RUNNING pid=NULL、facade/20260830T124500-JOB001-7b2d9e01/green/ に started-at.txt だけがある
    When 運用者が `abort-green.sh --run-id 20260830T124500-JOB001-7b2d9e01 --yes` を実行する
    Then 終了コード 0 で green/aborted.txt が作成され、slot_executions の同行が ABORTED、parallel_runs の同 run_id が ABORTED である

  Scenario: aborted.txt があり管理 DB だけ RUNNING のままなら管理 DB だけ再適用する
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/green/ に started-at.txt と aborted.txt(中身 2026-08-30T12:40:00Z)があり exitcode.txt は無い
    And slot_executions(run_id, green) の status が RUNNING のまま(前回の abort-green.sh が管理 DB 更新で 6 終了した)
    When 運用者が `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾に `status=ABORTED` が出て、stderr に `warn: aborted.txt already published; management db updated` が出る
    And green/aborted.txt の中身は `2026-08-30T12:40:00Z` のまま書き直されず、slot_executions の同行の status が ABORTED である

  Scenario: RUNNING の確報比較依頼を中止する
    Given final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=RUNNING がある
    When 運用者が `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 0 で final_crosscheck_requests の同行の status が ABORTED である
```

### 異常系

```gherkin
  Scenario: foreground の blue は中止できない(SPEC-010-01)
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が foreground で、blue/ に started-at.txt だけがある
    When 運用者が `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: run is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=blue mode=foreground status=RUNNING` が出る
    And blue/aborted.txt は作成されず、slot_executions の status は RUNNING のまま、parallel_runs の status も変わらない

  Scenario Outline: 終端状態の速報比較依頼は状態を変更せずエラー終了する(SPEC-010-02)
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=<status> completed_at=2026-08-30T12:00:00 がある
    When 運用者が `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck status=<status>` が出る
    And rapid_crosscheck_requests の同行の status は <status>、completed_at は 2026-08-30T12:00:00 のままで、parallel_runs も変わらない

    Examples:
      | status    |
      | SUCCEEDED |
      | FAILED    |
      | ABORTED   |

  Scenario Outline: RUNNING でない確報比較依頼は状態を変更せずエラー終了する(SPEC-010-02)
    Given final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=<status> がある
    When 運用者が `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T020000-final-1a2b3c4d role=final-crosscheck status=<status>` が出る
    And status は <status> のままである(REQUESTED / CLAIMED の確報比較依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う)

    Examples:
      | status    |
      | REQUESTED |
      | CLAIMED   |
      | SUCCEEDED |

  Scenario: 既に ABORTED の slot への再実行は中止不可として拒否する(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/green/ に started-at.txt と aborted.txt(中身 2026-08-30T12:40:00Z)があり exitcode.txt は無い
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green mode=background status=ABORTED completed_at=2026-08-30T12:40:00 がある
    When 運用者が `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を再実行する
    Then 終了コード 3 で stderr に `error: run is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=green mode=background status=ABORTED` が出る
    And green/aborted.txt の中身と slot_executions の completed_at は変わらない

  Scenario: off で既に aborted.txt がある slot への再実行は中止不可として拒否する
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/blue/ に started-at.txt と aborted.txt があり exitcode.txt は無い
    When `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: run is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=blue mode=background status=ABORTED` が出て、aborted.txt は書き直されない

  Scenario: 直前に完了した slot への中止は競合として拒否する
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background で、現在状態の表示時点では green/ に started-at.txt だけがあった
    And 現在状態の表示後、応答入力の前に runner が green/exitcode.txt(中身 0)を公開した
    When 運用者がプロンプトに `yes` と入力する
    Then yes 応答直後の成果物再確認で exitcode.txt を検出し、終了コード 3 で stderr に `error: run is not abortable (state changed concurrently) run_id=20260830T113000-JOB001-3f9a1c2e role=green` が出る
    And green/aborted.txt は作成されず、slot_executions の status は SUCCEEDED のままである

  Scenario: 管理 DB の更新に失敗しても aborted.txt は残し再適用を案内する
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/green/ に started-at.txt だけがあり、管理 DB が接続を拒否する
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 6 で stderr に `error: management db update failed` で始まる 1 行と `hint: rerun abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e to reapply` が出る
    And green/aborted.txt は公開済みのまま残る
```

## ティア別仕様

- [tier-ops](tier-ops.md)(4 スクリプトそれぞれの対象、aborted.txt の書き込み、条件付き UPDATE)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(この UC は publish / subscribe しない)
