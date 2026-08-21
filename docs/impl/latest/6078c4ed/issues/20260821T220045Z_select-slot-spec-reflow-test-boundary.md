# select-slot 還流後仕様(spec 20260819_114307)の検証境界と UC 間依存

S2 test-scaffold(scoped 再実行・tier-facade)で gherkin を転写した際に判明した、仕様と検証境界が両立しない点。
いずれも blocker ではない(足場は生成済み)。S4 / S6 の着手前に判断が必要なものを列挙する。

## 1. 起動前監査ゲートの `SELECT ... FOR UPDATE` は SQLite 検証境界で実行できない

### 仕様の記載

- spec.md 処理フロー / tier-facade.md データモデル変更: audit_chain_heads の run_id 行を `SELECT ... FOR UPDATE` で排他ロックして previous_hash を確定し、同一 transaction で audit_logs INSERT と audit_chain_heads 更新を commit する
- RDB の正本は PostgreSQL(docs/infra/latest)

### 実装で判明した事実

- 既存の限定検証境界(issues/20260817T230000Z: JSON ジョブマップ・SQLite DSN・PATH 上の ssh)では `FOR UPDATE` が構文エラーになる。SQLite は行ロック構文を持たず、`BEGIN IMMEDIATE` による DB 全体の書込みロックで直列化する
- S2 の足場(tier BDD / UC BDD / bats)は SQLite スキーマで生成した。テストは「同一 transaction で commit / rollback される」ことだけを検証し、`FOR UPDATE` の有無は検証しない

### 提案

- RDB gateway で DSN 種別により `FOR UPDATE`(PostgreSQL)/ `BEGIN IMMEDIATE`(SQLite)を切り替える設計を S4 で採り、仕様側に「SQLite は検証境界限定。直列化は transaction 開始時の書込みロックで代替」を追記する
- PostgreSQL コンテナでの検証は CI 側の設計(エアーギャップは実行時制約であり CI のビルド時依存は許容)として S8 feedback で扱う

## 2. E2E Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」は後続 UC に依存する

### 仕様の記載

- spec.md E2E 完了条件: `blue foreground実行の待機中に、runner_results の (..., slot_type="green", role_type="background", ...) が status="RUNNING" で並走している`
- 同 spec.md 状態遷移一覧: 「STARTING以降の遷移(STARTING→RUNNING等)は後続UC『background roleを起動する』が担う」

### 実装で判明した事実

- 本 UC(tier-facade)単独では green の runner_results は STARTING のままであり、RUNNING への遷移は UC c3c7ab31(tier-worker 側のリモート runner)が実装されるまで観測できない
- S6 uc-bdd(本 UC の feature 全体を実行)では当該 Scenario が「未実装」ではなく「他 UC 未着手」を理由に fail する

### 提案

- S6 では当該 Scenario を UC c3c7ab31 完了後に結合する(実行順序の依存を uc-map または S6 の dispatch 条件に記録する)
- または feedback request で Then を「green への background 起動イベント送出が blue foreground 同期実行より先に完了し、green の runner_results が STARTING で存在する」へ改める

## 3. E2E Scenario 1 の credential_ref 期待値が Given に無い(軽微)

### 仕様の記載

- Then: `slot_execution_specs に (..., credential_ref="cred-blue-batch") と (..., credential_ref="cred-green-batch")`
- Given のジョブマップ記述には credential_ref の値が無い

### 実装で判明した事実

- テスト fixture(ジョブマップ)側で `cred-blue-batch` / `cred-green-batch` を補って足場を生成した。仕様の Given に値を追記する feedback を推奨する

## 4. tier-facade Scenario 2 は RAPID_CROSSCHECK_MODE 未設定のまま exit 2 を期待する(軽微)

### 仕様の記載

- Given は `BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka` のみ。RAPID_CROSSCHECK_MODE は必須環境変数

### 実装で判明した事実

- 同時 foreground の検証が必須環境変数の欠落検証より先に走る(またはどちらも exit 2)なら成立する。S4 では「バリデーションは全パラメータをまとめて検証し exit 2」(LP-001)として実装すれば矛盾しない。バリデーション順序の明記を feedback 候補とする

