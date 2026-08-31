# infra イベント変更サマリ

- event_id: `20260830_190412_infra_product_design`
- trigger_event: `arch:20260830_184457_initial_arch, nfr:20260830_183726_initial_nfr`
- 種別: 初期構築(relay-gate の infra イベントは今回が初回)

## 追加

MCL product-design(vendor: onprem)によるインフラ設計一式を新規生成した。

- `docs/mcl/product/input/product-input.yaml` — arch-design.yaml + nfr-grade.yaml からの MCL 入力変換
- `docs/mcl/product/output/product-workload-model.yaml` — ベンダー中立ワークロードモデル(9特性 + 8 canonical elements)
- `docs/mcl/product/output/product-mapping-onprem.yaml` — オンプレミス サービスマッピング(systemd/PostgreSQL/ローカルディスク/Postfix)
- `docs/mcl/product/output/product-impl-onprem.yaml` — 実装仕様(8コンポーネント、configuration + validation_rules)
- `docs/mcl/product/output/product-observability.yaml` — SLI/SLO・ログ・トレーシング・ダッシュボード・アラート仕様
- `docs/mcl/product/output/product-cost-hints.yaml` — コスト最適化ヒント(6カテゴリ)
- `docs/cloud-context/decisions/product/product-decision-{001..005}.yaml` — 実行基盤/DBエンジン/成果物ストレージ/メールMTA/バックアップ監視の決定記録
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml` — 23要件の適合性検証(conformant 18 / partial 5 / non_conformant 0)
- `docs/cloud-context/generated-md/product/relay-gate-target-architecture.md` — Mermaid図付きアーキテクチャドキュメント
- `infra/product/onprem/terraform/` — ホスト/セグメントの論理定義(プレースホルダ。provider未確定)
- `infra/product/onprem/ansible/` — 5ロール(runtime/postgresql/config/mail/backup)のIaCスケルトン
- `docs/cloud-context/sources/onprem/` — ベンダーソース4件(PostgreSQL HA / RabbitMQ / MinIO / Redis)

## 変更

なし(初期構築)

## 削除

なし

## 備考

- `docs/mcl/foundation/output/foundation-context.yaml` と `docs/mcl/shared-platform/output/shared-platform-context.yaml` は
  mcl-foundation-design / mcl-shared-platform-design 未実施のため、dist-infrastructure がプロジェクト前提から
  最小構成として自動生成したもの(`_inference.md` 参照)。正式な foundation/shared-platform 設計を実施した場合は
  本イベントを再実行して置き換える。
- confidence: low の項目(REQ-OPS-002: 組織既存監視の有無)は保守的な⭐推奨(既存監視への統合、無ければfallback)を
  仮採用し、`docs/todo.md`(DIST-013)に確認事項として登録した。
