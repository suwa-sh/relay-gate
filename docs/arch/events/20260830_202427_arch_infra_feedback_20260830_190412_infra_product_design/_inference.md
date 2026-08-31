# arch フィードバック推論根拠

event_id: `20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design`
入力: `docs/infra/latest/`(event: `20260830_190412_infra_product_design`)

## 抽出手順(references/infra/infra-feedback.md 準拠)

1. **技術制約の抽出**: `product-impl-onprem.yaml` の各 components.configuration を確認したが、
   DB接続プール上限・MQサイズ上限等の「ベンダー共通の技術制約」に該当する新規項目は無かった
   (単一インスタンスPostgreSQLでMQ/FaaSを持たない構成のため)。追加無し
2. **オブザーバビリティ方針の抽出**: `product-observability.yaml` の `sli` / `slo` / `alerting` から
   `CTP-010` を抽出。既存の `CTP-003`(ログ相関)・`CTP-007`(性能方針)はSLI/SLOという形式では
   表現していなかったため、重複ではなく新規項目として追加
3. **サービスマッピング fidelity の分析**: `product-mapping-onprem.yaml` の8 canonical elementのうち
   4件(compute/database/artifact_store/backup_monitoring)が `fidelity: partial` であった。
   共通する論点(自動化の欠如・手動運用)を集約し `CTR-006` として追加。
   `config_store` と `execution_log_store` は `fidelity: exact` のため、対応する
   `storage_mapping` エントリ(E-008, E-012)の confidence を1段階昇格(medium→high)。
   `mail_notification` と `job_scheduler` も `fidelity: exact` だが、対応する storage_mapping
   エントリが存在しないためconfidence昇格の対象外
4. **コスト最適化方針の抽出**: `product-cost-hints.yaml` の `recommendations`(rightsizing/
   reserved_commitment/autoscaling等)から `CTP-011` を抽出
5. **横断的関心事のチェック**: 冪等性(CTP-004で既存カバー済み)、トレーサビリティ(CTP-003で既存カバー済み)、
   エラーハンドリング(CTR-002で既存カバー済み)、認証/認可(CTP-002で既存カバー済み)を確認したが、
   いずれも既存の cross_tier_policies/rules で全ティア共通にカバー済みであり追加の昇格提案は無し
6. **ストレージマッピング confidence の昇格**: 上記3参照

## ベンダーニュートラル化の確認

CTP-010/011、CTR-006の記述に PostgreSQL / Postfix / systemd 等のベンダー固有名詞を含めず、
「単一インスタンスDB」「ジョブスケジューラ実行ホスト」等のベンダー中立表現に置き換えた。

## confidence: "user" の保護確認

`CTR-005`(実装言語と実行環境、confidence: user)を含む全 confidence: "user" 項目は本フィードバックで
一切変更していない。

## dialogue_policy: auto_adopt に基づく判断

管理DBのRPO 4h/RTO 12h具体値の技術制約化は、既存 CTP-006 との重複可能性があり「新しいクロスティア
ポリシーが既存のポリシーと重複する可能性がある場合」(references/arch-feedback-rules.md「判断が必要な
ケース」)に該当するため、auto_adopt方針の保守的分岐に従い今回は反映せず `docs/todo.md`(DIST-014)に
登録した。