---

## S4 tier-impl(attempt 5)での対応状況と追加の仕様疑義

S4 で実装側に吸収した点と、仕様側の判断が要る点を追記する。実装は仕様を曲げていない(吸収した点はいずれも仕様の記載範囲内の実装判断)。

### §1 への対応(実装で吸収)

- `facade/src/rdb_gateway.sh` の `transaction_begin_sql` / `audit_chain_lock_sql` が DSN 種別で切り替える: PostgreSQL = `BEGIN;` + `SELECT ... FOR UPDATE`、SQLite = `BEGIN IMMEDIATE;` + `FOR UPDATE` 無しの SELECT。SQL 文字列の生成は単体テスト(`facade/test/6078c4ed_select_slot.bats` の `audit_chain_lock_sql_*`)で固定した
- ただし PostgreSQL クライアント(psql 等)はこの検証境界に配線していないため、`postgres://` DSN は `resolve_rdb_target` で業務エラー(exit 1)にしている。PostgreSQL 実行経路の検証は提案どおり CI 側の設計(S8 feedback)に委ねる
- 新規 run_id の監査チェーンは previous_hash=NULL から bash 側で算出し、`audit_chain_heads` の INSERT を同一 transaction に含める。万一同じ run_id の行が存在すれば主キー違反で transaction 全体が rollback されチェーンは分岐しない

### §3 への対応(fixture で吸収)

- tier BDD steps と bats のジョブマップ fixture に `credential_ref="cred-blue-batch"` / `"cred-green-batch"` を補った。仕様の Given への追記は引き続き feedback 候補

### §4 への対応(実装で吸収)

- `validate_select_slot_environment`(presentation 層)が BLUE_MODE / GREEN_MODE の列挙値・排他制約・RAPID_CROSSCHECK_MODE・RELAYGATE_OPERATOR を**まとめて**検証し、違反を全件 stderr に出して exit 2 にする。Scenario 2(RAPID_CROSSCHECK_MODE 未設定)は排他制約違反と併記で exit 2 になり成立する

### §5 監査イベントの正規化形式(event_hash の算出規則)が契約に無い(仕様側の判断が要る)

#### 仕様の記載

- audit-event-contract.yaml `event_hash`: 「正規化済みイベント本体と previous_hash から算出するハッシュ値」。hash_chain: 「定期検証ジョブが run_id ごとにチェーンを照合」

#### 実装で判明した事実

- 正規化形式(フィールド順・null 表現・区切り・ハッシュ関数)が未定義のため、定期検証ジョブ(別 UC)が同じ値を再計算できる保証が無い
- S4 では `facade/src/domain.sh` の `audit_event_canonical` / `audit_event_hash` に仮置きした: 契約 fields 順(event_id … error_code の 13 項目)を `|` 連結・null は空文字・末尾に `|previous_hash`(最初のイベントは空)を付け SHA-256 hex

#### 提案

- audit-event-contract.yaml に `hash_chain.canonical_form`(フィールド順 / null 表現 / 区切り / アルゴリズム)を追記し、verifier 側 UC と共有する

### §6 additional_args / fixed_args の保存形式(軽微)

#### 仕様の記載

- spec.md E2E: `additional_args に "--target-date 2026-08-18 --retry 3"`、`fixed_args に "--mode batch"` が保存される(空白区切りの 1 文字列)

#### 実装で判明した事実

- 単純な空白連結は空白・改行を含む引数で可逆性を失う。S4 では bash の `%q` 形式で連結した 1 文字列として保存・伝播する(上記の例は仕様どおりの文字列になり、空白を含む引数だけがクォートされる)

#### 提案

- 保存形式(`%q` 連結 or JSON 配列)を tier-facade.md のデータモデル変更表に明記する

### §7 foreground の同期実行と CLI 応答 10 秒以内(CTP-009)の両立(仕様側の判断が要る)

#### 仕様の記載

- spec.md E2E「blue実装のforeground実行が完了まで60秒かかる」「blue foreground実行の完了を待ってから終了コード 0」
- tier-facade.md ビジネスルール「CLI応答は10秒以内(CTP-009)」

