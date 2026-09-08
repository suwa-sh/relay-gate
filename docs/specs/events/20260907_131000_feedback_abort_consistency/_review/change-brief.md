# spec 差分更新の変更正本(feedback 20260907_abort_consistency / event 20260907_131000_feedback_abort_consistency)

この文書は、今回の spec 更新で全 subagent が従う「変更の正本」。ここに書かれた決定を各成果物へ反映する。
ここに無い仕様を発明しない。判断に迷う点は完了報告の「要確認」に書く(ファイルに仮採用を書き込まない)。

- 作業対象ルート: `/Users/suwa_sh/src/github.com/suwa-sh/relay-gate/docs/specs/events/20260907_131000_feedback_abort_consistency/`(以下 `$E`)
- `docs/specs/latest/` は読むだけ。**書かない**(最後にオーケストレータが $E を latest へ反映する)
- RDRA の正本: `docs/rdra/latest/*.tsv`(今回更新済み)。差分要約: `docs/rdra/events/20260907_114000_feedback_abort_consistency/_changes.md`
- USDM の正本: `docs/usdm/latest/requirements.yaml`(SPEC-005-02 / SPEC-010-01 / SPEC-010-02 に今回の受け入れ条件が追加済み)
- arch / nfr は `$E/_inputs-digest.md`(再生成済み)を読む。arch-design.yaml / nfr-grade.yaml の丸読みはしない。arch 差分要約: `docs/arch/events/20260907_122000_feedback_abort_consistency/_changes.md`
- 中立表現を守る(固有システム名・製品名を書かない。現行実装 / 新実装 / ジョブスケジューラ / 比較ツール)
- Bash にヒアドキュメントを渡さない。ファイル編集は Edit / Write ツールで行う
- 今回の範囲は CR-016 / CR-017 / CR-018 の 3 件だけ。それ以外の記述は変えない(前イベント 20260907_024000 で確定済み)
- 前イベントで「仮採用: rdra-feedback #13」「rdra-feedback #14」「rdra-feedback #15」と注記した箇所は、今回 RDRA / USDM / arch に反映されたので **注記を外し、確定した規則として書く**(`grep -rn "rdra-feedback #1[345]\|仮採用: rdra-feedback" $E` が 0 件になること。`_cross-cutting/rdra-feedback.md` の解消済み表だけは残る)

## 決定事項(CR ごと)

### D1. 中止済み run の判定キーに「対象 slot の slot 実行 ABORTED」を加える(CR-016。利用者決定 DIST-025 A)

RDRA: 条件「中止済み run の比較依頼作成除外」(判定キー拡張。判定材料 = parallel_run.status と slot_executions.status。状態モデルに slot 実行を追加)、
条件「両系成功判定」(除外対象の表現)、情報「速報実行(rapid_run)」(関連情報に slot 実行)、BUC「速報クロスチェックフロー」UC「両系成功時に速報比較依頼を作成する」(入力情報に slot 実行)。
USDM SPEC-005-02(受け入れ条件 8 件。AC5 / AC6 が今回追加)。arch SP-009 / LP-010 / LP-023 / L-rapid の usecase・domain・repository 責務 / CLP-004 / BC-002 / AG-002 / E-016(E-014 slot 実行への関係)。

#### D1-1. 判定キー(契約 `rapid-crosscheck-runner.sh` の `request_creation_matrix` と notes、UC-09 の spec / tier)

