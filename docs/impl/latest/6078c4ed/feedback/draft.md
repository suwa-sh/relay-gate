---
schema_version: distillery.feedback-request/v1
feedback_id: 20260822_085257_impl_feedback_6078c4ed
created_at: 2026-08-22T08:52:57+09:00
source: distillery-impl
uc_id: 6078c4ed
---

# 実装からの変更要求

本書は、仕様還流(`20260818_113601_impl_feedback_6078c4ed` と `20260818_164000_rdra_followup_6078c4ed`)を反映した仕様(spec `20260819_114307`)に対する再実装で判明した、仕様側の未定義・矛盾をまとめた新規の変更要求である。反映済みの要求(CR-6078c4ed-001〜010)は再掲しない。

実装の到達点(前提として扱うこと):

- `relaygate concurrent-run select-slot` は実 PostgreSQL に対し、execution_specs / slot_execution_specs の INSERT、選択 slot ごとの runner_result_events + runner_results の STARTING 記録、audit_chain_heads の run_id 行の `SELECT ... FOR UPDATE`、audit_logs INSERT と audit_chain_heads 更新を単一 transaction で commit してから外部 slot を起動する
- 独立検証(blocker 0 件)、UC 統合テスト 9 Scenario、受け入れテスト 6 Scenario が pass している
- 本書の要求は、この到達点を変更せず、複数 UC が共有する契約の欠落と、本 UC の責務境界を超える記述を仕様側で確定することを求める

## CR-6078c4ed-011: 監査イベント event_hash の正規化形式を契約に定義する

