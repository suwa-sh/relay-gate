# 変換推論根拠: 20260819_111931_infra_product_design

## 入力

- `docs/arch/latest/arch-design.yaml`（arch イベント 20260819_110531_arch_comparison_definition_exitcode 反映済み）
- `docs/nfr/latest/nfr-grade.yaml`（20260817_144844_initial_nfr。変更なし）
- 直前のインフラ成果物スナップショット `docs/infra/latest/`

差分反映モードのため、arch 差分の影響範囲だけを MCL 成果物へ写像した（MCL の全量再生成は行っていない）。

## 写像

| arch の変更 | 影響を受けた product-input / MCL 成果物 | 推論 |
|---|---|---|
| data_architecture/entities: E-008 比較定義（model_type: resource_scd2、PK: job_id + valid_from、valid_to / target_tables / target_files / comparator_id） | product-input elements[database].entities / requirements、product.persistence(REQ-PS-005)、mapping product.persistence、impl comp-datastore-rdb、conformance | storage_mapping で E-008 → rdb と確定しているため、既存の PostgreSQL 単一データストアへテーブルを追加する写像となる。resource_scd2 は有効期間列を持つ世代管理テーブルへ写像し、AG-006 の不変条件（有効期間の重複禁止・世代の追記管理）を主キー + 部分一意索引 + 排他制約という永続化層の制約へ落とす |
| AG-006（同一 JOB_ID で実行時点が有効期間に含まれる定義は高々1件、既存世代は不変、速報/確報は同一世代を参照） | impl comp-datastore-rdb の validation_rules、REQ-PS-005 | 集約不変条件のうちデータストアで強制できるものを static 制約として記述し、依頼側が解決済み世代の値を保持する点を configuration に明記した |
| BC-005 / CM-005 / CM-006（クロスチェック定義管理コンテキスト） | 影響なし | 論理的なコンテキスト分離であり、オンプレ単一 RDB・単一 facade/worker のティア構成を変えない。インフラ配置単位の追加は不要と判断した |
| SP-002（foreground exitcode 全値透過） / SR-006（退避コード 125 / 124、126・127 非衝突、UNKNOWN の推測変換禁止、stderr 併記） | product-input workload.description、product.workload_type(REQ-WT-003)、mapping product.workload_type、impl comp-facade、observability、conformance | 終了コードはプロセス起動契約そのものであり、facade コンポーネントの実装仕様（応答チャネル契約）に写像する。加えて、業務ジョブの異常終了率メトリクスに基盤自身のエラーが混入すると監視の意味が変わるため、オブザーバビリティ側で退避コードを分離集計する定義を追加した |
| E-007 の source_info 名称変更（情報: slot別実行設定） | 影響なし | 命名整合のみ。slot 別実行設定の分離自体は前回イベント 20260818_141149 で写像済み |

## ベンダー選定への影響

なし。オンプレミス限定（product-decision-onprem-only）と PostgreSQL + ローカルファイルシステムの選定は変更していない。比較定義テーブルは既存の RDB 内に収まり、新しいミドルウェアを必要としない。

## Arch へのフィードバック

今回のインフラ写像から arch へ戻すベンダーニュートラルな新規知見は発生しなかった（追加した制約はすべて arch 既存の SP-002 / SR-006 / AG-006 / storage_mapping から導出したもの）。したがって arch フィードバックイベントは作成していない。