- run が中止済み = `parallel_runs.status = 'ABORTED'`、**または完了通知の対象 slot(通知元 role の slot。blue の通知なら slot='blue' の行)の `slot_executions.status = 'ABORTED'`**(aborted.txt 公開済みのミラー)
- 判定材料は同一トランザクションで読む: rapid_runs(FOR UPDATE)→ parallel_runs(`SELECT job_id, status FROM parallel_runs WHERE run_id = ? FOR UPDATE`)→ slot_executions(`SELECT status FROM slot_executions WHERE run_id = ? AND slot = ?`。SELECT のみ)→ 両系成功判定 → 依頼 INSERT
- 判定表(arch LP-010)の縦軸は 3 値: 「並行稼働実行 ABORTED」「対象 slot の slot 実行 ABORTED」「いずれでもない」。横軸は両系成功判定(両系成功 / いずれか失敗 / 片系未完了)。依頼を作成するのは「いずれでもない × 両系成功」だけ。`request_creation_matrix.rows` を 3 行にする(既存 2 行の「run が中止済み(... slot_executions に ABORTED あり)」を 2 行に分ける)
- 前イベントの「同 run の slot_executions に status = 'ABORTED' の行がある(いずれかの slot)」という表現は **「完了通知の対象 slot の slot 実行」に改める**(RDRA の判定表と一致させる)。「仮採用: rdra-feedback #13」「RDRA 条件は parallel_run の ABORTED のみを判定キーとしている」の注記は削除する
- 典型経路の説明(残す): 並行稼働実行は foreground slot の結果を中継した時点で COMPLETED になるため、foreground 完了後に background slot を abort-blue / abort-green で中止した run は、対象 slot の slot 実行 ABORTED の側で除外される
- 実行ログの reason は判定キーで分ける: `WARN rapid request not created run_id=... reason=parallel_run_aborted`(並行稼働実行 ABORTED)/ `WARN rapid request not created run_id=... role=... reason=slot_execution_aborted`(対象 slot の slot 実行 ABORTED)。stderr も同様に `warn: rapid request not created run_id=... reason=parallel_run_aborted` / `warn: rapid request not created run_id=... role=... reason=slot_execution_aborted`(継続。終了コード 0)。完了事実(blue_status / green_status / 成果物 URI / 受信日時)は記録し、`rapid_runs.completion_status` は BOTH_SUCCEEDED のまま(REQUEST_CREATED へ進めない)。stdout は `request_status=-` / `requested_at=-`
- 判断主体は本コマンド(dispatcher)。slot runner は自 slot の中止状態(aborted.txt)を判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり完了通知を送る(条件「完了通知の系統独立」)。RAPID_CROSSCHECK_MODE=off では完了通知も依頼も存在しないため速報有効時だけに適用する
- リラン: 中止した run を `background-rerun.sh --role rapid-crosscheck` でリランした場合は新 run_id(parallel_runs は RUNNING、slot_executions 行なし)で依頼が作成される

#### D1-2. UC-09「両系成功時に速報比較依頼を作成する」

- spec.md「関連 RDRA モデル」: 情報「slot 実行」/ 状態「slot 実行」(ABORTED の参照)の行を追加する(適用 tier: tier-rapid-crosscheck。参照のみ。属性は status)。条件「中止済み run の比較依頼作成除外」「両系成功判定」の行の説明を D1-1 に合わせる
- 分岐条件一覧 / 処理フロー / データフロー(mermaid): slot_executions の SELECT を追加(既にある場合は「対象 slot」条件 `AND slot = ?` に改める)
- BDD(spec.md E2E / tier-rapid-crosscheck.md): USDM SPEC-005-02 の受け入れ条件 8 件がすべて対応シナリオを持つこと。今回追加は
  AC5「Given 並行稼働実行は COMPLETED だが対象 slot の slot 実行が ABORTED When 後から完了通知を受ける Then 速報比較依頼は作成されず、完了事実だけが記録される」と
  AC6「Given foreground の blue が完了して並行稼働実行が COMPLETED になった後に background の green を abort-green で中止した When green の実装が走り切って完了通知を送る Then 速報比較依頼は作成されず、実行ログに警告が残る」。
  前イベントで「仮採用: rdra-feedback #13」として置いた「parallel_runs が COMPLETED で green slot だけ ABORTED」のシナリオは、AC5 / AC6 に対応するシナリオとして名前を整え(末尾 `(SPEC-005-02)`)、注記を外す。「関連 USDM」表の SPEC-005-02 行も 8 件に合わせる