- severity: blocker
- related_ids: [CTP-004, CTR-008, product.audit_event_persistence]
- related_files: [docs/specs/latest/_cross-cutting/api/audit-event-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`docs/specs/latest/_cross-cutting/api/audit-event-contract.yaml` の `event_hash`(70 行付近)は「正規化済みイベント本体と previous_hash から算出するハッシュ値」、`hash_chain`(163 行付近)は「定期検証ジョブが run_id ごとにチェーンを照合して欠損・改ざんを検知する」と定めている。正規化形式(対象フィールドと順序、null の表現、区切り、ハッシュ関数、出力表現)はどの契約にも無い。

実装(`facade/src/domain.sh` の `audit_event_canonical` / `audit_event_hash`)は、契約 `fields` の順(event_id から error_code までの 13 項目)を `|` で連結し、null は空文字、末尾に `|previous_hash`(最初のイベントは空)を付けた文字列の SHA-256 を 16 進小文字で記録する仮置きの形式で実 PostgreSQL のテストを通過させている。

### 現在の仕様と問題

同じ run_id のチェーンには、本 UC のほかに「background roleを起動する」「background実行の未完了・非0終了・速報比較異常を定期検知する」「中止」「リラン」の各 UC が追記する(`emitted_by`)。正規化形式が未定義のままでは、UC ごとの実装が異なる文字列をハッシュし、同一 run_id のチェーンが分岐する。定期検証ジョブも event_hash を再計算できず、契約の目的である欠損・改ざん検知が成立しない。

### 変更してほしいこと

`audit-event-contract.yaml` の `hash_chain` に正規化形式を定義する。最低限次を確定する。

- ハッシュ対象フィールドの集合と順序(event_hash 自身と previous_hash を除く本体フィールドの順序)
- null / 非該当(`-`)の表現、フィールド区切り、値に区切り文字が含まれる場合のエスケープ
- previous_hash の連結位置と、最初のイベント(previous_hash=null)での表現
- ハッシュ関数と出力表現(例: SHA-256、16 進小文字 64 桁)
- 検証ジョブが `audit_logs` の行から同じ値を再計算できることを保証する旨

採用案: 実装で採用した仮置きの形式(契約 `fields` 順の 13 項目を `|` で連結、null は空文字、末尾に `|previous_hash`(最初のイベントは空)、SHA-256 を 16 進小文字 64 桁で表現)をそのまま正規化形式として契約化する。値に `|` が含まれる場合のエスケープ規則は契約側で補う。全 emitter と検証ジョブはこの定義だけを参照する。

### 完了条件

監査イベントを追記するすべての UC と検証ジョブが、契約の記述だけから同一の event_hash を推測なしに算出でき、実 PostgreSQL に保存された行から再計算した値が保存値と一致する。

## CR-6078c4ed-012: 起動イベント送出失敗で STARTING のまま残る試行の扱いを定義する

- severity: blocker
- related_ids: [SPEC-001-01, LR-002, CTR-008]
- related_files: [docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md, docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/foreground roleの標準出力・標準エラー・終了コードを応答する/spec.md, docs/specs/latest/実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md, docs/specs/latest/_cross-cutting/api/audit-event-contract.yaml]

### 観測した事実

本 UC の tier-facade 仕様は、標準出力契約を「status=STARTING を選択 slot ごとに 1 行」、データモデルを「status 固定値 STARTING(本 UC 時点。RUNNING 以降への遷移は後続 UC が担う)」、終了コードを「起動先接続失敗 = 1(業務エラー)」と定めている。独立検証は、起動後に FAILED / UNKNOWN を補償記録していた実装を仕様違反(blocker)と判定し、実装は仕様どおり STARTING 固定へ戻した。

現在の実装(`facade/src/launch_gateway.sh`)は、SSH による起動イベントの送出失敗・timeout を stderr の診断と終了コード 1 で応答するだけで、runner_results / runner_result_events / audit_logs には何も追記しない。commit 済みの STARTING 行と `slot_launch_attempted` 監査イベントは残る。

`audit-event-contract.yaml` では `slot_launch_failed` / `slot_launch_timeout` の `emitted_by` が「background roleを起動する」のみであり、本 UC は発行できない。

### 現在の仕様と問題

送出に失敗した試行が STARTING のまま残った後の扱いが、role ごとに次のように食い違う、または欠落している。

- background role: 「background実行の未完了・非0終了・速報比較異常を定期検知する」UC が `status IN ('STARTING','RUNNING','UNKNOWN') AND role_type='background'` を走査し、started_at が無い場合は accepted_at からの経過でハング疑いを検知する。STARTING 滞留は検知対象に含まれるが、「起動イベントが届かなかった試行」と「起動したが遅い試行」を区別する記述は無い
- foreground role: 「foreground roleの標準出力・標準エラー・終了コードを応答する」UC は最新試行の status が STARTING の間は退避コード 125 で応答し続ける。foreground の STARTING 滞留を検知・確定する UC は無く、起動失敗が永続的に「未確定」として扱われる
- 監査: 本 UC の起動失敗を記録する監査イベントが無く、`slot_launch_attempted` の後にどのイベントも続かない run が正常な系譜と区別できない

このため、運用者がジョブスケジューラの終了コード 1 を見た後に、RDB と監査ログから「何が起きたか」を確定できない。

### 変更してほしいこと

採用案: 本 UC が起動イベントの送出失敗 / timeout を補償記録する。

- runner_result_events + runner_results を同一 transaction で FAILED(送出失敗、attempt_failed)/ UNKNOWN(timeout、attempt_unknown。推測で FAILED にしない)へ遷移させる
- `slot_launch_failed` / `slot_launch_timeout` の `emitted_by` に本 UC を追加する
- 起動後の監査追記失敗はローカル永続 outbox へ退避する既存の `post_launch` 契約に従う
- 標準出力契約(status=STARTING 行)と終了コード表(起動先接続失敗 = 1)を維持するか変更するかを明記する

「本 UC は STARTING 固定を維持し、STARTING 滞留の検知・確定を後続 UC の責務とする」案は採用しない。

### 完了条件

起動イベントの送出失敗・timeout 後の runner_results の status、runner_result_events の履歴、audit_logs のイベントと emitter、foreground / background それぞれの後続 UC の挙動が仕様から一意に決まり、本 UC と後続 UC を同じ前提で実装できる。

## CR-6078c4ed-013: E2E Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」の責務境界と CLI 応答時間を整合させる

- severity: spec-gap
- related_ids: [SPEC-001-01, CTP-009, B.2.1.1]
- related_files: [docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md, docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md, docs/specs/latest/_cross-cutting/uc-dependencies.md]

### 観測した事実

spec.md の当該 Scenario は、Given「blue 実装の foreground 実行が完了まで 60 秒かかる状態である」に対し、Then で「blue foreground 実行の待機中に green の runner_results が status=RUNNING で並走している」「blue foreground 実行の完了を待ってから終了コード 0 で終了し、green background 実行の完了は待たない」を求めている。

一方、同 spec.md の状態遷移一覧は「STARTING 以降の遷移は後続 UC『background roleを起動する』が担う」、tier-facade.md のビジネスルールは「CLI 応答は 10 秒以内(CTP-009)」と定めている。

実装は全外部 I/O を単一 deadline(8 秒)で打ち切り、SSH を起動イベントの送出として扱う。UC 統合テストでは、この Scenario だけが本 UC 単独で成立せず、ssh スタブに「background 起動受領時に green を RUNNING へ遷移させ 60 秒の実行を模擬する」ハーネスを注入して通過させた(`features/uc/steps/select-and-launch-slots-by-feature-flags.steps.cjs` の `SSH_STUB_CONCURRENT`)。「blue foreground の完了を待つ」は検証していない。

### 現在の仕様と問題

Then の 2 行目(green が RUNNING)は「background roleを起動する」UC の責務、3 行目(foreground 完了待ち)は「foreground roleの標準出力・標準エラー・終了コードを応答する」UC の責務であり、本 UC 単独では観測できない。3 行目は 60 秒の同期待ちを要求しており、「CLI 応答は 10 秒以内」と同じ tier 仕様の中で両立しない。

「CLI 応答 10 秒以内」の対象が「起動受付(STARTING まで)の応答」なのか「foreground の完了を含む応答」なのかも未定義である。

### 変更してほしいこと

採用案として次を確定する。

- 「CLI 応答は 10 秒以内」の対象を、本 UC では「起動受付(transaction commit と起動イベント送出)までの応答」に限定する旨を明記する。foreground 完了までの待機時間の上限は、foreground 応答 UC 側の契約(hang_detect_limit_minutes との関係を含む)として定義する
- 当該 Scenario の Then を本 UC の責務内に改める: 「green への background 起動イベント送出が blue への foreground 起動イベント送出より先に完了する」「green の runner_results が STARTING で存在する」「CLI は green の完了を待たずに終了コード 0 で終了する」
- 元の Then(green の RUNNING 並走、blue 完了待ち)を検証する場所を、UC 横断の統合シナリオ(依存先: background 起動 UC、foreground 応答 UC)として `uc-dependencies.md` または該当 BUC の仕様に移す

### 完了条件

本 UC の E2E Scenario がすべて本 UC の tier 実装だけで(ハーネス注入なしに)成立し、CLI 応答時間の対象範囲が本 UC と foreground 応答 UC の間で矛盾なく定義されている。

## CR-6078c4ed-014: additional_args / fixed_args の保存形式と引数復元規則を定義する

- severity: spec-gap
- related_ids: [SPEC-009-01, SPEC-009-02]
- related_files: [docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md]

### 観測した事実

spec.md の Scenario「job map の固定引数の後ろに追加引数を順序を変えず連結する」は、`additional_args` に `"--target-date 2026-08-18 --retry 3"`、`fixed_args` に `"--mode batch"` が保存されることを求めている(空白区切りの 1 文字列)。`rdb-schema.yaml` の両カラムは `text` 型で、保存形式の記述は無い。ジョブマップ側の `fixed_args` は Given で `["--mode", "batch"]`(配列)と書かれている。

実装は、空白や改行を含む引数でも可逆に復元できるよう、各引数を bash の `%q` 形式でクォートして空白連結した 1 文字列として保存・伝播している。Scenario の例では空白を含む引数が無いため、仕様どおりの文字列になる。

### 現在の仕様と問題

保存形式が未定義のため、引数に空白・引用符・改行が含まれる場合の復元規則が UC 間で一致しない。`additional_args` / `fixed_args` を読んで起動引数を再構成するのは、本 UC のほかに「background roleを起動する」UC(worker)と「リラン」UC であり、書き手と読み手が別形式を採ると引数が壊れる。

### 変更してほしいこと

採用案: `rdb-schema.yaml` の `execution_specs.additional_args` と `slot_execution_specs.fixed_args` の保存形式を JSON 配列(例: `["--target-date","2026-08-18","--retry","3"]`)と定義し、復元は要素順をそのまま argv にする。空白・引用符・改行を含む引数の往復が同一であることを要件に含め、E2E Scenario の期待値を JSON 配列に合わせて更新する。実装の `%q` 連結(bash 専用)は採用しない。

### 完了条件

書き手(本 UC)と読み手(background 起動 UC、リラン UC)が同じ仕様から同じ復元規則を実装でき、空白・引用符・改行を含む引数の往復テストが仕様値で書ける。

## CR-6078c4ed-015: rdb-schema の論理型に対する PostgreSQL 物理型と datetime 精度を正本に定義する

- severity: spec-gap
- related_ids: [LR-002, CTP-006]
- related_files: [docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/_cross-cutting/datastore/datastore-schema.md, docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml]

### 観測した事実

`rdb-schema.yaml` は論理型(uuid / string / text / integer / datetime)のみを定義し、PostgreSQL の物理型は定義していない。`runner_result_events.occurred_at` は「履歴の時系列順序の基準」、`runner_results.updated_at` は「対応する runner_result_events.occurred_at と一致させる」と定められているが、時刻の精度は無い。

独立検証で、秒精度の occurred_at では同一秒内のイベント順序が定まらず、履歴順序を検証するテストが不安定に失敗した(blocker)。実装はマイクロ秒精度の UTC ISO 8601(`YYYY-MM-DDTHH:MM:SS.ffffffZ`)を生成し、timestamptz に保存することで解消した。

実 PostgreSQL のテストには DDL が必要だが、migration の正本(`worker/migrations/`)は未整備で、本 UC の tier からは書き込めない。実装は `rdb-schema.yaml` から `facade/test/fixtures/generate-postgresql-schema.py` で DDL を生成し(uuid → uuid、string → text、text → text、integer → integer、datetime → timestamptz)、テスト fixture として使用している。

### 現在の仕様と問題

物理型の対応表と datetime 精度が正本に無いため、migration を書く tier と fixture を生成する tier が独立に型を選ぶ。datetime の精度が秒なら履歴順序の契約(occurred_at を順序基準とする)が成立せず、tier 間で精度が異なれば「updated_at と occurred_at を一致させる」契約が壊れる。run_id / event_id の `uuid` 型は、識別子の発番形式(UUID 文字列でなければならない)を暗黙に拘束しており、この拘束も記述されていない。

### 変更してほしいこと

採用案として `rdb-schema.yaml`(または `datastore-schema.md`)に次を定義する。

- 論理型 → PostgreSQL 物理型の対応表: uuid → uuid、string → text、text → text、integer → integer、datetime → timestamptz
- datetime の精度はマイクロ秒、保存時刻の基準は UTC、表現は ISO 8601
- 同一 transaction で記録する複数の時刻カラム(accepted_at / occurred_at / updated_at)を同一値にする規則
- uuid 型カラムに保存する識別子が RFC 4122 形式の UUID 文字列であること

あわせて、migration(datastore 所有 tier)とテスト fixture の双方がこの対応表から生成される旨を明記する。CR-6078c4ed-018 で `job_map_version` を slot_execution_specs へ移す列変更も、同じ対応表(string → text)に従う。

### 完了条件

migration と各 tier のテスト DDL が同じ対応表から生成でき、同一秒内に発生した履歴イベントの順序が occurred_at だけで一意に決まり、時刻カラム間の一致契約を実 PostgreSQL で検証できる。

## CR-6078c4ed-016: USDM SPEC-009-03 の文言を execution spec の分離保存と run 共通の hang_detect_limit_minutes に合わせる

- severity: spec-gap
- related_ids: [SPEC-009-03, REQ-009]
- related_files: [docs/usdm/latest/requirements.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`docs/usdm/latest/requirements.yaml` の SPEC-009-03(402 行付近)は「…・role ごとの hang_detect_limit_minutes を execution-spec.json として保存する」と定めている。

spec.md の関連 RDRA モデルは「情報 execution-spec.json — run 共通の execution_specs と slot 別の slot_execution_specs に分離して保存する」、`rdb-schema.yaml` は `hang_detect_limit_minutes` を execution_specs(run 共通)の 1 列として定義し、role / slot 別の列は無い。

実装は execution-spec.json ファイルを生成せず RDB の 2 テーブルへ保存する。hang_detect_limit_minutes はジョブマップの job 直下の 1 値として解決・保存している。受け入れテスト(SPEC-009-03-1)はこの 2 テーブルの実体で検証した。

### 現在の仕様と問題

要求正本(USDM)が「execution-spec.json」というファイルと「role ごと」のしきい値を求めるのに対し、仕様とデータストア契約は「RDB の 2 テーブル」と「run 共通の 1 値」である。受け入れ基準の読み手が USDM の文言どおりにファイルと role 別の値を期待すると、実装は受け入れ基準を満たさないと判断される。

### 変更してほしいこと

採用案: SPEC-009-03 の文言を仕様に合わせる。「execution spec(run 共通の execution_specs と slot 別の slot_execution_specs)として RDB に保存する」「hang_detect_limit_minutes は run 共通の 1 値として保存する」と改め、受け入れ基準の「execution-spec.json に…保存され」も同様に改める。rdb-schema に role 別のしきい値列を追加する案は採用しない。

run 共通の 1 値の出所は CR-6078c4ed-018 で確定する(background に選ばれた slot のジョブマップの `hang_detect_limit_minutes` を採用する)。SPEC-009-03 の文言もこの出所と矛盾しない表現にする。

### 完了条件

USDM の SPEC-009-03 と受け入れ基準、spec.md、rdb-schema.yaml が同じ保存先と粒度(run 共通 / slot 別)を記述し、受け入れテストの検証対象と一致する。

## CR-6078c4ed-017: credential_ref から SSH 認証情報を解決する契約と、E2E Given の credential_ref 値を定義する

- severity: spec-gap
- related_ids: [SPEC-009-03, CTP-001]
- related_files: [docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md, docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/background roleを起動する/tier-worker.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

`slot_execution_specs.credential_ref` は「認証情報の参照名のみを保存する(実値は保存しない)」と定められている。本 UC の tier-facade.md は SSH 経由で slot を起動すると定めるが、環境変数表に SSH 認証に関する項目は無く、credential_ref から鍵・認証情報を解決する方法の記述も無い。一方、「background roleを起動する」UC の tier-worker.md は `RELAYGATE_SSH_KEY_PATH`(blue/green 実装ホストへの SSH 接続鍵パス)を必須環境変数として定めている。

実装は credential_ref を保存するだけで、SSH 接続の鍵解決には使っていない(解決方式が未契約のため)。E2E Scenario の Then は `credential_ref="cred-blue-batch"` / `"cred-green-batch"` を期待するが、Given のジョブマップ記述にこの値は無く、テスト fixture 側で補っている。

### 現在の仕様と問題

credential_ref が「参照名」として何を参照するのか(鍵ファイルのパス、ssh_config の Host エイリアス、認証情報ストアのキー)が未定義であり、本 UC(facade からの SSH)と background 起動 UC(worker からの SSH)で認証方式が一致する保証が無い。tier-facade と tier-worker で別の環境変数体系になると、同じ slot へ 2 通りの認証設定を運用することになる。

### 変更してほしいこと

採用案として次を cross-cutting の契約(CLI コマンド契約または実行境界の契約)として定義する。

- credential_ref の解決規則: ジョブマップ外の認証情報ディレクトリを参照名で引く(認証情報ディレクトリ方式)。実値はジョブマップ・RDB・監査・標準出力・起動イベントに現れない。ssh_config の Host エイリアス方式は採用しない
- facade と worker で共通の環境変数名(`RELAYGATE_SSH_KEY_PATH` の扱いを含む)と、credential_ref が null の場合の既定動作
- E2E Scenario の Given のジョブマップ記述に `credential_ref` の値(cred-blue-batch / cred-green-batch)を追記する

### 完了条件

facade と worker が同じ契約から credential_ref の解決を実装でき、認証情報の実値が保存・出力されないことを同じ検証方法で確認でき、E2E Scenario の Given だけから Then の credential_ref 期待値が導ける。

## CR-6078c4ed-018: ジョブマップを slot ごとの独立ファイルとして契約化し、job_map_version を slot 別に保存する

- severity: spec-gap
- related_ids: [SPEC-009-01, REQ-009]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md]

### 観測した事実

`cli-command-contract.yaml` と tier-facade.md は `RELAYGATE_JOB_MAP_PATH`(ジョブマップファイルパス)を 1 つだけ定義し、spec.md の Given は「ジョブマップ v1.4.0 で job_id が blue(host=…, impl_version=…)と green(…)に解決できる」と記述する。`rdb-schema.yaml` は `job_map_version` を `execution_specs`(run 共通)の列として定義し、「実行先解決に使用したジョブマップのバージョン」と説明している。ジョブマップのファイル形式(JSON / YAML)、トップレベル構造、job ごとの必須フィールド、slot ごとの項目(host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref)と hang_detect_limit_minutes の位置は、どの正本にも無い。

実装は限定検証境界として、blue / green を 1 ファイルに持つ JSON の slot-entry 形式(`facade/src/job_map_gateway.sh` のヘッダコメントに記載)を採用し、jq でフィールド名を指定して読む。`job_map_version` は 1 ファイルの 1 値を run 共通として保存し、`hang_detect_limit_minutes` は job 直下の 1 値として解決している。未知のフィールドは無視され、形式の厳格検証は行っていない。受け入れテストでは、facade が読まない余剰フィールドに秘密鍵風の値を混入させ、RDB・起動イベント・標準出力に現れないことを確認した。

### 現在の仕様と問題

ジョブマップは運用者が編集する外部入力であり、UC「runner 設定の差し替えのみで新世代実装を起動できる」の前提でもある。現行の仕様と実装は、ジョブマップが 1 ファイルであり、`job_map_version` が run 共通の 1 値であることを前提としている。

blue と green は別ライフサイクルでメンテナンスされる。1 ファイルを両 slot で共有すると、片方の slot の変更が他方の slot のリリースと競合し、版の記録も「どちらの slot の変更か」を表せない。形式が未契約のため、運用手順書・サンプル・検証(必須フィールド欠落時の終了コードとメッセージ)を仕様から導けず、background 起動 UC やリラン UC が別形式を仮定する余地もある。

### 変更してほしいこと

採用案: ジョブマップを slot ごとの独立ファイルとして cross-cutting の契約に定義する。1 ファイルで blue / green を併記する形式(実装の現行形式)は採用しない。

- 環境変数: `RELAYGATE_JOB_MAP_PATH` を廃止し、slot ごとのファイルパス(`RELAYGATE_JOB_MAP_PATH_BLUE` / `RELAYGATE_JOB_MAP_PATH_GREEN` 相当)を `cli-command-contract.yaml` と tier-facade.md の環境変数表に定義する
- ファイル構造: 各ファイルは自分の `job_map_version` と、job_id ごとの `host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref / hang_detect_limit_minutes` を持つ。ファイル形式(JSON を想定)、必須 / 任意の区別、未知フィールドの扱い(無視 / エラー)、必須欠落時の終了コード(バリデーション 2 または業務エラー 1)と stderr 文言も定める
- rdb-schema: `job_map_version` を `execution_specs`(run 共通)から `slot_execution_specs`(slot 別)へ移動し、「その slot の実行先解決に使用したジョブマップの版」とする。列の物理型は CR-6078c4ed-015 の対応表に従う
- hang_detect_limit_minutes: 各 slot のジョブマップが値を持つ。run 共通の `execution_specs.hang_detect_limit_minutes` には、background role に選ばれた slot のジョブマップの値を採用する(両 slot が background の場合の選び方も定める)。USDM 側の文言は CR-6078c4ed-016 で合わせる
- E2E Scenario の Given を slot ごとのジョブマップ(それぞれの版)に改める

### 完了条件

運用者が契約だけから slot ごとのジョブマップを作成でき、片方の slot のジョブマップだけを差し替えて新世代を起動できる。facade・worker・リランの各 UC が同じ形式を読み、`slot_execution_specs.job_map_version` に各 slot の版が保存され、`execution_specs.hang_detect_limit_minutes` の出所が background slot のジョブマップであることと、必須フィールド欠落時の挙動が E2E Scenario として書ける。
