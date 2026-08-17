# フィードバック推論根拠

インフラ設計イベント `20260817_151023_infra_product_design`（MCL product-design onprem 実行結果）を
`references/infra/infra-feedback.md` の抽出手順に従って分析した。

## 1. 技術制約の抽出

`product-impl-onprem.yaml` の components[].configuration を確認したが、DB接続プール上限・MQメッセージ
サイズ上限等の明示的な数値制約は記載されていなかった（ベースライントラフィックが低頻度・少人数運用の
ため、MCL側でも数値上限を設けていない）。一方、`product-mapping-onprem.yaml` の
`product.observability_needs`（fidelity: partial）で「クラウドのマネージド監視・アラーティングサービスは
利用不可。閉域内での監視基盤整備が別途必要」と明記されており、これは既存の
`technology_context.constraints`（エアギャップ環境の制約）を具体化する新規制約として妥当と判断し追加した。

## 2. オブザーバビリティ方針の抽出

`product-observability.yaml` の `sli[]` / `slo[]` に、可用性99.9%（月次）・p99レイテンシ1秒以内（日次）・
エラーバジェット消化時の変更凍結方針という具体的なSLO運用ルールが定義されていた。既存の
`CTP-009`（性能・拡張性の設計方針）はCLI応答目標値（10秒以内・10TPS）を定めているが、SLI/SLOベースの
エラーバジェット運用方針までは含まれていないため、CTP-013として新規追加した（CTP-009の削除・書き換えは
行わない）。

## 3. サービスマッピング fidelity の分析

`product-mapping-onprem.yaml` で fidelity: partial と判定された項目は
`product.availability_target`（手動フェイルオーバー）、`product.recovery_target`（自前バックアップ運用）、
`product.persistence`（自前HA運用）、`product.observability_needs`（閉域内監視基盤の別途整備）の4件。
このうち observability_needs は上記1で制約として反映済み。availability_target / recovery_target /
persistence は「自動化されたマネージド機能が存在しないため運用手順の整備が必要」という共通の含意を持つため、
横断ルール CTR-006 として集約して追加した（個別ティアの既存ポリシー SP-009/SP-010/SP-011/SP-012 は
書き換えず、運用手順整備という横断的な補完事項のみを新設）。

`product.workload_type` / `latency_sensitivity` / `data_sensitivity` / `traffic_pattern` /
`consistency_needs` / `scheduled_execution` / `cost_posture` はいずれも fidelity: exact であり、
特筆すべき乖離はない。

## 4. ストレージマッピング confidence の昇格

`data_architecture.storage_mapping` は全エンティティ（E-001〜E-006）が既に `confidence: high` であり、
昇格対象は存在しなかった。

## 5. コスト最適化方針の抽出

`product-cost-hints.yaml` はクラウド従量課金系のヒントを明示的に対象外とし、オンプレミス資産運用の
観点（rightsizing / storage_tiering / capacity_planning）のみを記載していた。このうち
storage_tiering（実行ログの一定期間経過後のコールドストレージ相当への移動）は tier-datastore に
固有のポリシーとして具体性が高いため、SP-013として tier-datastore.policies に追加した。
rightsizing / capacity_planning は運用開始後の実測に基づく判断であり、現時点でアーキ設計に反映すべき
具体的なポリシーとして表現できる内容がないため見送った。

## 6. 横断的関心事のチェック

- 冪等性: 既存の CTP-006（冪等性方針）が run_id/parent_run_id とlease/claim機構による重複実行防止を
  カバー済みであり、MCL の実装仕様（lease失効時のREQUESTED差し戻し）と整合していたため追加不要と判断
- トレーサビリティ: 既存の CTP-004（実行系譜トレーサビリティ）がrun_id/parent_run_idの相関ID方針を
  カバー済みであり、MCL observability の correlation_id 定義と整合していたため追加不要と判断
- エラーハンドリング: MCL impl にサーキットブレーカー・リトライの明示的設計は含まれていなかった
  （facade/workerとも単純な起動前検証・lease機構が中心）ため、新規追加は見送った
- 認証/認可の一貫性: MCL mapping の SSH鍵認証・参照名管理は既存の CTP-001（認証方式）・
  SR-003（認証情報の非保存）と整合しており、新規追加は不要と判断

## 適用したフィードバック方針

- ベンダー固有サービス名（PostgreSQL, RAID5, logrotate 等の実装詳細）はアーキ設計へは持ち込まず、
  ベンダーニュートラルな表現（RDB、ストレージ冗長化、ログローテーション等）に変換して追加した
- `confidence: "user"` の項目は存在せず、変更対象にも含まれていない
- 既存の policy/rule/constraint の削除・書き換えは行わず、新規追加のみ実施した
- 全新規項目の confidence は "medium"、source_model の先頭に "infra: " を付与した