- `_model-summary.yaml`: tables に `slot_executions`(operations: SELECT。列 run_id / slot / status)が無ければ追加する(既にある場合は説明を「完了通知の対象 slot の状態参照」に)。repository 層モデルに slot 実行の状態参照を追加(rdra_info: "slot 実行")
- tier-rapid-crosscheck.md: 判定表を 3 行 × 3 列に、SQL 列挙とロック順(D1-1)、実行ログ行(D1-1)を反映する

#### D1-3. UC-08「速報クロスチェック runner へ完了通知を送信する」/ buc-spec(速報クロスチェックフロー)

- 中止済み run の説明(完了通知の系統独立の注記や rapid_run の説明)に「並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED」の判定キーが書かれていれば D1-1 に揃える。「仮採用」「rdra-feedback #13」の注記を外す
- buc-spec.md(速報クロスチェックフロー): 情報 CRUD マトリクスに slot 実行(slot_executions)の R を UC-09 に追加。共有条件一覧の「中止済み run の比較依頼作成除外」の説明を D1-1 に合わせる

### D2. abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING を中止できる。worker の CLAIMED → RUNNING は条件付き UPDATE(CR-017。利用者決定 DIST-026 A)

RDRA: 条件「依頼中止可否判定」(速報 = REQUESTED / CLAIMED / RUNNING、確報 = RUNNING のみ。競合規則)、状態「クロスチェック依頼」CLAIMED → ABORTED(新設。遷移 UC「実行を ABORTED へ遷移させる」)、
REQUESTED → ABORTED(遷移経路に abort-rapid-crosscheck を追加)、CLAIMED → RUNNING(条件付き UPDATE。0 件なら比較を開始しない)、RUNNING → ABORTED / ABORTED(終端)の説明追記、
条件「slot 中止可否判定」(abort-rapid-crosscheck の対象 3 状態を追記)、情報「速報比較依頼」「中止指示」、バリエーション「中止対象種別」「停止確認応答」、
BUC「速報クロスチェックフロー」UC「比較ツールでジョブ単位比較を実行して結果を登録する」に条件「依頼中止可否判定」を関連付け。
USDM SPEC-010-02(受け入れ条件 5 件。AC2 / AC3 / AC4 / AC5 が今回追加。AC1 は既存)。arch SP-011 / SP-022 / LP-019 / LP-021 / LP-024(新規)/ L-rapid・L-ops の責務 / BC-004 / CM-005 / AG-002 / E-017 / E-024。

#### D2-1. 契約 `abort-rapid-crosscheck.sh`

- `--run-id` の description: 「依頼が REQUESTED / CLAIMED / RUNNING のとき ABORTED へ」
- 処理順: 現在状態 7 行の表示 → 停止確認(プロンプト文言は SPEC-010-03 のまま。REQUESTED の依頼には worker プロセスが無いが確認は省略しない)→ yes のときだけ
  `UPDATE rapid_crosscheck_requests SET status='ABORTED', completed_at=? WHERE run_id=? AND status IN ('REQUESTED','CLAIMED','RUNNING')` → 更新件数 1 で 0。続けて parallel_runs の併更新(`WHERE status IN ('STARTED','RUNNING')`。0 件で可)は従来どおり
