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
