# RDRA フィードバック（Spec 生成時の発見事項）

本ファイルは、Spec 生成時に「Spec 側だけでは解消できず、RDRA モデル（および USDM）側の見直しが必要」と判定した項目を記録する。

## 変更要望一覧

| # | 種別 | 対象 RDRA 要素 | 変更内容 | 理由 | 状態 |
|---|------|---------------|---------|------|------|
| 1 | 追加 | 情報: 比較定義 | job_id ごとの比較対象・比較実装を保持する情報エンティティを追加する。属性の候補は job_id / 比較対象テーブル / 比較対象ファイル / 比較実装識別子 / 有効期間 | USDM SPEC-012-03「比較定義は job_id ごとに差し替えられる」の acceptance criterion を検証する Scenario を書けない。比較定義に相当する情報が RDRA 情報モデルに存在せず、Spec 側で発明すると RDRA 整合性ルールに違反するため | **解消済み** |
| 2 | 変更 | 情報: execution-spec.json の属性「マップ版」/ 情報: slot別実行設定 | 属性「マップ版」を execution-spec.json（run 共通）から slot別実行設定へ移す（slot ごとの独立したジョブマップの版を slot 別に記録するため） | feedback request 20260822_085257_impl_feedback_6078c4ed の CR-6078c4ed-018（採用済み）で job_map_version を slot_execution_specs へ移動した。RDRA 情報.tsv の属性配置がこれと食い違うため、requirements 側の差分更新で整合させる必要がある。spec 側は RDRA 整合性ルールに従い属性を自動追加せず、トレーサビリティは execution-spec.json.マップ版 → slot_execution_specs.job_map_version として維持している | **未解消** |

## 変更要望 #1 の解消記録

feedback request `20260818_164000_rdra_followup_6078c4ed` の CR-6078c4ed-009 として起票され、上流で反映済みである。

| 反映先 | 内容 |
|---|---|
| RDRA 情報.tsv | 業務「クロスチェック定義管理」に情報「比較定義」（属性: JOB_ID、比較対象テーブル、比較対象ファイル、比較実装識別子、有効期間。関連情報: 速報比較依頼、確報比較依頼）を追加 |
| USDM | SPEC-012-03 の acceptance criteria に、有効期間に該当する比較定義を 1 件解決する条件を追加 |
| infra | comp-datastore-rdb に `comparison_definitions`（(job_id, valid_from) 複合主キー、現行世代の部分一意索引、有効期間の排他制約、世代追記のみ）を追加 |
| spec（本イベント） | `_cross-cutting/datastore/rdb-schema.yaml` に `comparison_definitions` テーブルを追加し、`rapid_crosscheck_requests` / `final_crosscheck_requests` に依頼時点で解決した世代（`comparison_definition_valid_from`）を保持させた。速報・確報の比較実行 UC と速報比較依頼作成 UC に、job_id 別比較定義の適用と有効期間による 1 件解決の BDD Scenario を追加した |

この結果、`usdm-acceptance-matrix.md` の SPEC-012-03 は全 acceptance criterion が UC Scenario へ対応付き、USDM acceptance criteria 単位の逆引き網羅率は 100% になった。

## 現在未解消の変更要望

#2（1 件）。

- 対応方針: dist-requirements の差分更新で RDRA 情報.tsv の属性「マップ版」を execution-spec.json から slot別実行設定へ移す。
- その後 dist-spec を再実行し、traceability-matrix.md の対応列を slot別実行設定.マップ版 → slot_execution_specs.job_map_version へ更新する。