- exit_codes: 0 の meaning に上記 SQL と「REQUESTED / CLAIMED / RUNNING のいずれからでも ABORTED にする(条件「依頼中止可否判定」)」を書く。3 の condition を「対象依頼が無い / 応答が yes 以外 / 管理 DB なし(RAPID_CROSSCHECK_MODE=off)/ 中止不可(SUCCEEDED / FAILED / ABORTED の終端状態。状態を変更せずエラー終了)/ 更新件数 0(表示後に終端した競合)」に改める
- stderr の `error: request is not abortable run_id=... role=rapid-crosscheck status=...(3)` は終端状態のときだけ出る旨を明記する
- idempotency: 「条件付き UPDATE(status IN ('REQUESTED','CLAIMED','RUNNING'))。CLAIMED を中止すると claim 済み worker の RUNNING 遷移(条件付き UPDATE)が 0 件になり比較を開始しない(rapid-crosscheck-worker.sh)。CLAIMED を放置すると lease 失効で REQUESTED に戻り別 worker が再 claim して比較が実行されるため、中止済み run の依頼は本コマンドで止める。再実行は終端済みで 3」。前イベントの「REQUESTED / CLAIMED は worker に処理させてから判断する」は削除する
- notes に判定表(arch LP-019。縦軸クロスチェック種別 = 速報 / 確報、横軸依頼状態 = REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)を書く: 速報 × REQUESTED / CLAIMED / RUNNING = 可、速報 × 終端 = 不可(3)、確報 × RUNNING = 可、確報 × それ以外 = 不可(3。abort-final-crosscheck.sh)

#### D2-2. 契約 `abort-final-crosscheck.sh`

- RUNNING のみ維持。exit 3 の condition に「RUNNING でない(REQUESTED / CLAIMED / 終端)は状態を変更せずエラー終了」を明記し、notes に「確報の未着手(REQUESTED / CLAIMED)依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限(FINAL_POLL_LIMIT_SEC)で扱う(条件「依頼中止可否判定」)」を追加する

#### D2-3. 契約 `rapid-crosscheck-worker.sh`(CLAIMED → RUNNING の条件付き UPDATE)

- claim 後・比較開始前の RUNNING 遷移は `UPDATE rapid_crosscheck_requests SET status='RUNNING', started_at=? WHERE run_id=? AND status='CLAIMED' AND worker_id=?`。**更新件数 0 なら比較ツールを起動せず、成果物ディレクトリと started-at.txt も作らず、comparison_results も INSERT せず、終了コード 0**(条件「依頼中止可否判定」。arch LP-024)
- 0 件のとき依頼を再 SELECT し、status = ABORTED(abort-rapid-crosscheck.sh で中止済み)なら実行ログ `WARN comparison not started run_id=... worker_id=... reason=request_aborted`、それ以外(lease 失効で別 worker に回収された = status が REQUESTED / 他 worker の CLAIMED / RUNNING)は既存の `WARN request not owned run_id=... status=...`。stderr には出さない(既存規則)。stdout(--once)は既存の形(claim の 4 行 + `request_status=<再 SELECT した現在の status>` / `result_status=-` / `exit_code=-` / `comparison_result_id=-` / `artifact_dir: -`)を維持する
- idempotency に「CLAIMED → RUNNING と RUNNING → 終端はいずれも status と worker_id を条件にした条件付き UPDATE。前者 0 件 = 中止済みまたは回収済みで比較を開始しない、後者 0 件 = 比較中に中止済みで comparison_results を INSERT しない」と整理する
- 既存の「終端 UPDATE 0 件(比較中に abort-rapid-crosscheck.sh で ABORTED)」の記述は変えない

#### D2-4. 契約 `shared_rules.state_codes.request_status_transitions`(正本。他ファイルはこれに揃える)

```text
- "(新規)→ REQUESTED(... 変更なし)"
- "REQUESTED → CLAIMED(... 変更なし)"
- "CLAIMED → REQUESTED(... 変更なし)"
- "CLAIMED → RUNNING(rapid-crosscheck-worker.sh / final-crosscheck-worker.sh の比較開始。条件付き UPDATE status='CLAIMED' AND worker_id=自 worker。速報は 0 件(abort-rapid-crosscheck.sh で ABORTED 済み、または lease 失効で回収済み)なら比較を開始せず comparison_results も登録しない)"
- "RUNNING → SUCCEEDED / FAILED(... 変更なし)"
- "REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck.sh。速報比較依頼のみ。停止確認 yes 後の条件付き UPDATE status IN ('REQUESTED','CLAIMED','RUNNING')。0 件 = 終端済みでエラー(3))"
- "CLAIMED → ABORTED(abort-rapid-crosscheck.sh。claim 済み速報比較依頼の中止。claim 済み worker は RUNNING への条件付き UPDATE が 0 件になり比較を開始しない。状態「クロスチェック依頼」CLAIMED → ABORTED)"
- "RUNNING → ABORTED(abort-final-crosscheck.sh。確報比較依頼のみ。条件付き UPDATE status='RUNNING'。REQUESTED / CLAIMED の確報比較依頼は中止できない)"
- "REQUESTED → ABORTED(abort-blue.sh / abort-green.sh。対象 run の未着手の速報比較依頼だけ。条件付き UPDATE status='REQUESTED'。0 件は正常。両系の完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険で、dispatcher 側の中止済み run 判定(rapid-crosscheck-runner.sh request_creation_matrix)と併用する。確報比較依頼には適用しない)"
```

