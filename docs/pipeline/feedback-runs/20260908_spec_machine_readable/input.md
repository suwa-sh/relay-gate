---
schema_version: distillery.feedback-request/v1
feedback_id: 20260908_spec_machine_readable
created_at: 2026-09-08T15:00:00+09:00
source: distillery-spec
uc_id: c770d8f0
---

## CR-c770d8f0-020: spec-event.yaml の全 UC に USDM 対応(use_cases[].usdm)を機械可読で持たせる

- severity: spec-gap
- related_ids: [SPEC-EVENT-USDM]
- related_files: [docs/specs/latest/spec-event.yaml, docs/specs/latest/_cross-cutting/usdm-acceptance-matrix.md]

### 観測した事実

distillery 1.15.1 の dist-spec は `schema-spec-event.json` の `use_cases[]` に任意フィールド `usdm: [{req_id, spec_id, scenarios[]}]` を持ち、`validateSpecEvent.js` が spec_id の USDM 実在と req_id の親子関係を検証する。spec.md に「関連 USDM」節があるのに YAML に usdm が無い UC は warning になる。現在の `docs/specs/latest/spec-event.yaml` は 32 UC すべてが warning(`spec.md に「関連 USDM」節があるが spec-event.yaml の use_cases[].usdm がありません`)を出す。各 UC の spec.md「関連 USDM」表(REQ ID / SPEC ID / 対応 BDD Scenario の 3 列、計 133 行)は揃っており、SPEC ID は全件 `docs/usdm/latest/requirements.yaml` に実在し req_id の配下にある(事前検証済み)。

### 現在の仕様と問題

UC → USDM SPEC ID / 受け入れ条件の対応が各 spec.md の Markdown 表にしか無く、後工程(distillery-impl の ATDD 生成、`usdm-acceptance-matrix.md` の再生成)が Markdown 表を再パースしている。`_cross-cutting/rdra-feedback.md` の SR-001 がこの不足を記録しており、スキーマ側の対応(1.15.1)が済んだため spec 側の投入が残っている。表の「対応 BDD Scenario」列は複数シナリオを「 / 」で区切っているが、Scenario 名の括弧内にも「 / 」を含む行があり、機械分割だけでは Scenario 名と一致しない(19 箇所を事前検出)。

### 変更してほしいこと

- `spec-event.yaml` の `use_cases[]` 32 件すべてに `usdm[]` を追加する。内容は各 UC の spec.md「関連 USDM」表と同内容(req_id / spec_id / scenarios)にする。
- `scenarios[]` の各要素は、その spec.md の BDD `Scenario:` 名と完全一致させる(接尾の「(SPEC-xxx-yy)」を含む実際の行の名前)。表の「対応 BDD Scenario」列で Scenario 名以外の注記(「受け入れ条件 8 件:」「AC5」「…の実行side は UC〈…〉で覆う」等)が混ざっている行は、YAML には Scenario 名だけを載せ、注記は表側に残すか表を整えて YAML と表の対応が一意に読めるようにする。Scenario を持たない対応(モデル整合のみ)は `scenarios: []` にする。
- `usdm-acceptance-matrix.md` は spec-event.yaml の usdm[] から再集計し、既存の集計値(受け入れ条件 122、振る舞い SPEC 対応率 49/49)と一致することを確認する。差があれば YAML 側ではなく表の転記誤りとして扱い、spec.md の表を直す。
- `rdra-feedback.md` の SR-001 を「1.15.1 で対応済み。本イベントで投入」として解消済みに移し、「スキーマ更新までの暫定」の注記から USDM 対応の部分を外す。

### 完了条件

- `validateSpecEvent.js docs/specs/latest` の usdm 関連 warning が 0 件で、エラーも 0 件である。
- spec-event.yaml の usdm[] の (uc, req_id, spec_id) 集合が、各 spec.md「関連 USDM」表の集合と一致する(133 行)。
- usdm[].scenarios[] の全要素が当該 spec.md の `Scenario:` 名に実在する。
- rdra-feedback.md の残存スキル要求に SR-001 が無い。

## CR-c770d8f0-021: rdb-schema.yaml の列挙列 14 列に enum[] を持たせる

- severity: spec-gap
- related_ids: [SPEC-RDB-ENUM]
- related_files: [docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/rdra/latest/状態.tsv, docs/rdra/latest/バリエーション.tsv]

### 観測した事実

distillery 1.15.1 の `schema-rdb-schema.json` は `columns[]` に任意の `enum[]` を持ち、`validateRdbSchema.js` は description に列挙値があるのに enum が無い列を warning にする。現在の `rdb-schema.yaml` は 14 列で warning が出る: parallel_runs.status / slot_executions.slot / slot_executions.mode / slot_executions.status / rapid_runs.blue_status / rapid_runs.green_status / rapid_runs.completion_status / rapid_crosscheck_requests.status / comparison_results.comparison_type / comparison_results.status / final_crosscheck_requests.status / monitor_records.role / monitor_records.target_type / monitor_records.monitor_status。`datastore-rules.md`「列挙列ルール」は、状態列は RDRA 状態.tsv の状態名、モード・区分列はバリエーション.tsv の値と一致させ、値の列挙は enum を正本、description は意味の説明に使うと定める。

### 現在の仕様と問題

列挙値が description の日本語文中にしか無く、bash 定数・SQL CHECK 制約・状態コード表の codegen が description を正規表現で拾うか `cli-command-contract.yaml` の `shared_rules.state_codes` と手で突き合わせるしかない(`rdra-feedback.md` SR-002)。

### 変更してほしいこと

