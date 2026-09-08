# infra イベント変更サマリ

- event_id: `20260907_021000_feedback_todo_followup`
- trigger_event: `arch:20260907_015000_feedback_todo_followup, nfr:20260907_013000_feedback_todo_followup`
- created_at: 2026-09-07T02:10:00Z
- 種別: 差分更新(infra-event-diff.yaml。前イベント `20260905_093000_feedback_todo_resolution`)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項は決定を採用。確認推奨項目は完了報告で返却)
- feedback request: 20260907_todo_followup(direct work unit: なし。causal work unit: CR-c770d8f0-013#1, CR-c770d8f0-014#1, CR-c770d8f0-015#1。packet: docs/pipeline/feedback-runs/20260907_todo_followup/stage-packets/infrastructure.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_todo_followup"
  input_sha256: "193823ac1e6f02400269d6bdca461150a1fc8951393f332ef28580e045261389"
  request_ids: ["CR-c770d8f0-013","CR-c770d8f0-014","CR-c770d8f0-015"]
  work_unit_ids: ["CR-c770d8f0-013#1","CR-c770d8f0-014#1","CR-c770d8f0-015#1"]
```

## MCL 再実行の判断

- translation(workload_type / availability_tier / latency_target_p99 / data_classification / traffic_pattern_type / consistency_model / cost_posture / target_clouds)は無変更
- 影響は config_store の配置ファイル追加、管理 DB の接続解決と中止時 UPDATE の注記、実行ログの時刻軸とホストの TZ / 時刻同期、観測仕様の warning 扱いに限られる
- したがって mcl-product-design の全量再実行はスキップし、MCL 出力を対象箇所だけ更新した(前回 20260905_093000 と同じ判断。ハイブリッド方式: MCL 出力は全量を本イベントに保持し latest へ全量上書き)

## product-input 変更フィールド

- source_refs: `arch-design:20260905_091000_feedback_todo_resolution` / `nfr-grade:20260905_085000_feedback_todo_resolution` → `arch-design:20260907_015000_feedback_todo_followup` / `nfr-grade:20260907_013000_feedback_todo_followup`
- elements.config_store.description / entity_refs: 速報クロスチェック設定(env 形式 rapid-crosscheck.env。RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC。速報有効時に facade・slot runner・速報クロスチェック runner・worker が起動のたびに読む。off では不要)を追加し、entity_refs に E-027 を追加(CR-c770d8f0-013)
- elements.execution_log_store.description: 日時をホストのローカルタイムゾーン(ISO 8601 秒精度、指示子なし)で run_id の時刻部と同じ時刻軸にする旨を追記(CR-c770d8f0-015)
- observability_needs.notes: 中止済み run で速報クロスチェック runner が依頼を作成しなかった事実は実行ログの warning にのみ残りメール通知対象ではない旨を追記(CR-c770d8f0-014)

## MCL 出力ファイル(更新)

- `docs/mcl/product/output/product-workload-model.yaml`(更新): config_store(速報クロスチェック設定、REQ-CFG-001 の読み手、RAPID_DB_CONN_REF の参照名制約)、execution_log_store(時刻軸、REQ-LOG-003 全ホストの TZ 設定と時刻同期の一致、指示子なしの制約)
- `docs/mcl/product/output/product-mapping-onprem.yaml`(更新): management_db notes(RAPID_DB_CONN_REF / HANG_DB_CONN_REF による接続解決)、config_store notes(rapid-crosscheck.env、常駐 worker は再起動で反映)、execution_log_store notes(ローカルタイムゾーン、OS の TZ 設定と組織内 NTP の統一、systemd unit は TZ を上書きしない)
- `docs/mcl/product/output/product-impl-onprem.yaml`(更新): impl.compute.execution_hosts に timezone 設定と timedatectl の検証規則、impl.database.management_db に claim_pattern の lease / poll の出所・connection_resolution・abort_updates(REQUESTED 依頼の条件付き UPDATE。app_rw の UPDATE 権限で足りる)、impl.storage.config_store の contents / secret_handling / 平文検査に rapid-crosscheck.env と検証規則 1 件(3 キー存在・正の整数)、impl.storage.execution_log_store に timestamp
- `docs/mcl/product/output/product-observability.yaml`(更新): logging.timestamp(ローカルタイムゾーン)、logging.diagnostic_only_events(中止済み run の依頼未作成 warning はメール通知しない)、alert-error-rate の condition に対象外事象
- `docs/mcl/product/output/product-cost-hints.yaml`(変更なし)
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml`(更新): REQ-CFG-001 / REQ-CFG-002 の notes に rapid-crosscheck.env、REQ-LOG-003(conformant)を追加。summary を 24 要件(conformant 19 / partial 5 / non_conformant 0)に更新
- `docs/cloud-context/generated-md/product/relay-gate-target-architecture.md`(更新): 設定ファイル配置ノードに rapid-crosscheck.env、実行ログ領域ノードに時刻軸、ops CLI → 管理 DB の辺に未着手依頼の ABORTED 化。適合性サマリを 24 要件に更新
- `docs/cloud-context/decisions/product/*.yaml`(変更なし。決定記録は履歴として据え置き)
- `infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml`(更新): rapid-crosscheck.env の配置(0640。`rapid_crosscheck_mode` が off 以外のときのみ)とキー構成検査タスクを追加
- `infra/product/onprem/ansible/roles/relay-gate-runtime/tasks/main.yml`(更新): ホストのローカルタイムゾーン統一(`relay_gate_timezone`)と時刻同期確認タスクを追加
- `infra/product/onprem/ansible/inventory.ini.example`(更新): `rapid_crosscheck_mode`(実行ホスト)と `relay_gate_timezone`(全ホスト)の変数例を追加
- その他の IaC スケルトン(postgresql / mail / backup ロール、terraform)は変更なし

## infra-event.yaml 変更フィールド

- event_id / created_at / source / trigger_event / previous_event_ref / feedback_request / arch_event_ref / nfr_event_ref を本イベントへ更新
- mcl_execution.outputs の description に 20260907 差分の要約を追記
- arch_feedback: 据え置き(新規フィードバックなし)

## arch フィードバック

- なし。本イベントの差分はすべて arch 20260907_015000_feedback_todo_followup の変更(E-027 / SP-025 / SP-022 / LP-023 / CLP-002 / CTP-003)を下流へ追従したもの。ホスト間の TZ 統一は CLP-002 の「プロセスの TZ 環境変数に従う」から導かれる配備制約であり、arch の記述を変える知見ではない。arch のイベントは作成していない

## 書き戻しチェック

- 不要。arch 差分はティア構成・認証認可方式・DR 方針・外部連携・storage_type を変えておらず(E-027 の storage_type は file で既存の config_store に収まる)、product-input の translation フィールドに影響しない

## 照合結果(causal work unit)

| work unit | status | 反映先 / 理由 |
|---|---|---|
| CR-c770d8f0-013#1 | changed | 速報クロスチェック設定(rapid-crosscheck.env)を config_store(workload-model / mapping / impl / conformance / product-input / 構成図)、管理 DB の接続解決(mapping / impl)、ansible config ロール(配置 0640 と検査)、inventory 例へ反映 |
| CR-c770d8f0-014#1 | changed | 中止済み run の依頼未作成 warning をメール通知対象外として observability(logging / alert-error-rate)と product-input notes に反映。abort-blue / abort-green による未着手依頼の ABORTED 化を impl.database.management_db(条件付き UPDATE。既存の app_rw 権限で足りる)と構成図の辺へ反映 |
| CR-c770d8f0-015#1 | changed | 実行ログ日時のローカルタイムゾーン(指示子なし、run_id と同じ時刻軸)を execution_log_store(workload-model / mapping / impl / observability / product-input / 構成図)へ反映し、全ホストの TZ 設定と時刻同期の一致を REQ-LOG-003・execution_hosts の timezone 設定・検証規則・ansible runtime ロールへ追加 |

## 仮採用(confidence: low)

- なし(新規 low は作らない。既存の REQ-OPS-002(組織既存監視の有無。todo DIST-013)は本 CR の対象外で据え置き)

## 確認推奨項目

- ホスト間のタイムゾーン統一方式: 本イベントは「OS の TZ 設定を全ホストで同じ値にし、systemd unit / cron で TZ を上書きしない」を採用した(REQ-LOG-003。TZ の具体値は適用側の `relay_gate_timezone`)。代替は「systemd unit / ジョブスケジューラの環境変数で TZ を明示する」「ジョブスケジューラ実行ホストの TZ に他ホストを合わせる」。arch CLP-002 は「プロセスの TZ 環境変数に従う」としか定めていないため、適用側で統一方式を確定する