(確報 worker の CLAIMED → RUNNING も条件付き UPDATE と書いてよいが、確報側の 0 件時の振る舞いは今回の CR の範囲外なので追記しない)

#### D2-5. `rdb-schema.yaml`

- `rapid_crosscheck_requests.status` の description の遷移を D2-4 に揃える(CLAIMED → ABORTED を追加。CLAIMED → RUNNING は条件付き UPDATE。REQUESTED / CLAIMED / RUNNING → ABORTED は abort-rapid-crosscheck)
- `rapid_runs.completion_status` の description の中止済み run の定義を D1-1 に揃える(並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED。同一トランザクションで parallel_runs.status と slot_executions.status を読む)
- 冒頭注記「終端 UPDATE の 0 件(依頼)」の隣に「比較開始 UPDATE の 0 件(速報依頼): rapid_crosscheck_requests の CLAIMED → RUNNING(WHERE status='CLAIMED' AND worker_id=?)が 0 件のときは abort-rapid-crosscheck により ABORTED 済み(または lease 失効で回収済み)とみなし、worker は比較ツールを起動せず comparison_results も INSERT せず終了コード 0」を追加
- 冒頭注記「未着手依頼の中止(abort-blue / abort-green)」を D3 の表現(競合窓の保険。dispatcher 側判定と併用)に改め、「CLAIMED / RUNNING は abort-rapid-crosscheck の対象のまま」を「REQUESTED / CLAIMED / RUNNING の明示中止は abort-rapid-crosscheck(status IN 条件付き UPDATE)」に改める
- 冒頭注記「ロック順」に abort-rapid-crosscheck を追加: rapid_crosscheck_requests(条件付き UPDATE status IN)→ parallel_runs(条件付き UPDATE status IN ('STARTED','RUNNING'))。worker(rapid_crosscheck_requests UPDATE → parallel_runs UPDATE)と同じ順なのでデッドロックしない。dispatcher の slot_executions 参照は「対象 slot の行の SELECT」に改める
- `datastore-schema.md` は編集しない(後で生成する)

#### D2-6. UC-23「実行を ABORTED へ遷移させる」/ UC-22「現在状態を確認して停止確認に応答する」

