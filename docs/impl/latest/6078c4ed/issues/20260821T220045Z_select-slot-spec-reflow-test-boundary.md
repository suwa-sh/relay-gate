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