#### 実装で判明した事実

- facade は全外部 I/O を単一 deadline(8 秒 + 補償予約)で打ち切る設計を引き継いでおり、SSH は「起動イベントの送出(handshake)」として扱う。60 秒の foreground 完了待ちは deadline 内に収まらない
- foreground 応答(stdout/stderr/exitcode)は別 UC「foreground roleの標準出力・標準エラー・終了コードを応答する」の責務であり、本 UC の tier BDD には含まれない

#### 提案

- 「10 秒以内」の対象を「起動受付の応答(STARTING まで)」に限定し、foreground 完了待ちは応答 UC 側の契約とすることを仕様に明記する(issues/20260817T230000Z の handshake 契約と併せて)

### §8 起動後の SSH 失敗・timeout の記録(実装判断。仕様側で確認が望ましい)

- 本 UC の仕様は STARTING 記録までを定め、起動後の遷移は後続 UC の責務としている。一方 SSH 送出が失敗したまま STARTING を残すと運用上の誤認を招くため、S4 では rdb-schema の状態モデルに従い、失敗= `attempt_failed` / FAILED(exit_code 付き)、timeout = `attempt_unknown` / UNKNOWN(推測で FAILED にしない)を runner_result_events + runner_results へ同一 transaction で補償記録する。起動後の監査イベント(slot_launch_failed 等)は契約上 emitted_by が「background roleを起動する」のため本 UC では追記しない(post_launch の outbox 退避も未実装)
- credential_ref は「参照名のみ保存」の契約に従い保存するだけで、SSH 接続の鍵解決には使っていない(解決方式が未契約)

### §9 旧テストの整理

- `facade/test/6078c4ed_select_slot.bats` の stale assertion(標準出力形式 / RUNNING / execution-spec.json / 旧スキーマ / FAILED 補償)は新仕様に合わせて更新した。RDB 書込み timeout は tier-facade.md の終了コード表に従い exit 124 へ改めた

---

## S4 tier-impl(attempt 6)での対応状況(S5 attempt 5 findings F-001 / F-002 / F-003)

### §1 の更新: PostgreSQL 経路を実装した(F-001。「psql 未配線」の記述は本節で置き換える)

- `facade/src/rdb_gateway.sh` の `resolve_rdb_target` が `postgresql://` / `postgres://` DSN を受け付け、`psql -X -q -w -v ON_ERROR_STOP=1 -d <DSN> -c <SQL>` で起動トランザクションを**単一リクエスト**として送る(psql の `-c` 文字列は単一リクエストとして送られ、途中のエラーで残りは実行されず未 commit 分は rollback される。PostgreSQL 17 app-psql 参照)。psql が PATH に無い場合は `reason=postgresql_client_unavailable`(exit 1)、接続不能(psql exit 2)は `reason=connection`(exit 1)、CLI deadline 超過は exit 124
- transaction の内容は契約どおり: `BEGIN;` → execution_specs / slot_execution_specs INSERT → slot ごとの runner_result_events + runner_results INSERT → `SELECT head_hash FROM audit_chain_heads WHERE run_id = ... FOR UPDATE;` → audit_logs INSERT ごとに audit_chain_heads の INSERT(run 内 1 件目)/ UPDATE(2 件目以降)→ `COMMIT;`
- 実 PostgreSQL での実体テストを `facade/test/6078c4ed_select_slot_postgresql.bats` に追加した(テストファイルごとに `initdb` + `pg_ctl` の一時インスタンス、または `RELAYGATE_TEST_PG_BACKEND=docker` で postgres:16-alpine。`log_statement=all` の statement ログで FOR UPDATE と単一リクエストを検証)。起動不能な環境では skip せず fail にする(`RELAYGATE_TEST_SKIP_PG=1` の明示 skip のみ許可)
- **CI への影響(write-set 外のため未対応)**: `.github/workflows/ci.yml` の tdd ジョブで PostgreSQL バイナリ(`initdb` / `pg_ctl` / `psql`)を PATH に載せる必要がある(ubuntu runner は `/usr/lib/postgresql/<ver>/bin` にプリインストール済みだが PATH 外)。オーケストレータ側で CI 設定の追従を要する

