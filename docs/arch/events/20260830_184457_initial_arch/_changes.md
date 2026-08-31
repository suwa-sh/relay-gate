# 変更サマリ

- event_id: 20260830_184457_initial_arch
- trigger_event: rdra:20260830_181841_initial_build, nfr:20260830_183726_initial_nfr
- mode: 初期構築(全要素を「追加」として記載)
- dialogue_policy: auto_adopt

## 追加

### technology_context
- languages: bash / SQL / JavaScript(BDD step のみ)
- frameworks: なし
- constraints: エアーギャップ / UI なし / HTTP API なし / IdP・APIGW・認可サービス非導入 / 方針資料 C2-C4 と Runner Result Contract の尊重 / 設定所有区分 / RDB 1 種 / 中立表現 / 監査はジョブスケジューラ

### domain_architecture
- subdomains: SD-001 実装切替(core) / SD-002 クロスチェック(core) / SD-003 監視と復旧(supporting) / SD-004 適用構成(supporting)
- bounded_contexts: BC-001 並行稼働実行 / BC-002 速報クロスチェック / BC-003 確報クロスチェック / BC-004 実行監視・復旧 / BC-005 適用構成
- context_map: CM-001〜CM-008(Conformist × 6、OHS+PL × 1、Shared Kernel × 1)
- aggregate_hypotheses: AG-001〜AG-005(全件 low)

### system_architecture
- tiers: tier-facade / tier-rapid-crosscheck / tier-final-crosscheck / tier-ops / tier-datastore
- tier policies SP-001〜SP-026、tier rules SR-001〜SR-006
- cross_tier_policies CTP-001〜CTP-009、cross_tier_rules CTR-001〜CTR-005

### app_architecture
- tier_layers: tier-facade / tier-rapid-crosscheck / tier-final-crosscheck / tier-ops に 5 層(presentation → usecase → domain → repository / gateway)
- layer policies LP-001〜LP-021、cross_layer_policies CLP-001〜CLP-008、cross_layer_rules CLR-001〜CLR-004

### data_architecture
- entities: E-001〜E-025(情報.tsv の 25 情報すべて)
- storage_mapping: 26 件(E-014 slot 実行は file + rdb の二重マッピング)

### decisions
- arch-decision-001〜010

## 変更
- なし

## 削除
- なし