- UC-23: 分岐条件一覧の「クロスチェック依頼状態」行を「REQUESTED / CLAIMED / RUNNING = 中止可(abort-rapid-crosscheck)。RUNNING = 中止可(abort-final-crosscheck)。SUCCEEDED / FAILED / ABORTED = 不可(3)。確報の REQUESTED / CLAIMED = 不可(3)」に改める。「中止対象種別 = 速報比較依頼」行の SQL を D2-1 に。「依頼状態遷移規則」行を「REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck)/ RUNNING → ABORTED(abort-final-crosscheck)/ REQUESTED → ABORTED(abort-blue / abort-green。競合窓の保険)」に改める(「CLAIMED からの遷移は無い」を削除)
- UC-23: 状態遷移一覧に **CLAIMED → ABORTED(速報。abort-rapid-crosscheck.sh に yes と応答)の行を追加**し(適用 tier を空にしない。トレーサビリティの分母に新しい遷移パスが加わる)、RUNNING → ABORTED 行の trigger を速報 / 確報で分ける。関連 RDRA モデル表の状態「クロスチェック依頼」行を「REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck)/ RUNNING → ABORTED(abort-final-crosscheck)/ REQUESTED → ABORTED(abort-blue / abort-green。保険)」に。データフロー(mermaid)の DB ノードと SQL ラベルも揃える
- UC-23 BDD: USDM SPEC-010-02 の AC2「Given 速報比較依頼が REQUESTED または CLAIMED When abort-rapid-crosscheck を実行して yes と答える Then その依頼は ABORTED になり、worker は比較を開始しない」、AC4「Given 速報比較依頼が SUCCEEDED / FAILED / ABORTED の終端状態 When abort-rapid-crosscheck を実行する Then 状態を変更せずエラー終了する」、AC5「Given 確報比較依頼が RUNNING でない When abort-final-crosscheck を実行する Then 状態を変更せずエラー終了する」のシナリオを追加(既存の「SUCCEEDED の確報比較依頼は中止できない」は AC5 に対応づけてよい)。
  SPEC-010-01 の AC8「Given 両系の完了通知で速報比較依頼が REQUESTED で作成された直後 When 運用者が abort-blue または abort-green で slot を中止して yes と答える Then slot と依頼の両方が ABORTED になり、その後の完了通知でも速報比較依頼は再作成されない」のシナリオを追加(既存の AC6 相当のシナリオを拡張してもよい。シナリオ名末尾 `(SPEC-010-01)`)。「関連 USDM」表を SPEC-010-01(8 件)/ SPEC-010-02(5 件)に合わせる
- UC-23 tier-ops.md: abort-rapid-crosscheck の処理フロー・SQL・終了コードを D2-1 に、abort-final-crosscheck を D2-2 に、abort-blue / abort-green の REQUESTED 更新の説明を D3 に揃える。`_model-summary.yaml` の rapid_crosscheck_requests の operations 説明(status IN 条件)を揃える
- UC-22: abort-rapid-crosscheck の現在状態表示後の可否判定(「RUNNING でない依頼は 3」のような記述)を D2-1 の判定表に揃える。REQUESTED / CLAIMED の依頼も停止確認へ進む

#### D2-7. UC-11「比較ツールでジョブ単位比較を実行して結果を登録する」/ UC-10「速報比較依頼を claim する」

- UC-11: spec.md 関連 RDRA モデルに条件「依頼中止可否判定」の行を追加(適用 tier: tier-rapid-crosscheck。worker 側の競合規則 = CLAIMED → RUNNING の条件付き UPDATE 0 件で比較を開始しない)。分岐条件一覧「依頼状態遷移規則」行と状態遷移一覧の CLAIMED → RUNNING 行に「条件付き UPDATE(status='CLAIMED' AND worker_id=?)。0 件なら比較を開始せず comparison_results も登録しない」を書く。処理フロー(mermaid sequence)に 0 件分岐を追加
- UC-11 BDD: USDM SPEC-010-02 AC3「Given CLAIMED の速報比較依頼が abort-rapid-crosscheck で ABORTED になった When claim 済みの worker が RUNNING への条件付き UPDATE を行う Then 更新件数は 0 件で、worker は比較を開始せず終了する」のシナリオを追加(シナリオ名末尾 `(SPEC-010-02)`。stdout / 実行ログは D2-3)。「関連 USDM」表に SPEC-010-02 の行を追加
- UC-11 tier-rapid-crosscheck.md: 比較開始前の条件付き UPDATE と 0 件時の振る舞い(D2-3)を処理フローと実行ログ仕様に追加
- UC-10: 状態遷移一覧・関連 RDRA モデルに CLAIMED → ABORTED(abort-rapid-crosscheck。遷移 UC は UC-23)への言及があれば D2-4 に揃える(無ければ追加しない。遷移 UC は UC-23 のため UC-10 の分母には入らない)。lease 失効 → REQUESTED の説明に「中止済み run の CLAIMED 依頼は abort-rapid-crosscheck で止める」を 1 文添える
- buc-spec.md(速報クロスチェックフロー): 状態遷移全体図(mermaid stateDiagram)に CLAIMED → ABORTED を追加し、状態遷移 UC マッピングを更新。共有条件一覧に「依頼中止可否判定」を UC-11 に関連付ける
- buc-spec.md(実行中止フロー): 状態遷移全体図に CLAIMED → ABORTED(速報)を追加。REQUESTED → ABORTED の説明を D3 に