### §10 テスト用 DDL の所有と共有(仕様側 / datastore_owner の判断が要る)

#### 仕様の記載

- impl-config.yaml `datastore_owner: tier-worker`。migration の正本は `worker/migrations/`(現時点は空)
- rdb-schema.yaml は論理型(uuid / string / text / integer / datetime)のみを定義し、PostgreSQL の物理型は未定義

#### 実装で判明した事実

- tier-facade の PostgreSQL 実体テストには DDL が必要だが、正本の migration が未着手で、`worker/` は tier-facade の write-set 外
- S4 では `facade/test/fixtures/generate-postgresql-schema.py` が rdb-schema.yaml の transaction_rules「slot起動トランザクション」の tables(6 テーブル)から `facade/test/fixtures/relay-gate-db.postgresql.sql` を生成した(型対応: uuid → uuid / string → text / text → text / integer → integer / datetime → timestamptz。PK / UNIQUE / FK / index を含む)。fixture 先頭に「テスト fixture。正本は rdb-schema.yaml / worker/migrations」を明記している
- run_id / event_id が `uuid` 型のため、`RELAYGATE_ID_GENERATOR` で固定する run_id は UUID 形式でなければならない(attempt_id は string 型のため任意文字列でよい)

#### 提案

- tier-worker が `worker/migrations/` を整備した時点で、tier-facade の fixture を migration からの生成(または migration そのものの適用)へ切り替え、物理型の対応表(特に datetime → timestamptz、string → text)を rdb-schema.yaml か migration 側に正本として明記する
- それまでは rdb-schema.yaml の変更(S3 再生成)時に本生成器で fixture を再生成する運用とする

### §8 の更新: 起動後の SSH 失敗 / timeout の補償記録を撤回し仕様どおり STARTING 固定に戻した(F-003。仕様側の判断が要る)

#### 仕様の記載

- tier-facade.md 標準出力契約「status=STARTING を選択 slot ごとに 1 行」、データモデル変更「status 固定値 STARTING(本 UC 時点。RUNNING 以降への遷移は後続 UC が担う)」

#### 実装で判明した事実(attempt 6 の実装)

- attempt 5 で実装していた「SSH 失敗 = FAILED / attempt_failed、timeout = UNKNOWN / attempt_unknown の補償記録」と stdout の status 可変出力を削除した。`facade/src/launch_gateway.sh` は送出失敗を stderr の診断情報(`boundary=ssh, reason=ssh_failure, ssh_exit=<code>` または `reason=timeout`)と終了コード 1 で応答するだけで、runner_results / runner_result_events の STARTING 記録は変更しない。補償用の deadline 予約(`COMPENSATION_RESERVE_MILLISECONDS`)も不要になり削除した
- 終了コードは tier-facade.md の表に従う: 起動先接続失敗 = 1(業務エラー)。124 は RDB 接続タイムアウトのみ

#### 仕様側に委ねる論点

- 起動イベントの送出に失敗した slot が `STARTING` のまま残る。後続 UC「background roleを起動する」/ hang-detector が「started_at が無いまま一定時間経過した STARTING」をどう扱うか(UNKNOWN 遷移や `slot_launch_failed` 監査イベントの emitted_by)が未定義のため、いずれかが必要: (a) 本 UC に起動失敗時の補償記録(runner_result_events + runner_results の FAILED / UNKNOWN、audit_logs の slot_launch_failed / slot_launch_timeout)を仕様として追加する、(b) hang-detector の検知条件として「STARTING の滞留」を仕様化する。実装は仕様の決定まで STARTING 固定を維持する

### §11 runner_result_events.occurred_at のサブ秒精度(F-002。実装で吸収)