- 上記 14 列に `enum[]` を追加する。値は実装で使うコード値そのもの(英字コード)とし、次を正本にする。
  - 状態列: RDRA 状態.tsv の状態名。parallel_runs.status = STARTED / RUNNING / COMPLETED / ABORTED、slot_executions.status = RUNNING / SUCCEEDED / FAILED / ABORTED、rapid_crosscheck_requests.status と final_crosscheck_requests.status = REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED、rapid_runs.completion_status = PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED(状態「速報実行の完了状況」5 値の英字コード。既存の `shared_rules.state_codes.rapid_run_completion` と同じ)、monitor_records.monitor_status = NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED(状態「監視状態」6 値の英字コード)。
  - 区分列: バリエーション.tsv の値。slot_executions.slot = blue / green、slot_executions.mode = foreground / background(off の slot はレコードを作らないため enum に含めない)、comparison_results.comparison_type = job / full(利用者決定 2026-09-08: D2 = A。バリエーション「比較種別」2 値。crosscheck-job-map.csv の enum と同じ。速報側の本テーブルに実際に現れるのは job のみである旨は description に残す)、comparison_results.status = OK / NG / FAILED、monitor_records.role = blue / green / rapid-crosscheck(バリエーション「リラン対象 role」と同じ 3 値。final-crosscheck は監視対象外)、monitor_records.target_type = background_slot / rapid_request。
  - 完了結果列: rapid_runs.blue_status / green_status = SUCCEEDED / FAILED(nullable のまま。未受信は NULL)。
- description の「値: …」の列挙は enum と重複するため、意味の説明(各値の意味・遷移・条件)だけを残す形に整理する。値集合を description から削ることで意味が失われる箇所は残してよいが、enum と食い違う値を残さない。
- `datastore-schema.md` に enum 列を反映する(列挙値の表記)。
- `rdra-feedback.md` の SR-002 を解消済みに移す(CLI 契約側の扱いは CR-c770d8f0-022)。

### 完了条件

- `validateRdbSchema.js` が enum 関連の warning 0 件・エラー 0 件で PASS する。
- 14 列すべてに enum があり、値が上記の RDRA 状態.tsv / バリエーション.tsv 由来の値と一致する。
- description に enum と矛盾する値の列挙が無い。

## CR-c770d8f0-022: cli-command-contract.yaml の shared_rules.state_codes を rdb-schema の enum を正本として導出する形に改める

- severity: improvement
- related_ids: [API-CLI-STATE-CODES]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`cli-command-contract.yaml` の `shared_rules.state_codes` は parallel_run_status / slot_execution_status / request_status / rapid_run_completion / monitor_status / comparison_result_status の値集合をリテラルで持ち、同じ値集合が rdb-schema.yaml の列(CR-c770d8f0-021 で enum 化)にもある。`rdra-feedback.md` SR-002 と「スキーマ更新までの暫定」注記は、暫定の正本を `shared_rules.state_codes` としつつ、enum 導入後は state_codes がそれを参照(または生成)する形にして二重管理を解消すると定めている。state_codes には DB 列に対応しない値集合(slot_mode の off、role の final-crosscheck、hang_judgement、alert_level、alert_kind)と遷移説明(*_transitions / *_labels)も含まれる。

### 現在の仕様と問題

同じ値集合が 2 箇所にリテラルで存在し、片方だけを変えたときに検出する仕組みが仕様側に無い。実装フェーズでは bash 定数・SQL CHECK 制約の codegen 元を 1 つに決める必要がある。

### 変更してほしいこと

- `shared_rules.state_codes` の DB 列に対応する値集合(parallel_run_status / slot_execution_status / request_status / rapid_run_completion / monitor_status / comparison_result_status)を、rdb-schema.yaml の該当列の enum を正本とする導出形に改める。具体形は次の案 A を採用する(利用者決定 2026-09-08: D1 = A。案 B は不採用):
  - 案 A: 各項目を `{derived_from: {table, column}, values: [...]}` の形にし、values は enum の複製として残す。`shared_rules.state_codes` の冒頭に「values は rdb-schema.yaml の enum の複製。不一致は rdb-schema を正とし、実装フェーズのドリフトテストで一致を検証する」と明記する。
  - 案 B: 値集合を持たず `{derived_from: {table, column}}` の参照だけにする。
- request_status は速報(rapid_crosscheck_requests.status)と確報(final_crosscheck_requests.status)の 2 列に対応するため、derived_from を配列で両列を指す(値集合は同一であること)。
- DB 列に対応しない値集合(slot_mode / role / hang_judgement / alert_level / alert_kind)は従来どおりリテラルで残し、`source` に RDRA バリエーション名(「slot 実行モード」「run role(成果物ディレクトリ区分)」「ハング検知判定結果」「通知レベル」等)を記す。
- 遷移説明(*_transitions / *_labels / *_derivation / hang_judgement_to_monitor_status)は変更しない。
- state_codes を参照している本文(commands[].notes / idempotency、ui-design.md、各 UC の tier-*.md、usdm-acceptance-matrix.md、uc-dependencies.md)は参照名を変えないため追従不要だが、「列挙値の正本は shared_rules.state_codes」と述べている箇所(rdra-feedback.md の暫定注記など)は「正本は rdb-schema.yaml の enum」に改める。
- `rdra-feedback.md` の「スキーマ更新までの暫定」注記を削除し、SR-001 / SR-002 の解消をもって残存スキル要求を 0 件にする。

### 完了条件

- `shared_rules.state_codes` の DB 対応 6 項目が rdb-schema.yaml の列 enum への derived_from を持ち、案 A なら values が該当 enum と完全一致する。
- 「列挙値の正本は shared_rules.state_codes」という記述が docs/specs/latest に残っていない。
- rdra-feedback.md の残存スキル要求(SR-*)が 0 件である。
- `validateAllYaml.js` / `validateSpecProse.js` など既存の spec バリデータが PASS する。
