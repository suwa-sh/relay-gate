# 変換推論根拠(差分更新 20260905_093000_feedback_todo_resolution)

前イベント `20260830_190412_infra_product_design` の推論根拠を引き継ぎ、本イベントで変更した箇所だけを記す。

## translation(変更なし)

| product-input フィールド | 根拠 | 判定 |
|---|---|---|
| workload_type / availability / latency / data_sensitivity / traffic / consistency / cost_posture / target_clouds | arch 差分 20260905_091000 はティア構成・認証認可・DR 方針・外部連携・storage_type を変えていない。NFR 差分 20260905_085000 は grade を据え置き(confidence と reason のみ更新) | 無変更。MCL 全量再実行は不要 |

## 要素説明の更新根拠

| 更新箇所 | 上流の根拠 | 起因 CR |
|---|---|---|
| artifact_store: Runner Result に aborted.txt、状態導出規則 | RDRA 情報「Runner Result」「slot 実行」、条件「slot 実行の状態導出規則」、arch CTR-001 / storage_mapping E-014 file / E-024(confidence high) | CR-004 |
| config_store: feature flag 9 キー env、設定版なし | RDRA 情報「feature flag 設定」(9 キー、設定版なし)、arch E-001 / SP-001 / SP-025 | CR-001 |
| config_store: ジョブマップ系 CSV、列名、セル規則、map_version 任意列 | RDRA 情報「ジョブマップ」「クロスチェックジョブマップ」「対象カタログ」、条件「ジョブマップ解決条件」、arch E-003 / E-007 / E-008 storage_mapping | CR-002 |
| config_store: hang-detector.env(ALERT_MAIL_TO / ALERT_MAIL_CMD / ALERT_SUBJECT_PREFIX / HANG_DB_CONN_REF) | RDRA 情報「ハング検知定期ジョブ設定」、arch E-026 / storage_mapping E-026 file(env 形式) | CR-010 |
| config_store: バックアップ正本は適用側の版管理 | NFR C.1.2.2(バックアップ対象に設定・適用構成文書を含む)。設定所有区分により正本は適用側の構成管理リポジトリにあるため、ホスト側の追加バックアップではなく版管理側で満たすと解釈 | CR-010 / CR-007 |
| mail_notification: 送信コマンド・宛先・件名プレフィックスの出所 | RDRA 情報「通知メール」(宛先・送信コマンド・件名プレフィックスはハング検知定期ジョブ設定から取得)、NFR C.3.2.1 / F.1.2.1 | CR-010 |
| observability: aborted.txt の終端扱い | RDRA 条件「ハング検知判定」(aborted.txt がある対象の終端)、NFR C.1.3.2 | CR-004 |
| conformance notes: NFR 7 項目の利用者確定 | NFR A.2.1.1 / A.3.1.1 / A.3.1.2 / C.6.1.1(confidence user。適用側で上書き可能な既定値)。C.2.1.2 / C.4.1.1 / C.5.1.1 は infra の要件(REQ-*)に直接対応する項目が無いため product-input の notes には含めず、grade 据え置きのため構成変更なし | CR-012 |
| ansible config ロール: 配置ファイル名 | 上記 config_store の内容。ファイル名は RDRA(hang-detector.env)と CR-001(feature-flag.env)、CR-002(`.csv`)に従い、slot ごとのジョブマップは中立名 `blue-job-map.csv` / `green-job-map.csv` とした | CR-001 / 002 / 010 |
| ansible config ロール: hang-detector.env を 0640 | foundation.identity.no_secret_values_in_config(参照名のみ)に加え、接続参照名の露出範囲を実行グループに限定する防御的設定。認証情報の値は含まないため 0644 でも要件は満たす | CR-010 |

## 影響なしと判定した CR の根拠

| CR | 判定 | 根拠 |
|---|---|---|
| CR-003(run_id 形式) | not_impacted | infra は run_id を主キー・ディレクトリ名・ログ相関キーとしてのみ扱い、形式を定めていない。ローカルタイムゾーンの時刻部はディレクトリの整列性に影響しない |
| CR-005(完了通知失敗) | not_impacted | 検知対象外とする判断は RDRA 条件・spec の責務。infra の観測仕様(SLI / アラート)は NFR observability_needs から導出しており無変更。product-input の notes に注記だけ残した |
| CR-006(管理 DB 内部化) | already_current | 初期構築時から product.database.management_db を内部 canonical element、product-decision-002 で「ジョブキュー兼管理 DB」として扱っており、外部システム表記が無い |
| CR-007(情報属性整理) | not_impacted | 調整記録の置き場と応答日時は infra の要素・実装仕様に現れない |
| CR-008(監視状態の統一) | not_impacted | 監視状態の値集合は observability 仕様に列挙していない |
| CR-009(並行稼働実行の遷移) | not_impacted | 管理 DB 内の状態機械であり構成に影響しない |
| CR-011(比較結果の登録条件) | not_impacted | worker のアプリケーション規則であり構成に影響しない |

## arch フィードバック / 書き戻しチェック

- arch へ戻す新規知見: なし(本イベントは arch 差分の下流追従のみ)
- 書き戻しチェック: 不要(translation フィールドに影響する arch 変更なし)
