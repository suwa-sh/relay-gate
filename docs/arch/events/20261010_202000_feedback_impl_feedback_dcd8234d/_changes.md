# 変更サマリ

- event_id: 20261010_202000_feedback_impl_feedback_dcd8234d
- trigger_event: rdra:20261010_200000_feedback_impl_feedback_dcd8234d, nfr:20261010_201000_feedback_impl_feedback_dcd8234d
- created_at: 2026-10-10T20:20:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクション: technology_context / domain_architecture / system_architecture / app_architecture / data_architecture)
- dialogue_policy: auto_adopt(確認推奨項目は末尾に記載し ⭐ 推奨を採用)
- feedback request: 20261010_104636_impl_feedback_dcd8234d(direct work unit: CR-dcd8234d-001#1, CR-dcd8234d-003#1。causal work unit: CR-dcd8234d-007#1, CR-dcd8234d-001#1, CR-dcd8234d-002#1, CR-dcd8234d-003#1。packet: docs/pipeline/feedback-runs/20261010_104636_impl_feedback_dcd8234d/stage-packets/architecture.md)

```yaml
feedback_request:
  feedback_request_id: "20261010_104636_impl_feedback_dcd8234d"
  input_sha256: "d4ddd211752998f5480a51d9dddfa3a58937badd62f72092c9257ed1384448fd"
  request_ids: ["CR-dcd8234d-007","CR-dcd8234d-001","CR-dcd8234d-002","CR-dcd8234d-003"]
  work_unit_ids: ["CR-dcd8234d-007#1","CR-dcd8234d-001#1","CR-dcd8234d-002#1","CR-dcd8234d-003#1"]
```

マージ規則: `system_architecture.tiers` は `id`、`app_architecture.tier_layers` は `tier_id`、`data_architecture.entities` は `name`(= `id`)、`data_architecture.storage_mapping` は `entity_id`、`domain_architecture.bounded_contexts / context_map / aggregate_hypotheses` は `id` をキーに、diff の要素で latest の同キー要素を置き換えた。`technology_context` はセクション単位で置き換えた。`cross_tier_rules` は CTR-007 を追加した。下記「## 削除」の要素は latest から除去した。`confidence: "user"`(CTR-005)は diff に含めず変更していない。

本イベントは、validate-config.sh のティア間共有・名前空間規則の決定(direct: CR-dcd8234d-001 / CR-dcd8234d-003)と、クロスチェック簡素化(causal: CR-dcd8234d-007)への追従を arch へ反映する。方針資料(tmp/RelayGateのしくみ.md / tmp/RelayGateの利用イメージ.md)は validate-config.sh の内部構成を定めておらず、本変更と矛盾しない。

## 追加

- system_architecture/cross_tier_rules: CTR-007「ティアは独立プロセス・ティア間のシェル関数共有の規則」。各ティアの CLI は独立プロセスで原則として他ティアのシェルファイルを source しない。validate-config.sh は全設定ファイルを tier-facade 自身の解析関数で検証し他ティアの検証関数を委譲しない(委譲撤廃)。将来の source 併用に備えた名前空間の一般規則(ティア固有接頭辞・共有面の限定公開・副作用禁止・再定義禁止)を残す(CR-dcd8234d-001, CR-dcd8234d-003)
- data_architecture/entities/E-017 速報比較依頼: 属性 parameters / blue_exit_code / green_exit_code を追加(worker が起動コマンドを置換できる値を依頼レコードで揃える)(CR-dcd8234d-007)
- data_architecture/entities/E-027 速報クロスチェック設定: 属性 rapid_compare_command(速報の比較ツール起動コマンド 1 行。{job_id} 必須)を追加(CR-dcd8234d-007)

## 変更

- app_architecture/tier_layers/tier-rapid-crosscheck/CLP-003: ティア間のシェル関数共有は CTR-007 に従い、本ティアは validate-config.sh へ検証関数を提供せず source されない旨を注記(CR-dcd8234d-001, CR-dcd8234d-003)
- technology_context/constraints: 設定契約の列挙から「クロスチェックジョブマップ」を外し、速報クロスチェック設定・確報クロスチェック worker 設定を加えた(CR-dcd8234d-007)
- domain_architecture/bounded_contexts/BC-002: owned_entity から E-018 を外し、reason / source_model から comparison_result を外した(CR-dcd8234d-007)
- domain_architecture/bounded_contexts/BC-003: ユビキタス言語の確報比較依頼を業務上の引数なしへ改め、対象カタログの語を削除。reason / source_model から対象カタログを外した(CR-dcd8234d-007)
- domain_architecture/bounded_contexts/BC-005: owned_entity から E-007 / E-008 を外し、設定所有区分の語と source_model からクロスチェックジョブマップ・対象カタログを外した(CR-dcd8234d-007)
- domain_architecture/context_map/CM-007: 翻訳記述を速報クロスチェック設定の起動コマンド({job_id} を依頼レコードの値で置換)へ改めた(CR-dcd8234d-007)
- domain_architecture/context_map/CM-008: 翻訳記述を確報クロスチェック worker 設定の起動コマンド(業務上の引数なし)へ改めた(CR-dcd8234d-007)
- domain_architecture/aggregate_hypotheses/AG-002: member から E-018 を外し、不変条件の「成果物 URI」を「終了コード」へ、source_model から comparison_result を外した(CR-dcd8234d-007)
- domain_architecture/aggregate_hypotheses/AG-003: 不変条件から business_date・対象カタログの版を外し、業務上の引数なしの登録へ改めた(CR-dcd8234d-007)
- system_architecture/tiers/tier-rapid-crosscheck: technology_candidates から comparison_result を外し、比較ツール起動アダプタを起動コマンド置換に改めた。SP-009 の完了事実「成果物 URI」を「終了コード」へ、SP-011 をクロスチェックジョブマップ CSV の比較定義から速報クロスチェック設定の起動コマンド置換・stdout/stderr/exit_code 保存へ、SP-012 を依頼レコードの参照へ改め、SR-003 から comparison_result を外した(CR-dcd8234d-007)
- system_architecture/tiers/tier-final-crosscheck: technology_candidates から対象カタログを外し、SP-013 / SP-015 を業務上の引数なし・確報 worker 設定の起動コマンドへ、SR-004 から対象カタログを外した(CR-dcd8234d-007)
- system_architecture/tiers/tier-datastore: ティア説明の設定ファイル列挙と SP-023 / SP-025 からクロスチェックジョブマップ・対象カタログ・comparison_result を外し、比較ツール起動コマンドの所有(速報クロスチェック設定・確報クロスチェック worker 設定)へ改めた(CR-dcd8234d-007)
- app_architecture/tier_layers/tier-rapid-crosscheck: L-rapid-presentation LP-008 から成果物ディレクトリ(artifact_uri)を外し、L-rapid-usecase 責務の comparison_result 登録を起動コマンド置換・依頼レコード保存へ、LP-023 の「成果物 URI」を「終了コード」へ、LP-024 から comparison_result を外し、L-rapid-repository の責務からクロスチェックジョブマップ比較定義・comparison_result を外し速報クロスチェック設定の起動コマンドへ、LP-011 を起動コマンド置換へ、図から comparison_result を外した(CR-dcd8234d-007)
- app_architecture/tier_layers/tier-final-crosscheck: L-final-presentation 責務を業務上の引数なしへ、L-final-repository / L-final-gateway / 全量比較起動ポリシーを確報 worker 設定の起動コマンドへ、CLP の実行ログから business_date を外し、図から対象カタログを外した(CR-dcd8234d-007)
- data_architecture/entities/E-006 比較定義: 比較ツール起動コマンド 1 行に簡素化(crosscheck_type / definition_version / tool_command)。comparison_type / targets / tool_options を外し、E-007 への関係を E-027 への関係へ改めた(CR-dcd8234d-007)
- data_architecture/entities/E-015 完了通知: 属性 artifact_uri を外した(run_id / job_id / exit_code を渡す)(CR-dcd8234d-007)
- data_architecture/entities/E-016 速報実行: 属性 blue_artifact_uri / green_artifact_uri を外した(CR-dcd8234d-007)
- data_architecture/entities/E-017 速報比較依頼: E-018(comparison_result)への関係を外し、E-006 への関係を起動コマンド置換の説明へ改めた(CR-dcd8234d-007)
- data_architecture/entities/E-019 確報比較依頼: 属性 business_date / catalog_version を外し、E-008(対象カタログ)への関係を外した(CR-dcd8234d-007)
- data_architecture/entities/E-020 比較ツール実行結果: crosscheck_type の表記を「クロスチェック種別」に改め、依頼レコードの列へ保存し別レコード・ファイルに保存しない旨を明記(CR-dcd8234d-007)
- data_architecture/storage_mapping/E-006: クロスチェックジョブマップの一部から、速報クロスチェック設定・確報クロスチェック worker 設定の起動コマンドへ改めた(CR-dcd8234d-007)
- data_architecture/storage_mapping/E-015: 反映先から artifact_uri を外した(CR-dcd8234d-007)

## 削除

- data_architecture/entities/E-007 クロスチェックジョブマップ(ジョブ ID ごとの比較定義と対象カタログ参照の正本。比較対象の定義は比較ツール側へ移すため廃止)(CR-dcd8234d-007)
- data_architecture/entities/E-008 対象カタログ(確報の全量比較対象を版管理するカタログ。worker は依頼レコードの値だけで起動するため廃止)(CR-dcd8234d-007)
- data_architecture/entities/E-018 比較結果(comparison_result)(速報比較の差分件数・レポート URI レコード。結果は依頼レコードの stdout / stderr / exit_code で参照するため廃止)(CR-dcd8234d-007)
- data_architecture/storage_mapping/E-007, E-008, E-018(上記エンティティ廃止に伴う)(CR-dcd8234d-007)

## 変更なしと判断した関連項目

- tier-facade の SP-001〜SP-008 / LP-001〜LP-007 / LP-022: feature flag 9 キー・slot 起動・Runner Result・完了通知の系統独立は簡素化の影響を受けず、完了通知の属性変更(artifact_uri 除去)は E-015 / LP-008 で反映済み
- data_architecture/entities/E-013 並行稼働実行(parallel_run): comparison_result への関係を元々持たず、属性・関係とも不変
- data_architecture/entities/E-023 リラン指示: 属性・関係は source_run_id / role / precheck_result で、速報比較依頼の新規作成は role=rapid-crosscheck として既に表現しており、arch の属性レベルでは不変(成果物 URI 参照を持たない)
- CTR-001(Runner Result Contract)/ CTR-002(終了コード規約)/ CTR-003(gateway アダプタ)/ CTR-005 / CTR-006: 廃止要素への言及を持たず不変。CTR-005 は confidence: user のため diff に含めない

## 照合結果(work unit)

| work unit | 種別 | disposition / status | 反映先 |
|---|---|---|---|
| CR-dcd8234d-001#1 | direct | applied / changed | system_architecture/cross_tier_rules/CTR-007、app_architecture CLP-003(arch-decision-019) |
| CR-dcd8234d-003#1 | direct | applied / changed | system_architecture/cross_tier_rules/CTR-007(名前空間の一般規則)、app_architecture CLP-003(arch-decision-019) |
| CR-dcd8234d-007#1 | causal | changed | technology_context / domain / system / app / data の廃止構造追従(arch-decision-020) |
| CR-dcd8234d-002#1 | causal | not_impacted | arch は受け入れ基準・UC の Then を記述しないため影響なし(UC 仕様の Then 書き換えは下流 spec) |

## 仮採用(confidence: low)

- なし(今回の差分で新規 low は作らない。既存の low は集約境界仮説 AG-* と storage_mapping E-009 で、本 CR の対象は AG-002 / AG-003 の member・不変条件の追従のみ)

## 確認推奨項目

CR-dcd8234d-001 / CR-dcd8234d-003 のティア構成の決定(auto_adopt で ⭐ 推奨を採用):

- ⭐ 案1: 委譲を無くし facade 単独で設定検証を完結させる(既存 env 検証と同じ方式)。CTR-007 に「validate-config.sh は他ティアのファイルを source しない」旨を明記し、名前空間の規則は将来のティア追加に備えた一般規則として残す。採用理由: クロスチェック簡素化で速報の設定検証が env の起動コマンド 1 キーの検証(絶対パスで存在し実行可能・{job_id} を含む)に縮退し CSV クォート解析の共有が不要になったため、委譲を残す必然性が消えた。既存の feature-flag.env / rapid-crosscheck.env 検証と同じく facade が所有して単独で完結でき、結合面が最小になる
- 案2: 委譲を残し、共有面の契約(提供側・利用側・関数集合)+ 登録方式 案A(固定パス `<tier>/src/presentation/validate_config_<kind>.sh` を存在時のみ source、関数 `validate_config_<kind> <path> <verbose>`)+ 名前空間の規則を CTR-007 に追加する。簡素化前に CSV クォート解析を共有していた構成の延長
- 案3: 名前空間規則を設けず委譲も契約化しない(現状維持)

名前空間の一般規則を CTR-007 に残すか(将来ティア追加用): ⭐ 残す。安価な保険であり、同一プロセスの名前衝突(実装で終了コード 6 の内部障害が実際に発生)の再発を防ぐ一般規則として有用。委譲を無くしても facade の共有面・将来の source 併用に備えて明記する
