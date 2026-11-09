# 変更サマリ

- event_id: 20261101_123000_feedback_mail_removal_housekeeping
- trigger_event: usdm:20261101_121000_feedback_mail_removal_housekeeping, rdra:20261101_121000_feedback_mail_removal_housekeeping, nfr:20261101_122000_feedback_mail_removal_housekeeping
- created_at: 2026-11-01T12:30:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクション: technology_context / domain_architecture / system_architecture / app_architecture / data_architecture)
- dialogue_policy: interactive(確認推奨項目は完了報告で返却。⭐推奨を仮採用して出力)
- feedback request: 20261101_mail_removal_housekeeping(direct work unit: なし。causal work unit: CR-e4ea8aaa-001#1(メール削除)/ CR-e4ea8aaa-002#1(ハウスキープ新設)。packet: docs/pipeline/feedback-runs/20261101_mail_removal_housekeeping/stage-packets/architecture.md)

マージ規則: technology_context は全体置換。subdomains / bounded_contexts / context_map / aggregate_hypotheses / tiers / cross_tier_policies / cross_tier_rules は `id`、tier_layers は `tier_id`、entities は `name`、storage_mapping は `entity_id` で照合して diff の要素で置き換え(新規は追加)。3 つの diagram_mermaid は全体置換。meta(event_id / created_at / source)を本イベントの値へ更新した。`confidence: "user"` の要素(CTR-005)は変更していない。

## 追加

- domain_architecture/subdomains/SD-005「実行履歴のハウスキープ」(generic)(CR-e4ea8aaa-002)
- domain_architecture/bounded_contexts/BC-006「ハウスキープコンテキスト」(owned_buc: ハウスキープフロー、owned_entity なし)(CR-e4ea8aaa-002)
- domain_architecture/context_map/CM-009〜CM-013(BC-006 → BC-001 / BC-002 / BC-003 / BC-004 / BC-005、Conformist)(CR-e4ea8aaa-002)
- system_architecture/tiers/tier-ops/policies/SP-027「ハウスキープの削除判定」、SP-028「ハウスキープの削除順序と回復」(CR-e4ea8aaa-002)
- system_architecture/cross_tier_rules/CTR-008「管理 DB の行と成果物の削除はハウスキープだけが行う」(CR-e4ea8aaa-002)
- app_architecture/tier_layers/tier-ops/L-ops-usecase/LP-025「ハウスキープは削除だけを行う」、L-ops-gateway/LP-026「削除待ちの置き場への rename と専用ロールでの 1 トランザクション削除」(CR-e4ea8aaa-002)
- data_architecture/entities/E-028「ハウスキープ設定」(resource_mutable。属性 retention_days / db_conn_ref は論理名でキー名は仕様で確定)と storage_mapping E-028(file)(CR-e4ea8aaa-002)
- decisions: arch-decision-022(メール廃止と通知経路)、arch-decision-023(ハウスキープの配置・BC・削除順序・専用 DB ロール)

## 変更

- technology_context: frameworks からメール送信コマンドを削除。constraints の提示方式を「CLI と定期ジョブだけ、異常の通知はハング検知ジョブの終了結果と標準エラーでジョブスケジューラの障害通知へ」に改め、C2/C3/C4 構成に housekeep、設定契約にハング検知定期ジョブ設定・ハウスキープ設定を追加。実行履歴の制約にハウスキープによる削除を追記。languages の bash にハウスキープを追記(CR-e4ea8aaa-001 / 002)
- domain_architecture/bounded_contexts/BC-004: owned_entity から E-022 を外し、ユビキタス言語に「ハング検知ジョブの終了結果による通知」「通知済み」を追加、「ハング疑い」の通知手段を警告終了と標準エラーへ。source_model から通知メールを外し条件「通知レベルの判定」「CLI による提示」を追加(CR-e4ea8aaa-001)
- domain_architecture/bounded_contexts/BC-005: owned_entity に E-028 を追加、設定所有区分の語にハウスキープ設定を追加し語「ハウスキープ設定」を追加(CR-e4ea8aaa-002)
- domain_architecture/aggregate_hypotheses/AG-004: member から E-022 を外し(空)、不変条件を終了結果(正常終了 / 警告終了 / 失敗)と標準エラー 1 件 1 行、通知済みの除外と保存失敗時の再通知へ改めた(CR-e4ea8aaa-001)
- domain_architecture/diagram_mermaid: BC-006 と Conformist 5 本を追加(CR-e4ea8aaa-002)
- system_architecture/tiers/tier-ops: description・technology_candidates からメール送信コマンドとメール設定を外し、housekeep・専用 DB ロールの RDB クライアント・置き場への rename・通知済みの印の書き込みを追加。SP-017 に段階(error / warning)を明記。SP-018 を終了結果と標準エラーによる通知・通知済みの判定(off は通知済みの印)・保存失敗時の再通知へ改めた。SP-020 に期限切れリランのエラーを追記。SR-005 を監視・復旧・ハウスキープの facade からの分離へ拡張(CR-e4ea8aaa-001 / 002)
- system_architecture/tiers/tier-datastore: description に通知済みの印・削除待ちの置き場・ハウスキープ設定・DB ロールの分離を追記、RDB の候補にロール分離を追記。SP-025 からメール 3 項目を外しハウスキープ設定を追加(CR-e4ea8aaa-001 / 002)
- system_architecture/cross_tier_policies/CTP-001: 「CLI と定期ジョブだけの提示(UI 画面・通知送信手段なし)」へ改名、起動口にハウスキープ定期ジョブを追加、根拠を条件「CLI による提示」と NFR F.1.1.3 / F.1.2.1 に差し替え(CR-e4ea8aaa-001 / 002)
- system_architecture/cross_tier_policies/CTP-002: 管理 DB の接続ロール分離(削除はハウスキープ専用ロールだけ)と接続参照名を追記(CR-e4ea8aaa-002)
- system_architecture/cross_tier_policies/CTP-003: 管理レコードと成果物が保持日数後に削除され長期追跡はジョブスケジューラで行うこと、リラン系譜の途中を消さないことを追記(CR-e4ea8aaa-002)
- system_architecture/cross_tier_policies/CTP-009: 異常メールの受け手を、ハング検知ジョブの警告終了・失敗(障害通知)の受け手へ改め、ハウスキープ失敗の扱いを追記(CR-e4ea8aaa-001 / 002)
- system_architecture/cross_tier_policies/CTP-010: 「運用者向け日次メールサマリー」をジョブスケジューラの既存監視への統合へ改めた(CR-e4ea8aaa-001)
- system_architecture/cross_tier_rules/CTR-003: 外部システム「メール通知」を外し、外部システム数を 5 種に改め、管理 DB のロール別接続を追記(CR-e4ea8aaa-001 / 002)
- system_architecture/cross_tier_rules/CTR-006: 「保持期間超過分削除の手動手順」をハウスキープ定期ジョブによる自動削除へ改め、実行ログの手動ローテーションとハウスキープ定期ジョブの登録手順を運用手順書の記載事項にした(CR-e4ea8aaa-002)
- system_architecture/cross_tier_rules/CTR-007: validate-config.sh の検証対象にハウスキープ設定(保持日数が正の整数)を追加(CR-e4ea8aaa-002)
- system_architecture/diagram_mermaid: MAIL ノードを削除し、tier-ops に housekeep、tier-ops → ジョブスケジューラの終了結果と、ジョブスケジューラ → 運用者の障害通知を追加(CR-e4ea8aaa-001 / 002)
- app_architecture/tier_layers/tier-facade: CLP-002 の gateway の外部呼び出しの列挙からメールを外した(CR-e4ea8aaa-001)
- app_architecture/tier_layers/tier-ops: presentation / usecase / domain / repository / gateway の責務に housekeep と終了結果による通知を反映し、メール送信アダプタを削除。LP-017 をメール送信から終了結果の受け渡しへ、LP-019 に終了結果と削除判定の判定表、LP-020 に通知済みの印と housekeep の成果物だけの判定、LP-021 の source_model からメール通知を削除、CLP-008 に通知した異常と削除結果の記録を追加、層図を更新(CR-e4ea8aaa-001 / 002)
- data_architecture/entities/E-021 監視記録: 通知メールへの関連を削除(CR-e4ea8aaa-001)
- data_architecture/entities/E-025 実行ログ: script_name にハウスキープを追加(CR-e4ea8aaa-002)
- data_architecture/entities/E-026 ハング検知定期ジョブ設定: 属性 alert_mail_to / alert_mail_cmd / alert_subject_prefix と通知メールへの関連を削除(db_conn_ref だけを残す)(CR-e4ea8aaa-001)
- data_architecture/storage_mapping/E-021: 通知済みの判定、off 時の通知済みの印、ハウスキープによる削除を追記(CR-e4ea8aaa-001 / 002)
- data_architecture/storage_mapping/E-026: env キーを HANG_DB_CONN_REF だけに改めた(CR-e4ea8aaa-001)
- data_architecture/diagram_mermaid: NOTIFICATION_MAIL の 2 行を削除し、HOUSEKEEP_CONFIG の 3 行と HANG_DETECTOR_CONFIG → MONITOR_RECORD、RAPID_CROSSCHECK_CONFIG → COMPARISON_DEFINITION を追加。あわせて過去のイベントで削除済みのエンティティ(クロスチェックジョブマップ・対象カタログ・比較結果)を指していた 4 行(CROSSCHECK_JOB_MAP / TARGET_CATALOG / COMPARISON_RESULT)を図から除いた(図と entities の整合のみ。モデルの変更なし)

## 削除

- data_architecture/entities/E-022「通知メール」(name: 通知メール)(CR-e4ea8aaa-001。RDRA の情報「通知メール」の削除に追従)
- data_architecture/storage_mapping/E-022(CR-e4ea8aaa-001)
- data_architecture/entities/E-026: 属性 alert_mail_to / alert_mail_cmd / alert_subject_prefix(CR-e4ea8aaa-001)
- source_model からの「外部システム: メール通知」「情報: 通知メール」「条件: CLI とメールによる提示」参照(BC-004 / AG-004 / SP-018 / CTP-001 / CTR-003 / LP-021)(CR-e4ea8aaa-001)

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-e4ea8aaa-001#1 | changed | technology_context / BC-004 / AG-004 / tier-ops(SP-017 / SP-018)/ tier-datastore(SP-025)/ CTP-001 / CTP-009 / CTP-010 / CTR-003 / 構成図 / tier-facade CLP-002 / tier-ops 層(LP-017 / LP-019 / LP-020 / LP-021)/ E-021 / E-022 削除 / E-026 / storage_mapping E-021・E-022 削除・E-026 / ER 図 / arch-decision-022 |
| CR-e4ea8aaa-002#1 | changed | technology_context / SD-005 / BC-005 / BC-006 / CM-009〜013 / tier-ops(SP-020 / SP-027 / SP-028 / SR-005)/ tier-datastore / CTP-001 / CTP-002 / CTP-003 / CTP-009 / CTR-006 / CTR-007 / CTR-008 / 構成図 / tier-ops 層(LP-025 / LP-026 / CLP-008)/ E-025 / E-028 / storage_mapping E-021・E-028 / ER 図 / arch-decision-023 |

## 影響なしと判断した箇所

- tier-facade / tier-rapid-crosscheck / tier-final-crosscheck のティア定義(ポリシー・ルール): メールにもハウスキープにも依存しない。SR-003 / SR-004 の作成・更新の所有は変えず、削除の例外は CTR-008 で定めた
- tier-rapid-crosscheck / tier-final-crosscheck のレイヤー: メール・削除を扱わない
- E-013 並行稼働実行・E-014 slot 実行・E-016 / E-017 速報・E-019 確報のエンティティ: 属性は不変(削除は行単位で、モデルの列は増えない)
- SD-001〜SD-004、BC-001〜BC-003、CM-001〜CM-008、AG-001〜AG-003 / AG-005: メール・ハウスキープに触れていない
- arch-decision-001〜021: 当時の文脈記録として変更しない
