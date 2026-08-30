# 変換推論根拠: 20260818_141149_infra_product_design

## 入力

- `docs/arch/latest/arch-design.yaml`（event: 20260818_135504_arch_slot_config_attempt_identity）
- `docs/nfr/latest/nfr-grade.yaml`（event: 20260817_144844_initial_nfr）
- feedback packet: `docs/pipeline/feedback-runs/20260818_113601_impl_feedback_6078c4ed/stage-packets/infrastructure.md`

## direct work unit の反映根拠

### CR-6078c4ed-004#1（audit-table-postgres-valid-ddl）

- 従来の`retention: 月次パーティションで6ヶ月保持`は、`event_id`単独主キー + `(run_id, slot, attempt_id, event_name)`一意制約と両立しない。PostgreSQLのpartitioned tableはPRIMARY KEY / UNIQUE制約にpartition keyの包含を要求するため、この組合せは実DDLとして成立しない
- CR本文で確定済みの採用案に従い、初期構成を非partitionの追記専用`audit_logs`とし、`occurred_at` / `run_id` / `parent_run_id`の索引と専用保守権限ロールによる6ヶ月保持運用を定義した。冪等一意性（event_id単独主キー + 複合一意制約）は弱めていない
- 実測負荷が必要になった時点でregistry分離を含むpartition設計へ移行する方針を`partitioning_policy`として明記した
- 確定済みの除外項目（認証情報・起動引数実値・stdout/stderr本文）、追記専用の権限境界、ハッシュチェーン改ざん検知は維持した

### CR-6078c4ed-006#1（runner-result-event-snapshot-persistence）

- インフラ側のデータストア設計判断は現在状態のみのsnapshot-onlyを暗黙前提としており、arch-design.yaml LR-002（repository.save = historyAdapter.insert + snapshotAdapter.upsert）と矛盾していた
- CR本文で確定済みの採用案に従い、append-onlyの`runner_result_events`（履歴INSERT）+ 現在状態の`runner_results`（snapshot UPSERT）を同一transactionで更新する併用方式へ更新した
- 判断の正本として`product-decision-event-snapshot-persistence.yaml`を新設し、`product-decision-storage-approach.yaml`から参照した。実装仕様には同一transaction更新のvalidation ruleを追加した

## causal reconciliation の根拠

### CR-6078c4ed-003#1（rerun-identity-new-run-id）

- 再実行identity（新run_id発行 + parent_run_id関連付け、既存履歴不変）はUSDM / RDRA / archで反映済み
- インフラ成果物ではproduct-input.yamlのrequirementsとimpl仕様の`runner_result_identity`に同方針を明記し、矛盾を解消した

### CR-6078c4ed-005#1（slot-config-and-attempt-identity）

- archがrun共通execution spec（E-001）とslot別実行設定（E-007）の分離、Runner実行結果identity（run_id, slot_type, role_type, attempt_id）、実行状態6値を定義済み
- インフラ成果物ではcomp-datastore-rdbのテーブル一覧・`execution_spec_split`・`runner_result_identity`・`runner_result_states`、workload modelのREQ-CN-003、product-inputのentities / requirementsへ追随させた
- observabilityの監査照合表現（run_id・slot・attempt_id）はarchの監査イベント定義（slot / attempt_idフィールド）と一致しているため変更不要と判断した

## MCL 全量再実行を行わなかった理由

差分の影響範囲はデータストア契約（監査テーブルDDL・永続化方式・identity表現）に限定され、translation（workload_type / availability / latency / consistency / cost）へ影響しないため、MCL出力への直接差分反映とした。
