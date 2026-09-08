# spec 差分更新の変更正本(feedback 20260907_todo_followup / event 20260907_024000_feedback_todo_followup)

この文書は、今回の spec 更新で全 subagent が従う「変更の正本」。ここに書かれた決定を各成果物へ反映する。
ここに無い仕様を発明しない。判断に迷う点は完了報告の「要確認」に書く(ファイルに仮採用を書き込まない)。

- 作業対象ルート: `/Users/suwa_sh/src/github.com/suwa-sh/relay-gate/docs/specs/events/20260907_024000_feedback_todo_followup/`(以下 `$E`)
- `docs/specs/latest/` は読むだけ。**書かない**(最後にオーケストレータが $E を latest へ反映する)
- RDRA の正本: `docs/rdra/latest/*.tsv`(今回更新済み)。差分要約: `docs/rdra/events/20260907_011000_feedback_todo_followup/_changes.md`
- USDM の正本: `docs/usdm/latest/requirements.yaml`(SPEC-005-02 / SPEC-005-06 / SPEC-010-01 に今回の受け入れ条件が追加済み)
- arch / nfr は `$E/_inputs-digest.md`(再生成済み)を読む。arch-design.yaml / nfr-grade.yaml の丸読みはしない。arch 差分要約: `docs/arch/events/20260907_015000_feedback_todo_followup/_changes.md`
- 中立表現を守る(固有システム名・製品名を書かない。現行実装 / 新実装 / ジョブスケジューラ / 比較ツール)
- Bash にヒアドキュメントを渡さない。ファイル編集は Edit / Write ツールで行う
- 今回の範囲は CR-013 / CR-014 / CR-015 の 3 件だけ。それ以外の記述は変えない(前イベントで確定済み)
- **機械置換は適用済み**(下記「適用済みの機械置換」)。文脈上おかしくなった箇所があれば直す

## 適用済みの機械置換(全ファイル。`_review/` `decisions/` `_inputs-digest.md` を除く)

