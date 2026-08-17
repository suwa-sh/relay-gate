# インフラ設計変換 推論根拠

## 入力サマリ

| 項目 | 値 |
|------|-----|
| arch event_id | 20260817_150512_initial_arch |
| NFR event_id | 20260817_144844_initial_nfr |
| システム名（成果物では中立表現） | ジョブ実行中継基盤 |
| 対象クラウド | onprem（エアギャップ環境のオンプレミスLinuxサーバ限定。クラウドベンダー比較は対象外） |

## 前提条件の補完

- `docs/mcl/foundation/output/foundation-context.yaml` がプロジェクト内に存在しなかったため、オンプレミス単一サイト向けの最小 foundation-context.yaml を新規生成した（`organization_structure.environments: [prod, stg, dev]`, `network_guardrails.topology: single_site_onprem`, `approved_deviations` にクラウドマネージドサービス対象外の旨を明記）。
- `docs/mcl/shared-platform/output/shared-platform-context.yaml` も未存在のため、スキル既定の最小構成（`available_shared_services: []` 等）で生成した。

## 変換結果

| ワークロード特性 | 推論値 | 根拠 |
|-----------------|--------|------|
| workload_type | api | tier-frontend 無し、tier-facade（CLIエントリポイント=API Gateway相当）+ tier-worker（バッチ）構成。境界ケース表「API Gatewayのみ+worker → api」に合致 |
| availability_target.sla | 99.9% | A.1.1.1(grade5:24h無停止) + A.2.1.1(grade3:N+1手動切替)。表の完全一致行はないため、N+1冗長を維持しつつ手動切替である点を考慮し99.9%と判定 |
| availability_target.failover | warm_standby | A.1.2.1(grade3:60分未満) |
| latency_sensitivity.category | interactive | workload_type=api |
| latency_sensitivity.target_p99 | 1s | B.2.1.1(grade2:10秒以内)。nfr-grade.yaml内の実際のレスポンスタイム項目はB.2.1.1（"同時アクセス数"ではなく"レスポンスタイム"名称で登録） |
| traffic_pattern.type | scheduled | tier-worker技術候補にCronJob/cron/systemdタイマーが明記、SP-008(24時間定期監視)・SP-004(日次確報バッチ) |
| traffic_pattern.baseline_rps | 1 | B.2.1.2(grade1:〜10TPS) |
| traffic_pattern.spike_multiplier | 3 | B.1.2.1(grade2:通常時の2倍) |
| data_sensitivity.classification | internal | E.5.1.1はMFAだが外部IdP連携なし（CTP-001でOS/SSHレベル認証に統一）、PII属性検出なし |
| data_sensitivity.pii | false | entities属性に氏名/メール/電話/住所等のPII属性パターンが検出されなかった |
| data_sensitivity.encryption | in_transit_only | E.6.1.1(grade1:機密データのみ暗号化) |
| data_sensitivity.compliance | [] | カード情報属性なし、決済関連エンティティなし |
| consistency_needs.type | strong | lease/claim排他制御（SP-003）・冪等性方針（CTP-006）により重複実行防止が必須。model_type分布はevent/event_snapshotが拮抗のため業務要件（排他制御の必須性）を優先 |
| recovery_target.rpo/rto | 72h/72h | A.4.1.1(grade1)/A.4.1.2(grade1)。カテゴリA優先ルールに従う |
| recovery_target.backup | daily | 変換表の機械的適用ではC.1.2.1(grade2)→weeklyとなるが、arch-design.yaml SP-009に「フル+差分バックアップ（日次）」と明記されているため、より具体的なアーキテクチャ設計記述を優先しdailyとした（要確認事項として下記に記録） |
| observability_needs.* | 標準セット | C.1系がgrade3以上、C.6.1.1がgrade3のため変換表のフルセットを採用 |
| cost_posture.strategy | cost_optimized | NFR A重要指標平均約2.27・B重要指標平均約1.75で変換表の閾値に厳密には合致しないボーダーケース。オンプレ物理資産（スケールアップ前提・自動スケールアウト無し）というプロジェクト背景を踏まえコスト重視と判定（要確認事項として下記に記録） |

## NFR グレードマッピング

| NFR ID | grade | 推論先 | 変換値 |
|--------|-------|--------|--------|
| A.1.1.1 | 5 | availability_target.sla | 99.9%算出の一因 |
| A.2.1.1 | 3 | availability_target.sla | 99.9%算出の一因 |
| A.1.2.1 | 3 | availability_target.failover | warm_standby |
| A.4.1.1 | 1 | recovery_target.rpo | 72h |
| A.4.1.2 | 1 | recovery_target.rto | 72h |
| B.2.1.1 | 2 | latency_sensitivity.target_p99 | 1s |
| B.2.1.2 | 1 | traffic_pattern.baseline_rps | 1 |
| B.1.2.1 | 2 | traffic_pattern.spike_multiplier | 3 |
| E.5.1.1 | 3 | data_sensitivity.classification | internal（外部IdP無しのため） |
| E.6.1.1 | 1 | data_sensitivity.encryption | in_transit_only |
| C.1.2.1 | 2 | recovery_target.backup | daily（arch SP-009優先。表機械適用ならweekly） |
| C.6.1.1 | 3 | observability_needs.logs | フルセット |

## 要確認事項（dialogue_policy: auto_adopt により⭐推奨を仮採用）

1. **recovery_target.backup**: NFR変換表の機械適用では"weekly"だが、arch-design.yaml SP-009の明記（日次バックアップ）を優先し"daily"を採用。confidence: low → docs/todo.md に登録。
2. **cost_posture.strategy**: 変換表の閾値境界ケース。オンプレ資産前提から"cost_optimized"を仮採用。confidence: low → docs/todo.md に登録。