- 秒精度の `date -u` では同一秒内のイベント順序が定まらない(F-002)。契約型 `datetime` が保持できるマイクロ秒精度の UTC ISO 8601(`YYYY-MM-DDTHH:MM:SS.ffffffZ`)を `facade/src/id_gateway.sh` の `clock_now_utc`(perl Time::HiRes)で生成し、accepted_at / occurred_at / updated_at / 監査 occurred_at に同一値を記録する。PostgreSQL の timestamptz はこの形式をそのまま受け付ける(実体テストで確認)
- F-003 の対応で本 UC が記録する履歴は slot ごとに attempt_started の 1 件だけになり、順序依存の assertion は無くなった。テストは時系列順を前提にせず内容で検証する

---

## S6 uc-bdd での対応状況(§2 / §7 のハーネス注入)

UC BDD(`features/uc/select-and-launch-slots-by-feature-flags.feature`、9 Scenario)を tier-facade attempt 6 の実装に結線した。tier 実装は変更していない。8 Scenario は実装そのものの振る舞いで成立し、Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」だけは本 UC 単独で成立しないため ssh スタブへハーネス注入した。

### 注入箇所

- `features/uc/steps/select-and-launch-slots-by-feature-flags.steps.cjs` の `SSH_STUB_CONCURRENT`(Given「blue実装のforeground実行が完了まで60秒かかる状態である」で PATH 先頭の ssh スタブを差し替える)。注入箇所には本 issue への参照と「暫定注入・契約確定後に削除」のコメントを付けた
- スタブは SSH 先の remote runner(UC c3c7ab31 / tier-worker)を模擬する: green(background)の起動イベント受領時に runner_results を RUNNING へ遷移(runner_result_events に attempt_running を追記)し、60 秒の background 実行を detached プロセスで模擬する。blue(foreground)の起動イベント受領時に green の status を記録する

### Then ごとの検証範囲

| Then | 検証 | 根拠 |
|---|---|---|
| green background 起動イベントが blue foreground より先に送出される | 実装の振る舞いで成立(起動ログの順序) | 注入なし。`facade/src/domain.sh` select_slot_roles の起動順 |
| blue foreground 待機中に green が RUNNING で並走 | 注入スタブが遷移させた RUNNING を、blue 起動時点のスナップショットで検証 | §2(RUNNING 遷移は UC c3c7ab31 の責務) |
| blue foreground 完了を待ってから exit 0、green 完了は待たない | **部分検証**: exit 0 と「green の完了を待たない(CLI 終了後も green の detached 実行が継続)」のみ。「blue foreground の完了を待つ」は検証していない | §7(facade の SSH は起動受付の handshake で上限 8 秒。60 秒の完了待ちは応答 UC「foreground roleの標準出力・標準エラー・終了コードを応答する」の責務) |

### 仕様側に委ねる論点(§2 / §7 の再掲)

- 本 Scenario の Then 2 行目・3 行目は本 UC(tier-facade の起動受付)の範囲を超える。UC c3c7ab31(RUNNING 遷移)と応答 UC(foreground 完了待ち)が実装された時点で注入を外し、UC 横断の統合(または ATDD)で再検証する運用を推奨する
- もしくは feedback request で本 Scenario の Then を「green への background 起動イベント送出が blue foreground の起動イベント送出より先に完了し、green の runner_results が STARTING で存在する。CLI は green の完了を待たずに終了コード 0 で終了する」へ改める

### その他(注入なしで成立した点の補足)

- 「facade本体のコード・設定はジョブマップ以外に一切変更されていない」は、同一の `facade/bin/relaygate` をハーネス基準以外の RELAYGATE_* 設定を足さずに実行することの確認として結線した(ソースツリーのハッシュ比較は同一 Scenario 内では自明なため行わない)
- 「green実装への起動イベントは slot_execution_specs の値のみから構成され…」は、起動ログの remote_command が `cd <work_dir> && <run 実行コンテキスト env> <script_path> [<fixed_args>]` の形で DB 行の値と一致し、impl_version・実装名を含まないことで検証した。run 実行コンテキスト(RELAYGATE_RUN_ID / ATTEMPT_ID / SLOT / ROLE / RAPID_CROSSCHECK_MODE)は slot_execution_specs 外の値だが、実装固有の分岐ではなく run 共通の伝播項目として許容した。credential_ref は起動コマンドに現れない(§8: 鍵解決方式が未契約)