### D3. REQUESTED → ABORTED(abort-blue / abort-green)は「競合窓の保険」(CR-018。利用者決定 DIST-027 A)

RDRA: 状態「クロスチェック依頼」REQUESTED → ABORTED の説明を「両系の完了通知で依頼が作成された後に abort-blue / abort-green で slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」に変更。条件「slot 中止可否判定」も同旨。USDM SPEC-010-01 本文 / AC8。arch SP-022 / LP-021 / L-ops usecase 責務 / BC-004 / CM-005 / AG-002 / E-017 / E-024。

- 契約 `abort-blue.sh` / `abort-green.sh` の notes: 「REQUESTED → ABORTED は競合窓の保険(rdra-feedback #14): ...」を次に改める。
  「REQUESTED → ABORTED は競合窓の保険(条件「slot 中止可否判定」/ 状態「クロスチェック依頼」REQUESTED → ABORTED): 両系の完了通知で速報比較依頼が REQUESTED で作成された直後に運用者が slot を中止した場合の競合窓を塞ぐ。dispatcher 側の中止済み run 判定(rapid-crosscheck-runner.sh request_creation_matrix。対象 slot の slot 実行 ABORTED を判定キーに含む)と併用する。(以下、既存のロック順の説明 = 本コマンドは parallel_runs を無条件 FOR UPDATE でロックしてから条件付き UPDATE に進み、runner と直列化される、は残す)」
- 同 notes の「CLAIMED の依頼の再 claim(rdra-feedback #15): ...」は次に置き換える。「CLAIMED / RUNNING の依頼は本コマンドでは変更しない。REQUESTED / CLAIMED / RUNNING の速報比較依頼の明示中止は abort-rapid-crosscheck.sh(条件「依頼中止可否判定」。status IN 条件付き UPDATE)で行う。CLAIMED のまま残すと lease 失効で REQUESTED に戻り再 claim されるため、中止済み run の依頼は abort-rapid-crosscheck.sh で止める」
- 「両 slot 完了直後の抜けを防ぐ」「同時刻に起きた競合窓だけ」のような表現があれば「競合窓の保険」に統一する。「rdra-feedback #14」「#15」の参照を全て外す
- UC-23 spec.md / tier-ops.md / buc-spec.md(実行中止フロー)/ UC-08 の該当説明も同じ表現にする

### D4. RDRA フィードバック(`_cross-cutting/rdra-feedback.md`)の更新(cross-cutting subagent)

- #13 / #14 / #15 を「解消済み」表へ移す(反映先: feedback 20260907_abort_consistency CR-016 / CR-017 / CR-018。RDRA event 20260907_114000、USDM SPEC-005-02 / 010-01 / 010-02、arch event 20260907_122000。Spec 側の対応: 本イベントで注記を外し確定規則として記載)
- #9(方針資料 C2 図)は **利用者が図を修正済み**のため「解消済み」に移す(反映先: 方針資料の図修正(利用者)。Spec 側の対応: 変更なし。確報依頼は hang-detector の走査対象外のまま)
- 新規 #16(確認)を「残存」表に追加する: 対象 = 条件「中止済み run の比較依頼作成除外」の判定キー「完了通知の対象 slot の slot 実行 ABORTED」。変更内容 = 判定キーを「同 run のいずれかの slot の slot 実行 ABORTED」に広げるか確認。理由 = 対象 slot 限定だと次の経路で依頼が作られる: blue(foreground)実行中に background の green を abort-green で中止 → green の実装が走り切って完了通知を送る(対象 slot green が ABORTED なので依頼は作らず、完了事実 green_status=SUCCEEDED を記録)→ 後から blue が成功して完了通知を送る(対象 slot blue は ABORTED ではなく、parallel_runs も ABORTED ではない)→ 両系成功で依頼が作成される。Spec 側は RDRA の判定表どおり「対象 slot」で記載し、この経路は確認推奨項目として返す(仮採用は書かない)
- 冒頭の注記を本イベント(event 20260907_131000、RDRA event 20260907_114000 反映後)に更新する。「対応方針」の #13〜#15 の段落を削除し、#16 の方針(RDRA 側の判定キー拡張の要否は利用者判断。Spec は RDRA どおり)に置き換える。SR-001 / SR-002 はそのまま

**D4 の訂正(Step4-Review round 1 S4-traceability-4)**: #16 の経路は成立しない。foreground 実行中は parallel_runs が RUNNING で、abort-blue / abort-green の条件付き UPDATE(status IN ('STARTED','RUNNING'))により ABORTED になるため、後続の完了通知は「並行稼働実行 ABORTED」で除外される。foreground 中継後(COMPLETED)に中止できるのは background slot だけで、その完了通知は「対象 slot の slot 実行 ABORTED」で除外される。したがって #16 は登録せず、rdra-feedback.md の残存は SR-001 / SR-002 のみとする。確認推奨項目にも載せない。

### D5. USDM の今回追加分(配置 UC)

| SPEC | 受け入れ条件 | 配置 UC |
|---|---|---|
| SPEC-005-02 AC5 | 並行稼働実行は COMPLETED だが対象 slot の slot 実行が ABORTED → 依頼は作成されず完了事実だけ記録 | UC-09 |
| SPEC-005-02 AC6 | foreground blue 完了後に background green を abort-green で中止 → green の完了通知でも依頼は作成されず実行ログに警告 | UC-09 |
| SPEC-010-01 AC8 | 依頼が REQUESTED で作成された直後に slot を中止 → slot と依頼の両方が ABORTED、その後の完了通知でも再作成されない | UC-23 |
| SPEC-010-02 AC2 | REQUESTED / CLAIMED の速報比較依頼を abort-rapid-crosscheck で中止 → ABORTED、worker は比較を開始しない | UC-23 |
| SPEC-010-02 AC3 | CLAIMED の依頼が ABORTED になった後の worker の RUNNING 条件付き UPDATE → 0 件で比較を開始せず終了 | UC-11 |
| SPEC-010-02 AC4 | 終端状態の速報比較依頼を abort-rapid-crosscheck → 状態変更なしでエラー終了 | UC-23 |
| SPEC-010-02 AC5 | RUNNING でない確報比較依頼を abort-final-crosscheck → 状態変更なしでエラー終了 | UC-23 |

`usdm-acceptance-matrix.md` の集計値は USDM 正本から数え直す(`grep -c '^      - id: "SPEC-'` と `grep -c '^          - "Given'`)。

## 解消済み(注記を外す)

| 旧注記 | 今回の扱い |
|---|---|
| 「仮採用: rdra-feedback #13」「RDRA 条件は parallel_run の ABORTED のみを判定キーとしている」 | 削除。判定キーは D1-1(対象 slot)で確定 |
| 「rdra-feedback #14」(競合窓の保険) | 参照を外し、D3 の表現で確定 |
| 「rdra-feedback #15」(CLAIMED の再 claim) | 参照を外し、D2-1 / D3 の表現で確定(abort-rapid-crosscheck が止める) |
| UC-23「CLAIMED からの遷移は無い」 | 削除(CLAIMED → ABORTED を追加) |
| abort-rapid-crosscheck「REQUESTED / CLAIMED は worker に処理させてから判断する」 | 削除 |
