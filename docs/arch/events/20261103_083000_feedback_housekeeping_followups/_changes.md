# 変更サマリ

- event_id: 20261103_083000_feedback_housekeeping_followups
- trigger_event: usdm:20261103_081000_feedback_housekeeping_followups, rdra:20261103_081000_feedback_housekeeping_followups, nfr:20261103_082000_feedback_housekeeping_followups
- created_at: 2026-11-03T08:30:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクション: domain_architecture(bounded_contexts / context_map)/ system_architecture / data_architecture)
- dialogue_policy: interactive(確認推奨項目は完了報告で返却)
- feedback request: 20261103_housekeeping_followups(direct work unit: CR-f3b8a1d0-003#1(実行ログの整理を logrotate に任せる)。causal work unit: CR-f3b8a1d0-001#1(管理 DB に接続しないハウスキープ)/ CR-f3b8a1d0-003#1。packet: docs/pipeline/feedback-runs/20261103_housekeeping_followups/stage-packets/architecture.md)

マージ規則: bounded_contexts / context_map / tiers / cross_tier_rules は `id`、entities は `name` で照合して diff の要素で置き換えた(diff の要素は latest の当該要素と同一の内容)。meta(event_id / created_at / source)を本イベントの値へ更新した。`confidence: "user"` の要素は変更していない。

## 追加

- decisions: arch-decision-024(実行ログの整理を設置環境の logrotate に任せる。arch-decision-023 の「実行ログの手動ローテーションは残す」を改める)(CR-f3b8a1d0-003)
- decisions: arch-decision-025(管理 DB に接続しない設定のハウスキープ)(CR-f3b8a1d0-001)

## 変更

- system_architecture/cross_tier_rules/CTR-006: 「ハウスキープの対象外である実行ログはファイル領域での手動ローテーション(3 ヶ月保管)とする」を「実行ログはハウスキープの対象外とし、relay-gate は実行ログを整理しない。設置環境の OS 標準のログ整理(logrotate)で 3 か月保管する」に改め、運用手順書の手動手順の列挙から「実行ログのローテーション」を外した。reason に 2026-11-03 の変更を追記し、source_model に NFR C.6.1.1 を追加(CR-f3b8a1d0-003)
- system_architecture/tiers/tier-ops/SP-027「ハウスキープの削除判定」: 管理 DB に接続しないとき(RAPID_CROSSCHECK_MODE=off で接続参照名が無い・空)の規則を追記(確報比較依頼と管理 DB の行を削除せず起動ごとに warn 1 行、execution-spec.json の速報クロスチェックのモードが off でない実行は単位ごと残して warn、off の期間の成果物だけの実行は従来どおり、warn は終了コードに影響しない、この規則が優先)。reason に追従の根拠を追記(CR-f3b8a1d0-001)
- system_architecture/tiers/tier-ops/SP-028「ハウスキープの削除順序と回復」: 管理 DB に接続しないときは管理 DB の行の削除の段を行わず、その warn を失敗として扱わないことを追記(CR-f3b8a1d0-001)
- domain_architecture/bounded_contexts/BC-005: 語「ハウスキープ設定」に、off では接続参照名を無し・空にでき、そのとき管理 DB に接続せず確報比較依頼と管理 DB の行を削除しないことを追記(CR-f3b8a1d0-001)
- domain_architecture/context_map/CM-013(BC-006 → BC-005): ハウスキープが feature flag の RAPID_CROSSCHECK_MODE も読み、off で接続参照名が無い・空なら管理 DB に接続しないことを追記(CR-f3b8a1d0-001)
- data_architecture/entities/E-028 ハウスキープ設定: 属性 db_conn_ref を nullable: true にし、off では無し・空にできることを説明に追記(CR-f3b8a1d0-001)

## 削除

- なし(arch-decision-023 は過去の判断の記録として書き換えず、deprecated にもしない。実行ログの 1 項目だけを arch-decision-024 で改めた)

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-f3b8a1d0-001#1 | changed | SP-027 / SP-028 / BC-005 / CM-013 / E-028、arch-decision-025 |
| CR-f3b8a1d0-003#1 | changed(direct owner: applied) | CTR-006、arch-decision-024 |

確認したが変更不要だった箇所(CR-f3b8a1d0-001): CTR-008(削除の所有と専用ロール。接続しないときは削除しないだけで所有は不変)、LP-025 / LP-026(削除の順序とアダプタ。行を削除しない場合を妨げない)、BC-006 / CM-009〜012、tier-datastore SP-025(設定の配置先の区分のみ)、storage_mapping E-028。CR-f3b8a1d0-003: 実行ログのその他の記述(CTP-003 の 3 ヶ月保管の根拠、storage_mapping E-025)は手動前提を含まないため不変。
