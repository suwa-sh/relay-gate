# 変更サマリ

- event_id: 20260905_091000_feedback_todo_resolution
- trigger_event: rdra:20260905_083000_feedback_todo_resolution, nfr:20260905_085000_feedback_todo_resolution
- created_at: 2026-09-05T09:10:00Z
- mode: 差分更新(arch-design-diff.yaml)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項は決定を採用。確認推奨項目は完了報告で返却)
- feedback request: 20260905_todo_resolution(direct work unit: なし。causal work unit: CR-c770d8f0-001#1 〜 CR-c770d8f0-012#1。packet: docs/pipeline/feedback-runs/20260905_todo_resolution/stage-packets/architecture.md)

```yaml
feedback_request:
  feedback_request_id: "20260905_todo_resolution"
  input_sha256: "285429579e9c9d28307d4c779317f01941b915a1203d0e5b5f53a6c014ed7108"
  request_ids: ["CR-c770d8f0-001","CR-c770d8f0-002","CR-c770d8f0-003","CR-c770d8f0-004","CR-c770d8f0-005","CR-c770d8f0-006","CR-c770d8f0-007","CR-c770d8f0-008","CR-c770d8f0-009","CR-c770d8f0-010","CR-c770d8f0-011","CR-c770d8f0-012"]
  work_unit_ids: ["CR-c770d8f0-001#1","CR-c770d8f0-002#1","CR-c770d8f0-003#1","CR-c770d8f0-004#1","CR-c770d8f0-005#1","CR-c770d8f0-006#1","CR-c770d8f0-007#1","CR-c770d8f0-008#1","CR-c770d8f0-009#1","CR-c770d8f0-010#1","CR-c770d8f0-011#1","CR-c770d8f0-012#1"]
```

マージ規則: `bounded_contexts` は `id`、`tiers` / `cross_tier_policies` / `cross_tier_rules` は `id`、`tier_layers` は `tier_id`、`entities` は `name`(= `id`)、`storage_mapping` は `entity_id` + `storage_type` をキーに、diff の要素で latest の同キー要素を置き換えた。`confidence: "user"` の項目(CTR-005)は変更していない。`data_architecture.diagram_mermaid` は全置換。

## 追加

- data_architecture/entities: E-026 ハング検知定期ジョブ設定(alert_mail_to / alert_mail_cmd / alert_subject_prefix / db_conn_ref。BC-005 所有)(CR-c770d8f0-010)
- data_architecture/storage_mapping: E-026 → file(env 形式。hang-detector が起動のたびに読む)(CR-c770d8f0-010)
- data_architecture/entities/E-001: blue_impl / green_impl / rapid_crosscheck_runner / rapid_crosscheck_worker 属性、E-010 への関係(CR-c770d8f0-001)
- data_architecture/entities/E-003: hang_detect_limit_minutes 属性(CSV 列として明示)(CR-c770d8f0-002)
- data_architecture/entities/E-005: hang_limit_adjustment_records 属性、E-004 への関係(CR-c770d8f0-007)
- data_architecture/entities/E-011: aborted_at 属性(aborted.txt)(CR-c770d8f0-004)
- data_architecture/entities/E-022: subject 属性、E-026 への関係(CR-c770d8f0-010)
- data_architecture/diagram_mermaid: HANG_DETECTOR_CONFIG / FEATURE_FLAG → EXECUTION_SPEC / APPLICATION_DOCUMENT → HANG_DETECT_LIMIT の関係(CR-c770d8f0-010 / 001 / 007)
- app_architecture/tier_layers/tier-facade: LP-022 完了通知の送信失敗は警告のみ(gateway 層)(CR-c770d8f0-005)

## 変更

- domain_architecture/bounded_contexts/BC-001: 用語 run(run_id 形式)、Runner Result(aborted.txt と状態導出)(CR-c770d8f0-003 / 004)
- domain_architecture/bounded_contexts/BC-004: 用語 明示中止(aborted.txt を正本、off 以外で管理 DB も更新)(CR-c770d8f0-004)
- domain_architecture/bounded_contexts/BC-005: 用語 feature flag(9 キー・3 値・設定版なし)、ジョブマップ(CSV 列名)、設定所有区分(ハング検知定期ジョブ設定)。owned_entity_ids に E-026 追加(CR-c770d8f0-001 / 002 / 010)
- system_architecture/tiers/tier-facade: description、SP-001(9 キー、未知キー警告なし)、SP-006(CSV 列名・fixed_params セル規則・host / user 省略可)、SP-007(実装版 = BLUE_IMPL / GREEN_IMPL、マップ版 = 任意列)、SP-008(run_id は常時発行、通知先 = RAPID_CROSSCHECK_RUNNER、完了通知失敗は自動検知しない)、SR-001(aborted.txt と状態導出規則、リラン由来 run の COMPLETED)(CR-c770d8f0-001 / 002 / 003 / 004 / 005 / 009)
- system_architecture/tiers/tier-rapid-crosscheck: SP-011(比較結果の登録条件、リラン由来 run の COMPLETED)、SR-003(parallel_run の作成者・更新者、管理 DB を内部データストア表記)(CR-c770d8f0-006 / 009 / 011)
- system_architecture/tiers/tier-ops: description / technology_candidates(aborted.txt、ハング検知定期ジョブ設定)、SP-016(aborted.txt 終端、通知済み対象の再判定と終端、完了通知失敗は対象外)、SP-018(monitor_status 6 値、設定の出所、通知後正常終了)、SP-019(調整記録は適用構成文書)、SP-020(ファイル正本での事前検証、off でもリラン可、COMPLETED 到達経路)、SP-022(aborted.txt 書き込み、off でも中止成立、STARTED / RUNNING → ABORTED)(CR-c770d8f0-004 / 005 / 007 / 008 / 009 / 010)
- system_architecture/tiers/tier-datastore: description(管理 DB は内部、ハング検知定期ジョブ設定)、SP-023(内部データストア表記)、SP-024(aborted.txt、off でも中止・リラン)、SP-025(9 キー / CSV / env の所有区分、版の出所)(CR-c770d8f0-001 / 002 / 004 / 006 / 007 / 010)
- system_architecture/cross_tier_policies: CTP-002(source_model を内部データストア表記へ)、CTP-003(run_id 形式: ローカルタイムゾーン yyyymmddThhmmss-{job_id}-{8 桁 hex}。off でも facade 単独で発行)、CTP-009(利用者確定を反映し confidence low → medium)(CR-c770d8f0-003 / 006 / 012)
- system_architecture/cross_tier_rules: CTR-001(aborted.txt と状態導出規則)、CTR-003(外部システム 6 種、管理 DB は内部データストア)(CR-c770d8f0-004 / 006)
- app_architecture/tier_layers/tier-facade: usecase 責務(run_id 常時発行、通知失敗は警告)、LP-004、domain 責務と LP-005(STARTED → ABORTED、状態導出規則、run_id 生成規則、CSV セル解析)、repository 責務(9 キー / CSV)、gateway 責務(ローカル実行、RAPID_CROSSCHECK_RUNNER)(CR-c770d8f0-001 / 002 / 003 / 004 / 005 / 009)
- app_architecture/tier_layers/tier-rapid-crosscheck: usecase 責務(登録条件、リラン由来 run の COMPLETED)(CR-c770d8f0-009 / 011)
- app_architecture/tier_layers/tier-ops: domain 責務と LP-019(状態導出、監視状態 6 値と終端遷移)、repository 責務と LP-020(管理 DB なしでの監視・中止・リラン)、gateway 責務と LP-021(aborted.txt の原子的書き込み、条件付き更新の対象状態)、CLP-008(調整記録の置き場)(CR-c770d8f0-004 / 006 / 007 / 008 / 009 / 010)
- data_architecture/entities/E-001 feature flag 設定: config_version(設定版)を削除し 9 キー構成へ。rapid_crosscheck_mode を foreground / background / off に変更。model_type を resource_mutable へ(CR-c770d8f0-001)
- data_architecture/entities/E-003 ジョブマップ: 列名を job_id / host / user / work_dir / script / fixed_params / hang_detect_limit_minutes に統一。host / user / credential_ref / map_version を nullable に(CR-c770d8f0-002)
- data_architecture/entities/E-004 ハング検知上限設定: 説明に調整記録の置き場を明記(CR-c770d8f0-007)
- data_architecture/entities/E-009 ジョブ起動要求: run_id はモードによらず発行(CR-c770d8f0-003)
- data_architecture/entities/E-010 実行設定: 属性名を user / script / fixed_params に統一、map_version を nullable、impl_version の出所を BLUE_IMPL / GREEN_IMPL に。E-001 への関係を追加(CR-c770d8f0-001 / 002)
- data_architecture/entities/E-011 Runner Result: exit_code を nullable、E-014 への関係説明に状態導出(CR-c770d8f0-004)
- data_architecture/entities/E-013 並行稼働実行: run_id 形式、status 遷移(STARTED / RUNNING → ABORTED、リラン由来 run の COMPLETED)(CR-c770d8f0-003 / 009)
- data_architecture/entities/E-014 slot 実行: status をファイル正本から導出(CR-c770d8f0-004)
- data_architecture/entities/E-021 監視記録: monitor_status の 6 値と通知後・中止後の終端(CR-c770d8f0-008)
- data_architecture/entities/E-022 通知メール: recipient の出所(CR-c770d8f0-010)
- data_architecture/storage_mapping: E-001(9 キー env)、E-003 / E-007 / E-008(CSV 形式と解析規則)、E-014 file(状態導出規則。confidence medium → high)、E-014 rdb(二重マッピング確定。confidence low → high)、E-021(接続参照名、6 値)、E-024(aborted.txt を正本。confidence medium → high)(CR-c770d8f0-001 / 002 / 004 / 008 / 010)

## 削除

- data_architecture/entities/E-001: 属性 config_version(設定版)(CR-c770d8f0-001)
- data_architecture/entities/E-003: 属性 exec_user / script_path / fixed_args(改名)、impl_version(実装版列の廃止)(CR-c770d8f0-001 / 002)
- data_architecture/entities/E-004: 属性 adjusted_at / adjustment_basis(適用構成文書へ移動)(CR-c770d8f0-007)
- data_architecture/entities/E-010: 属性 exec_user / script_path / fixed_args(改名)(CR-c770d8f0-002)
- data_architecture/entities/E-012: 属性 occurred_at(応答日時)(CR-c770d8f0-007)
- source_model からの「外部システム: 管理 DB(RDB)」参照(SR-003 / SP-023 / CTP-002 / CTR-003 / LP-021。システム概要の内部データストア表記へ置換)(CR-c770d8f0-006)

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-c770d8f0-001#1 | changed | E-001 / E-010 / SP-001 / SP-007 / SP-008 / SP-025 / BC-005 / storage_mapping E-001 |
| CR-c770d8f0-002#1 | changed | E-003 / E-010 / SP-006 / SP-025 / BC-005 / storage_mapping E-003 / E-007 / E-008 |
| CR-c770d8f0-003#1 | changed | CTP-003 / E-013 / E-009 / BC-001 / LP-005 |
| CR-c770d8f0-004#1 | changed | E-011 / E-014 / SR-001 / CTR-001 / SP-016 / SP-020 / SP-022 / SP-024 / LP-005 / LP-019 / LP-020 / LP-021 / BC-001 / BC-004 / storage_mapping E-014 / E-024 |
| CR-c770d8f0-005#1 | changed | SP-008 / SP-016 / LP-004 / LP-022 |
| CR-c770d8f0-006#1 | changed | SR-003 / SP-023 / CTP-002 / CTR-003 / LP-021 / tier-datastore |
| CR-c770d8f0-007#1 | changed | E-004 / E-005 / E-012 / SP-019 / CLP-008 |
| CR-c770d8f0-008#1 | changed | E-021 / SP-016 / SP-018 / LP-019 / storage_mapping E-021 |
| CR-c770d8f0-009#1 | changed | E-013 / SR-001 / SR-003 / SP-011 / SP-020 / SP-022 / LP-005 / LP-021 |
| CR-c770d8f0-010#1 | changed | E-026 / E-022 / SP-018 / SP-025 / BC-005 / tier-ops / LP-020 / LP-021 / storage_mapping E-026 |
| CR-c770d8f0-011#1 | changed | SP-011 |
| CR-c770d8f0-012#1 | changed | CTP-009(confidence low → medium) |

## 仮採用(confidence: low)

- なし(今回の差分で新規 low は作らない。既存の low は集約境界仮説 AG-* と storage_mapping E-009 / E-022 で、本 CR の対象外)

## 確認推奨項目

- 実行ログの日時タイムゾーン(CLP-002 は UTC)と run_id の時刻部(ローカルタイムゾーン)の不一致。本イベントでは CLP-002 を変更せず、完了報告で確認項目として返却する