| 置換 | 内容 |
|---|---|
| ログ行書式 | `{UTC 出力日時}` → `{ローカル出力日時}`、`{UTC 日時}` → `{ローカル日時}`、`{UTC}` → `{ローカル日時}` |
| 列名表現 | 「UTC 出力日時の列」→「ローカル出力日時の列」、「UTC 時刻列」→「ローカル時刻列」 |
| ログ行の例 | `2026-08-30T12:40:00Z INFO ...` → `2026-08-30T12:40:00 INFO ...`(日時の直後に LEVEL が続くものだけ Z 除去) |
| stdout の例 | `xxx_at=2026-08-30T11:30:05Z` → `xxx_at=2026-08-30T11:30:05`(`*_at=` に続く値だけ)。TSV 例のタブ直後の日時も Z 除去 |
| 説明文 | 「日時(UTC)」→「日時(ローカル時刻)」、「日時(UTC。」→「日時(ローカル時刻。」、「時刻(UTC)」→「時刻(ローカル時刻)」、`now(UTC)` → `now(ローカル時刻)`、「受信時刻 UTC」等 → 「受信時刻(ローカル時刻)」 |

機械置換で **直っていない** もの(各 subagent が担当ファイルで直す):
「UTC ISO 8601」「UTC ISO 8601 Z 付き」の単独表記(started-at.txt / aborted.txt の中身は **そのまま UTC**。それ以外の出力・DB・ログは D3 に従いローカルへ)、
「aborted.txt と同値」(→「aborted.txt の中止時刻と同時刻(表記はローカル)」)、
「TZ=UTC 前提」の注記(そのまま残す。BDD の例示は TZ=UTC 前提で数字を変えない)、
`RELAY_GATE_NOW=...Z`(そのまま UTC 入力)、`--since` の形式(D3-6)、メール本文の日時(D3-4)、
run_id.timezone の説明文「実行ログ・*_at 列・started-at.txt・aborted.txt・メール本文の日時は UTC ISO 8601 Z 付きのまま」(D3-1 の文へ差し替え)。

## 決定事項(CR ごと)

### D1. 速報クロスチェック設定(rapid-crosscheck.env)は RDRA 情報「速報クロスチェック設定」(CR-013)

RDRA 情報.tsv に「速報クロスチェック設定」が追加された(属性: 管理 DB 接続参照名(RAPID_DB_CONN_REF。値は置かず参照名のみ)、
lease 期間(秒。RAPID_LEASE_SEC)、worker の poll 間隔(秒。RAPID_POLL_INTERVAL_SEC)。関連: 速報比較依頼 / 並行稼働実行 / 完了通知 / ハング検知定期ジョブ設定。
バリエーション「設定所有区分」に「速報クロスチェック設定」(所有者: 基盤適用設計者)が追加された。USDM は SPEC-005-06(新設)。

1. 契約 `config_files[rapid-crosscheck.env]`:
   - `owner: "基盤適用設計者(設定所有区分: 速報クロスチェック設定。RDRA 情報「速報クロスチェック設定」)"`
   - `defined_in_uc: "実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する / クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する / クロスチェック業務/速報クロスチェックフロー/両系成功時に速報比較依頼を作成する / クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する"`(RDRA BUC.tsv で入力情報として紐づく 4 UC)
   - keys の description に RDRA 属性名を併記する(RAPID_DB_CONN_REF = 属性「管理 DB 接続参照名」、RAPID_LEASE_SEC = 属性「lease 期間(秒)」、RAPID_POLL_INTERVAL_SEC = 属性「worker の poll 間隔(秒)」)。既定値 600 / 30 は変えない
   - 「仮採用: _inference.md #6」「final-crosscheck.env と対称」の注記は外す(final-crosscheck.env 側の注記は今回の対象外なので触らない)
2. 契約 `shared_rules.lease_and_poll`: `rapid` の出所を「速報クロスチェック設定(rapid-crosscheck.env。情報「速報クロスチェック設定」)」と明記する。`confidence` は
   `"low(既定値 600 / 30 秒は仮採用。出所(速報クロスチェック設定)は RDRA 確定)"` に狭める(値そのものは RDRA が定めていない)
3. `_model-summary.yaml`(4 UC): repository 層の設定読み取りモデルとして `速報クロスチェック設定(rapid-crosscheck.env)` を追加し、`rdra_info: "速報クロスチェック設定"` を付ける
   (既に `rapid-crosscheck.env(...)` の項目がある場合は `rdra_info` を付け、`note: "RDRA 未定義..."` を削除する)。
   UC「hang_detect_limit_minutes をジョブごとに調整する」の `_model-summary.yaml` にある `rapid-crosscheck.env(RAPID_DB_CONN_REF)` の `note: "RDRA 未定義(...)"` も削除し `rdra_info: "速報クロスチェック設定"` を付ける
4. 4 UC の spec.md「関連 RDRA モデル」に 情報「速報クロスチェック設定」の行を追加する(属性 3 つを列挙。適用 tier を空にしない)。
   tier-*.md の入力・データモデル記述で `rapid-crosscheck.env` を参照している箇所に「情報「速報クロスチェック設定」」を併記する
5. USDM SPEC-005-06 の受け入れ条件 4 件を次の UC の BDD に配置する(シナリオ名末尾に `(SPEC-005-06)`。spec.md「関連 USDM」表にも行を追加):
   - AC1「設定された参照名で管理 DB に接続し、設定された lease 期間と poll 間隔で claim と poll が行われる」→ UC「速報比較依頼を claim する」(lease / poll)と UC「速報クロスチェック runner へ完了通知を送信する」(接続参照名)
   - AC2「速報クロスチェック設定の所有者は基盤適用設計者である」→ UC「速報比較依頼を claim する」(設定所有区分の行)
   - AC3「認証情報の値は含まれず管理 DB 接続の参照名だけがある」→ UC「slot 実行モードを選択して runner を起動する」(既存の RAPID_DB_CONN_REF 検証シナリオに追加)
   - AC4「RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる」→ UC「slot 実行モードを選択して runner を起動する」

### D2. 中止済み run では速報比較依頼を作らない / abort-blue・abort-green は未着手依頼も ABORTED にする(CR-014)

RDRA: 条件「中止済み run の比較依頼作成除外」(新設)、条件「両系成功判定」「完了通知の系統独立」「slot 中止可否判定」(追記)、
状態「クロスチェック依頼」REQUESTED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」。速報比較依頼のみ)、状態 ABORTED(終端)の説明追記、
情報「速報実行(rapid_run)」「速報比較依頼」「中止指示」「完了通知」の説明追記。USDM: SPEC-005-02 に AC 3 件、SPEC-010-01 に AC 2 件を追加。
arch: SP-009 / LP-010 / LP-023 / SP-022 / LP-019 / LP-021 / CM-005 / E-016 / E-017 / E-024。判断主体は速報クロスチェック runner(dispatcher)。slot runner は自 slot の中止状態を判断しない。

#### D2-1. 契約 `rapid-crosscheck-runner.sh`(dispatcher)

- 処理順(トランザクション内): rapid_runs の自系統列を更新(先勝ち)→ `parallel_runs.status` を同一トランザクションで読む → 両系成功判定 → **parallel_runs.status = 'ABORTED' なら速報比較依頼を INSERT しない**。それ以外は従来どおり
- ABORTED run で両系成功のとき: `rapid_runs.completion_status` は `BOTH_SUCCEEDED` のまま(`REQUEST_CREATED` へ進めない)。完了事実(blue_status / green_status / 成果物 URI / 受信日時)は記録する
- 実行ログ: `WARN rapid request not created run_id=... reason=parallel_run_aborted`(dispatcher の実行ログ `rapid-crosscheck-runner.sh.log`)。
  stderr: `warn: rapid request not created run_id=... reason=parallel run aborted`(継続。終了コード 0)
- stdout: 固定順は変えない。`request_status=-` / `requested_at=-`(依頼を作らなかったため)
- exit_codes の 0 の meaning に「並行稼働実行が ABORTED の run では両系成功でも依頼を作成せず 0(条件「中止済み run の比較依頼作成除外」)」を追記
- notes に条件「中止済み run の比較依頼作成除外」の説明を 1 項目追加(判断主体は本コマンド。slot runner は自 slot の中止状態(aborted.txt)を判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり通知する = 条件「完了通知の系統独立」。RAPID_CROSSCHECK_MODE=off では完了通知も依頼も存在しないため速報有効時だけに適用)
- 判定表(arch LP-010。tier-rapid-crosscheck.md にも載せる): 縦軸 = parallel_runs.status(ABORTED / それ以外)、横軸 = 両系成功判定(両系成功 / いずれか失敗 / 片系未完了)。依頼を作成するのは「それ以外 × 両系成功」だけ

#### D2-2. 契約 `abort-blue.sh` / `abort-green.sh`

- exit_codes 0 の meaning に追記: 「RAPID_CROSSCHECK_MODE が off 以外なら加えて `rapid_crosscheck_requests` を条件付き UPDATE(`WHERE run_id=? AND status='REQUESTED'`)で ABORTED(completed_at=now)にする。0 件は正常(依頼が無い、または CLAIMED / RUNNING / 終端済み)。CLAIMED / RUNNING の依頼は変更せず abort-rapid-crosscheck.sh の対象のまま」
- idempotency の順序: 成果物再確認 → aborted.txt 公開 → (off 以外)slot_executions / parallel_runs / **rapid_crosscheck_requests(REQUESTED のみ)** を条件付き UPDATE。再適用時も同じ UPDATE を試みる(0 件で可)
- 実行ログ: 依頼を ABORTED にしたとき `INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=... answer=yes`。0 件のときはログを出さない(正常)。`--verbose` 時は stderr に `info: rapid request aborted run_id=...`
- stdout の固定 8 行と `status=ABORTED` / `aborted_at=` は変えない(依頼の状態は出さない)
- `--run-id` の description に「対象 run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(条件「slot 中止可否判定」)」を追記
- abort-green.sh は「abort-blue.sh と同じ」の参照のままでよい(abort-blue.sh 側に書けば足りる)
- 確報比較依頼(final_crosscheck_requests)には適用しない

#### D2-3. 契約 `shared_rules.state_codes`

`request_status` の直後に `request_status_transitions` を追加する(状態.tsv「クロスチェック依頼」と 1:1):

```yaml
    request_status_transitions:
      - "(新規)→ REQUESTED(rapid-crosscheck-runner.sh の両系成功判定 / background-rerun.sh --role rapid-crosscheck / final-crosscheck-runner.sh の登録)"
      - "REQUESTED → CLAIMED(rapid-crosscheck-worker.sh / final-crosscheck-worker.sh の claim。条件付き UPDATE status='REQUESTED')"
      - "CLAIMED → REQUESTED(worker の lease 失効解放。lease_until < now かつ started_at IS NULL)"
      - "CLAIMED → RUNNING(worker の比較ツール起動)"
      - "RUNNING → SUCCEEDED / FAILED(worker の終端 UPDATE status='RUNNING'。0 件は ABORTED 済み)"
      - "RUNNING → ABORTED(abort-rapid-crosscheck.sh / abort-final-crosscheck.sh。条件付き UPDATE status='RUNNING')"
      - "REQUESTED → ABORTED(abort-blue.sh / abort-green.sh。対象 run の未着手の速報比較依頼だけ。条件付き UPDATE status='REQUESTED'。0 件は正常。確報比較依頼には適用しない)"
```

#### D2-4. `rdb-schema.yaml`

- `rapid_crosscheck_requests.status` の description 末尾に遷移注記を追加: 「遷移: REQUESTED → CLAIMED(claim)/ CLAIMED → REQUESTED(lease 失効)/ CLAIMED → RUNNING / RUNNING → SUCCEEDED・FAILED / RUNNING → ABORTED(abort-rapid-crosscheck)/ REQUESTED → ABORTED(abort-blue / abort-green による未着手依頼の中止。条件付き UPDATE status='REQUESTED')」
- `rapid_runs.completion_status` の description 末尾に追記: 「並行稼働実行が ABORTED の run では両系成功でも REQUEST_CREATED へ進めない(BOTH_SUCCEEDED のまま。条件「中止済み run の比較依頼作成除外」)」
- `rapid_runs` の access に UC「両系成功時に速報比較依頼を作成する」が parallel_runs を SELECT することを反映(parallel_runs の access に無ければ `SELECT` を追加)
- `_review_notes` に「abort-blue / abort-green の rapid_crosscheck_requests 条件付き UPDATE(REQUESTED のみ)は app_rw の既存 UPDATE 権限で足りる。0 件は正常」を 1 項目追加

#### D2-5. UC への配置(BDD はシナリオ名末尾に SPEC ID)

- UC「両系成功時に速報比較依頼を作成する」(UC-09): 分岐条件一覧に条件「中止済み run の比較依頼作成除外」を追加(適用 tier: tier-rapid-crosscheck)、
  関連 RDRA モデルに 情報「実行ログ」を追加、状態遷移一覧の「速報実行の完了状況 → 比較依頼作成済み」に ABORTED run の除外を注記。
  処理フロー(spec.md / tier-rapid-crosscheck.md)に parallel_runs.status の参照と判定表を追加。`_model-summary.yaml` の parallel_runs(並行稼働実行)に SELECT があることを確認。
  BDD 追加(SPEC-005-02): AC4「Given 並行稼働実行が ABORTED When 後から完了通知を受ける Then 速報比較依頼は作成されず、完了事実だけが記録される」、
  AC5「Given 並行稼働実行が ABORTED で片系が成功済み When もう片系の完了通知を受ける Then 両系成功でも速報比較依頼は作成されず、実行ログに警告が残る」、
  AC6「Given 中止した run を background-rerun でリランした When 新しい run の両系が成功する Then 新しい run_id で速報比較依頼が作成される」(新 run の parallel_runs は RUNNING であることを Given に含める)
- UC「速報クロスチェック runner へ完了通知を送信する」(UC-08): 条件「完了通知の系統独立」の説明に「自 slot の中止状態(aborted.txt)も判断しない」を反映。
  BDD 1 件追加(SPEC-005-01 の既存行に併記): 「Given aborted.txt がある slot で実装が走り切り exitcode.txt を公開した When runner が完了通知を送る Then 通常どおり blue-completed / green-completed を送り、比較依頼の要否は判断しない」
- UC「実行を ABORTED へ遷移させる」(UC-23): 状態遷移一覧に「クロスチェック依頼 REQUESTED → ABORTED(abort-blue / abort-green。速報比較依頼のみ)」を追加(適用 tier: tier-ops)、
  条件「slot 中止可否判定」の説明に未着手依頼の ABORTED 化を追記、関連 RDRA モデルの情報「中止指示」「速報比較依頼」を確認。
  処理フロー(spec.md / tier-ops.md)に D2-2 の UPDATE と実行ログを追加。
  BDD 追加(SPEC-010-01): AC6「Given REQUESTED の速報比較依頼がある run When abort-blue または abort-green を実行して yes と答える Then その依頼も ABORTED になる」、
  AC7「Given CLAIMED または RUNNING の速報比較依頼がある run When abort-blue または abort-green を実行して yes と答える Then slot は ABORTED になるが依頼の状態は変更されない」
- UC「現在状態を確認して停止確認に応答する」(UC-22): 契約 abort-blue.sh の defined_in_uc のため、コマンド契約の参照(D2-2)を tier-ops.md に反映(BDD 追加は不要)
- buc-spec.md「速報クロスチェックフロー」「実行中止フロー」: 状態遷移全体図(mermaid)に REQUESTED → ABORTED(abort-blue / abort-green)を追加、状態遷移 UC マッピング・共有条件一覧(中止済み run の比較依頼作成除外 / slot 中止可否判定)を更新
- UC「background 実行の経過時間と終了状態を判定する」「監視記録を保存する」: 依頼 ABORTED は既に中止済み終端として扱っている。REQUESTED から ABORTED になった依頼も同じ終端(変更不要。記述があれば「abort-blue / abort-green による未着手依頼の中止を含む」と 1 語添える程度)

### D3. 実行ログ・出力・管理 DB の日時はホストのローカルタイムゾーン(CR-015。利用者決定 DIST-022 A)

arch CLP-002 / CTP-003 / CLP-004 / E-025 / E-015: ログの日時はホストのローカルタイムゾーン(プロセスの TZ 環境変数に従う)で ISO 8601 秒精度、タイムゾーン指示子(Z / オフセット)なし。
run_id の時刻部と同じ時刻軸。UTC への統一は行わない。管理 DB の *_at 列は RDB のタイムスタンプ型に委ね、CLI が stdout に表示する日時もローカル時刻。
RELAY_GATE_NOW は UTC の Z 付きで受け付け、内部でローカル時刻へ変換してから使う(既存規則を維持)。

- D3-1. 契約 `conventions.execution_log.line_format`: `{script} {run_id} {ローカル日時} {LEVEL} {message}`。`line_format` の直後に
  `datetime: "ホストのローカルタイムゾーン(プロセスの TZ 環境変数に従う)。ISO 8601 秒精度、タイムゾーン指示子(Z / オフセット)なし(例 2026-08-30T12:40:00)。run_id の時刻部と同じ時刻軸。UTC への統一は行わない(arch CLP-002 / CTP-003)"` を追加。
  `shared_rules.run_id.timezone` の末尾文を「実行ログ・管理 DB の *_at 列・CLI の stdout・メール本文の日時も同じローカルタイムゾーン(指示子なし)で表す。started-at.txt / aborted.txt の中身だけは UTC ISO 8601 Z 付きのまま(Runner Result Contract。表示・DB 転記時はローカルへ変換する)」に差し替える
- D3-2. `ui-design.md`「出力フォーマット」の **日時** 項: 「ホストのローカルタイムゾーン、ISO 8601 秒精度、タイムゾーン指示子なし(`2026-08-30T11:30:00`)。run_id の時刻部と同じ時刻軸。UTC や Z 付き・オフセット表記は使わない(利用者決定 2026-09-07)。例外: started-at.txt / aborted.txt の中身は UTC Z 付き(Runner Result Contract)。RELAY_GATE_NOW は UTC Z 付きで受け取りローカルへ変換する」。
  実行ログファイルの形式・例、状態表示の例、通知メール本文の `started_at` / `detected_at`(D3-4)、環境変数表の RELAY_GATE_NOW の説明(「run_id の時刻部・実行ログ・*_at 列・stdout の日時はこの UTC 値をローカルへ変換した値」)を追従
- D3-3. `rdb-schema.yaml` の `*_at` 列 description: 「(UTC)」は機械置換で「(ローカル時刻)」になっている。テーブル冒頭または `_review_notes` に
  「日時列は RDB のタイムスタンプ型(タイムゾーンなし)に委ね、ホストのローカルタイムゾーンの値を入れる。全ホストの TZ 設定は統一する(infra REQ-LOG-003)。RELAY_GATE_NOW 設定時はその UTC 値をローカルへ変換した値」を 1 項目追加。
  `slot_executions.completed_at` の「ABORTED では aborted.txt の中止日時と同値」→「ABORTED では aborted.txt の中止時刻(UTC)をローカルへ変換した同時刻」
- D3-4. 通知メール本文(ui-design.md 通知メール規約、UC「ハング疑い・実行エラー・比較異常を通知する」): `started_at` / `detected_at` はローカル ISO 8601(指示子なし)。started-at.txt 由来の値はローカルへ変換して載せる
- D3-5. `data-visualization.md`: 日時列(`requested_at` / `completed_at` / `compared_at` / `started_at` / `judged_at` 等)の型を「ローカル ISO 8601(指示子なし)」に変更。
  「requested_at 列は UTC。両者を突き合わせるときはタイムゾーン差に注意する」の注記を「run_id の時刻部と同じ時刻軸なので突き合わせに変換は不要」に差し替え。
  `hang-detect-trend.sh` の `--since` 見出しを `[--since ローカル日時]` に変更
- D3-6. `hang-detect-trend.sh --since`: 入力形式をローカル ISO 8601 秒精度・指示子なし(表示と同じ時刻軸)に変更(契約 options / stderr の `since 形式不正` 条件 / 既定値の説明 / data-visualization)。
  **要確認項目 #1**(オーケストレータが完了報告で返す。ここでは採用済みとして書く)
- D3-7. stdout の日時(`requested_at=` / `started_at=` / `aborted_at=` / `detected_at=` / `completed_at=` / TSV 列): ローカル(指示子なし)。機械置換で例示の Z は除去済み。
  `abort-blue.sh` の `aborted_at={ローカル日時}` は aborted.txt の中止時刻(UTC Z)をローカルへ変換した値(同時刻)。`started_at=` も started-at.txt の値をローカルへ変換
- D3-8. started-at.txt / aborted.txt / execution-spec.json(`finalized_at` / `restored_at`)の**中身は変えない**(UTC ISO 8601 秒精度 Z 付き。artifact_layout / shared_rules.exitcode_to_status / abort-* notes / execution_spec_example の記述はそのまま)。
  ファイル成果物(Runner Result Contract)の値は機械交換用として UTC Z 付きを維持し、表示・実行ログ・DB へ出すときにローカルへ変換する。
  **要確認項目 #2**(Runner Result ファイルの中身を UTC のまま残す判断)
- D3-9. BDD の例示: `RELAY_GATE_NOW=2026-08-30T11:30:00Z`(UTC 入力)は変えない。TZ=UTC 前提なので、表示・ログ・DB の Then は `2026-08-30T11:30:00`(Z なし)。
  例示のログ行 `... 2026-08-30T12:40:00 INFO ...`。「(TZ=UTC 前提)」の注記は残す
- D3-10. `asyncapi.yaml` / `uc-dependencies.md` / `ux-design.md` の日時説明も同じ規則へ(内容は説明文の追従のみ)

## USDM の今回追加分(spec.md「関連 USDM」表と BDD に対応づける)

| SPEC | 受け入れ条件(追加分) | 配置 UC |
|---|---|---|
| SPEC-005-02 | AC4 / AC5 / AC6(D2-5) | 両系成功時に速報比較依頼を作成する |
| SPEC-005-06 | AC1〜AC4(D1-5) | 速報比較依頼を claim する / 速報クロスチェック runner へ完了通知を送信する / slot 実行モードを選択して runner を起動する |
| SPEC-010-01 | AC6 / AC7(D2-5) | 実行を ABORTED へ遷移させる |

## 解消済み(注記を外す)

- `config_files[rapid-crosscheck.env]` / `_model-summary.yaml` の「仮採用: _inference.md #6」「RDRA 未定義(rapid-crosscheck.env は情報.tsv に無い…)」(D1。todo DIST-023)
- 実行ログ日時の「UTC」注記(D3。todo DIST-022)
- todo DIST-024(中止済み run の速報比較依頼)は D2 で解消

## 反証レビュー round-1 で確定した追加決定(D4。全 subagent が従う)

反証レビュー(`_review/round-1.yaml` R-001〜R-007)で「検証は通るが実装で破綻する」点が挙がった。RDRA の変更が必要なものは `rdra-feedback.md` に変更要望として載せ、Spec 側は仮採用(注記付き)で実装可能な形にする。

### D4-1. 中止済み run の判定キーを拡張する(R-001。仮採用 + rdra-feedback #13)

- 典型経路(foreground blue 完了 → facade が parallel_runs を COMPLETED にした後、background green を abort-green で中止)では parallel_runs は COMPLETED のまま(abort の条件付き UPDATE は COMPLETED を更新しない)。このため判定キーを `parallel_runs.status = ABORTED` だけに置くと除外が効かない
- dispatcher の判定キーを「run が中止済み = `parallel_runs.status = ABORTED` **または** 同 run の `slot_executions` に `status = ABORTED` の行がある(いずれかの slot に aborted.txt が公開済み)」に拡張する。判断主体は dispatcher のまま(条件「完了通知の系統独立」と矛盾しない)
- 契約 `request_creation_matrix` の縦軸を「run が中止済み(parallel_runs ABORTED または slot_executions に ABORTED あり)/ それ以外」に改め、UC「両系成功時に速報比較依頼を作成する」の分岐条件・判定表・処理フロー・`_model-summary.yaml`(slot_executions SELECT)を追従。BDD に「parallel_runs が COMPLETED で green slot だけ ABORTED の run に green の完了通知が届いても依頼を作らない」を 1 件追加(SPEC-005-02。仮採用の注記付き)
- 注記の書き方: 「(仮採用: rdra-feedback #13。RDRA 条件は parallel_run の ABORTED のみを判定キーとしている)」

### D4-2. dispatcher は parallel_runs を FOR UPDATE で読む(R-003)

- rapid-crosscheck-runner.sh の処理順: rapid_runs 自系統列の UPDATE(先勝ち)→ `SELECT job_id, status FROM parallel_runs WHERE run_id = ? FOR UPDATE` → `slot_executions` の status を読む → 両系成功判定 → 依頼 INSERT → COMMIT
- abort-blue / abort-green の順序は slot_executions UPDATE → parallel_runs UPDATE → rapid_crosscheck_requests UPDATE(REQUESTED のみ)。worker は requests → parallel_runs。ロック順を `rdb-schema.yaml` の `_review_notes` に 1 項目で明記し、abort が先なら dispatcher は COMMIT 後の状態を読み、dispatcher が先なら abort の requests UPDATE が REQUESTED を 1 件 ABORTED にする、と説明する
- 契約 rapid-crosscheck-runner.sh の idempotency / notes、UC「両系成功時に速報比較依頼を作成する」の spec.md / tier-rapid-crosscheck.md / `_model-summary.yaml` に反映

### D4-3. REQUESTED → ABORTED は競合窓の保険と位置づける(R-002。rdra-feedback #14)

- REQUESTED の依頼は両 slot の exitcode.txt 公開後にしか存在せず、その時点で abort-blue / abort-green は「exitcode.txt あり = 終端済み」で 3 を返す。到達するのは「abort の成果物再確認と runner の exitcode.txt 公開が同時刻に起きた競合窓」だけ
- 契約 abort-blue.sh の notes と UC「実行を ABORTED へ遷移させる」の条件説明・buc-spec(実行中止フロー)に、この遷移が競合窓の保険であること、両 slot 完了直後の依頼を止める本来の経路は D4-1(dispatcher の判定)であることを明記する
- BDD(SPEC-010-01 AC6)の Given を「green slot が RUNNING(started-at.txt あり・exitcode.txt なし)で、その run に REQUESTED の速報比較依頼がある(dispatcher が中止直前に作成した競合ケース)」に書き換える。シナリオ名は変えない(usdm-acceptance-matrix と一致させたまま)
- RDRA 状態.tsv 行 7 の説明文(「両 slot 完了直後に中止した場合に依頼だけが残って比較が走る抜けを防ぐ」)は実際の経路と合わないため rdra-feedback に変更要望として載せる

### D4-4. CLAIMED の依頼が lease 失効で戻る抜けは注記と rdra-feedback にとどめる(R-004。rdra-feedback #15)

- abort-blue / abort-green が CLAIMED を変更せず、abort-rapid-crosscheck は RUNNING 限定(条件「依頼中止可否判定」)のため、中止済み run の CLAIMED 依頼は lease 失効で REQUESTED に戻り再 claim されうる
- Spec 側は claim の振る舞いを変えない(RDRA に無い判断を発明しない)。契約 abort-blue.sh の notes と UC「実行を ABORTED へ遷移させる」の条件説明に「CLAIMED のまま中止した依頼は lease 失効で再 claim されうる。止めるには abort-rapid-crosscheck の対象拡張(RDRA 変更要望)が必要」と書く
- rdra-feedback に「条件「依頼中止可否判定」/ 状態.tsv 行 16 / SPEC-010-02: abort-rapid-crosscheck の対象に REQUESTED / CLAIMED を加える」の変更要望を載せる(確認推奨項目として返却)

### D4-5. すべての日時はホストで生成してバインドする(R-005)

- 契約 `conventions.execution_log` の直後(または shared_rules)に `datetime_generation: "日時はすべてホスト側で生成し(RELAY_GATE_NOW 設定時はその変換値)、SQL にはバインド値で渡す。SQL 内の now() / CURRENT_TIMESTAMP / DEFAULT now() は使わない(DB セッションの TimeZone 設定に依存させない)。spec の擬似 SQL に現れる now は「ホストで生成した現在時刻のバインド値」を意味する"` を追加
- `environment_variables.RELAY_GATE_NOW.purpose` の「DB の now() を使う UPDATE / INSERT も、この値を渡して同じ時刻にする」を「すべての日時はホストで生成して渡す(設定時はその変換値)」に差し替え
- `rdb-schema.yaml` の `_review_notes` に同趣旨を 1 項目追加。UC の擬似 SQL の `now()` 表記は書き換えない(上の規約で意味を定める)

### D4-6. 判定は epoch 秒で行う(R-006)

- 契約の日時規約と ui-design.md「出力フォーマット」の日時に 1 文追加: 「経過時間・lease 失効・走査窓(--since)の判定は epoch 秒で計算し、表記の比較では行わない。DST のあるタイムゾーンでは切替前後の表記が一意でないことを許容する。UTC → ローカルの変換は 1 箇所の共通関数に置き、全スクリプトが同じ変換を使う」

### D4-7. stderr の reason 値を実行ログと揃える(R-007)

- D2-1 の stderr を `warn: rapid request not created run_id=... reason=parallel_run_aborted` に訂正する(値に空白を含めない)。契約 stderr / exit_codes / UC「両系成功時に速報比較依頼を作成する」の spec.md・tier-rapid-crosscheck.md の該当箇所を修正

### D4-8. abort-blue / abort-green は parallel_runs を無条件に FOR UPDATE でロックしてから条件付き UPDATE を行う(R-003 round-2)

- parallel_runs が COMPLETED(foreground 中継済み)の run では abort の条件付き UPDATE(status IN STARTED/RUNNING)が 0 件で行ロックを取らず、dispatcher の FOR UPDATE と直列化されない
- abort-blue / abort-green のトランザクション先頭(slot_executions UPDATE の直後、parallel_runs 条件付き UPDATE の前)に `SELECT 1 FROM parallel_runs WHERE run_id = ? FOR UPDATE`(無条件の行ロック)を置く。ロック順は slot_executions → parallel_runs(FOR UPDATE)→ parallel_runs 条件付き UPDATE → rapid_crosscheck_requests 条件付き UPDATE のまま
- 契約 abort-blue.sh の idempotency / notes(競合窓の保険)、UC「実行を ABORTED へ遷移させる」の spec.md 処理フロー・条件表・tier-ops.md「共通(併更新)」表、rdb-schema.yaml `_review_notes` のロック順項目に反映
- UC「両系成功時に速報比較依頼を作成する」の `_api-summary.yaml`(stdout / exit_codes)と速報クロスチェックフロー buc-spec.md の残存する旧判定キー表現を D4-1 の表現に統一(R-008)
- background 側リランフローの 2 つの tier-ops.md にある「DB の now() を使う INSERT / UPDATE にもこの値を渡す」を「日時はホストで生成して SQL にバインド値で渡す(RELAY_GATE_NOW 設定時はその変換値。conventions.datetime_generation)」に差し替え(R-009)
