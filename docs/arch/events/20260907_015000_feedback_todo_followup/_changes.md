# 変更サマリ

- event_id: 20260907_015000_feedback_todo_followup
- trigger_event: rdra:20260907_011000_feedback_todo_followup, nfr:20260907_013000_feedback_todo_followup
- created_at: 2026-09-07T01:50:00Z
- mode: 差分更新(arch-design-diff.yaml)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項は決定を採用。確認推奨項目は完了報告で返却)
- feedback request: 20260907_todo_followup(direct work unit: CR-c770d8f0-015#1。causal work unit: CR-c770d8f0-013#1, CR-c770d8f0-014#1, CR-c770d8f0-015#1。packet: docs/pipeline/feedback-runs/20260907_todo_followup/stage-packets/architecture.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_todo_followup"
  input_sha256: "193823ac1e6f02400269d6bdca461150a1fc8951393f332ef28580e045261389"
  request_ids: ["CR-c770d8f0-013","CR-c770d8f0-014","CR-c770d8f0-015"]
  work_unit_ids: ["CR-c770d8f0-013#1","CR-c770d8f0-014#1","CR-c770d8f0-015#1"]
```

マージ規則: `bounded_contexts` / `context_map` / `aggregate_hypotheses` は `id`、`tiers` / `cross_tier_policies` は `id`、`tier_layers` は `tier_id`、`entities` は `id`(= `name`)、`storage_mapping` は `entity_id` + `storage_type` をキーに、diff の要素で latest の同キー要素を置き換えた(latest に無い要素は追加)。`confidence: "user"` の項目(CTR-005)は diff に含めず変更していない。`data_architecture.diagram_mermaid` は全置換。

## 追加

- data_architecture/entities: E-027 速報クロスチェック設定(db_conn_ref = RAPID_DB_CONN_REF / lease_sec = RAPID_LEASE_SEC / poll_interval_sec = RAPID_POLL_INTERVAL_SEC。resource_mutable。BC-005 所有。E-017 / E-013 / E-015 / E-026 への関係)(CR-c770d8f0-013)
- data_architecture/storage_mapping: E-027 → file(env 形式 rapid-crosscheck.env。速報有効時に facade・slot runner・速報クロスチェック runner・worker が起動のたびに読む。off では読まない)(CR-c770d8f0-013)
- data_architecture/diagram_mermaid: RAPID_CROSSCHECK_CONFIG → RAPID_CROSSCHECK_REQUEST(lease_and_poll)/ PARALLEL_RUN(db_conn_ref)(CR-c770d8f0-013)
- data_architecture/entities/E-015: E-027 への関係(管理 DB 接続参照名の出所)(CR-c770d8f0-013)
- data_architecture/entities/E-016: E-025 への関係(中止済み run で依頼を作成しなかったことの警告ログ)(CR-c770d8f0-014)
- data_architecture/entities/E-017: E-027 への関係(lease 期間・poll 間隔の出所)(CR-c770d8f0-013)
- domain_architecture/bounded_contexts/BC-005: ユビキタス言語「速報クロスチェック設定」、owned_entity_ids に E-027(CR-c770d8f0-013)
- domain_architecture/aggregate_hypotheses/AG-002: 不変条件「並行稼働実行が ABORTED の run では両系成功でも速報比較依頼を作成しない」「REQUESTED で未着手の速報比較依頼は abort-blue / abort-green で ABORTED になる」(CR-c770d8f0-014)
- app_architecture/tier_layers/tier-rapid-crosscheck: LP-023 中止済み run では依頼を作成しない(usecase 層。dispatcher が parallel_run の状態を読み、ABORTED なら完了事実の記録と warning のみ)(CR-c770d8f0-014)

## 変更

- app_architecture/tier_layers/tier-facade/CLP-002 実行ログの出力方針: 「TZ は UTC に統一する」を削除し、ログ日時をホストのローカルタイムゾーン(ISO 8601 秒精度、タイムゾーン指示子なし。run_id の時刻部と同じ時刻軸)に改める。管理 DB の *_at 列は RDB のタイムスタンプ型に委ね、CLI の stdout もローカル時刻。RELAY_GATE_NOW は UTC Z 付き入力 → ローカル変換を維持。confidence medium → high(利用者決定)(CR-c770d8f0-015)
- app_architecture/tier_layers/tier-rapid-crosscheck/CLP-004: CLP-002 と同一(ローカルタイムゾーン)であることと、dispatcher の中止済み run の warning を明記(CR-c770d8f0-014 / 015)
- system_architecture/cross_tier_policies/CTP-003: 実行ログの出力日時が run_id の時刻部と同じ時刻軸(ローカルタイムゾーン、指示子なし)であることを明記(CR-c770d8f0-015)
- data_architecture/entities/E-025 実行ログ: occurred_at の説明をローカルタイムゾーン(指示子なし)に変更(CR-c770d8f0-015)
- data_architecture/entities/E-015 完了通知: occurred_at の説明をローカルタイムゾーンに変更。E-016 への関係に「slot runner は自 slot の中止状態を判断せず通常どおり送る」を追記(CR-c770d8f0-014 / 015)
- domain_architecture/bounded_contexts/BC-002: 用語「完了通知」(自 slot の中止状態も判断しない)、「両系成功」(中止済み run では依頼を作成せず完了事実の記録と警告のみ。判断主体は dispatcher)。source_model に条件「中止済み run の比較依頼作成除外」(CR-c770d8f0-014)
- domain_architecture/bounded_contexts/BC-004: 用語「明示中止」に abort-blue / abort-green による未着手の速報比較依頼の ABORTED 化を追記。source_model に状態「クロスチェック依頼」、条件「slot 中止可否判定」(CR-c770d8f0-014)
- domain_architecture/bounded_contexts/BC-005: 用語「設定所有区分」に速報クロスチェック設定を追加。reason / source_model を更新(CR-c770d8f0-013)
- domain_architecture/context_map/CM-005: BC-004 が abort-blue / abort-green で REQUESTED の速報比較依頼を ABORTED にすること、比較の要否判断は BC-002 の dispatcher が持つことを明記(CR-c770d8f0-014)
- domain_architecture/aggregate_hypotheses/AG-002: claim の不変条件に lease 期間・poll 間隔の出所(速報クロスチェック設定)。source_model を更新(CR-c770d8f0-013 / 014)
- system_architecture/tiers/tier-facade: description / technology_candidates(速報有効時の管理 DB 接続参照名は速報クロスチェック設定から)、SP-008(runner は自 slot の中止状態も判断せず通常どおり完了通知を送る。管理 DB 接続は RAPID_DB_CONN_REF で解決)(CR-c770d8f0-013 / 014)
- system_architecture/tiers/tier-rapid-crosscheck: description / technology_candidates(接続参照名・lease 期間・poll 間隔の出所)、SP-009(並行稼働実行が ABORTED の run では両系成功でも依頼を作成せず、完了事実の記録と警告のみ。判断は dispatcher。速報有効時のみ)、SP-010(lease 期間 RAPID_LEASE_SEC・poll 間隔 RAPID_POLL_INTERVAL_SEC を速報クロスチェック設定から読む)(CR-c770d8f0-013 / 014)
- system_architecture/tiers/tier-ops/SP-022: abort-blue / abort-green が対象 run の REQUESTED で未着手の速報比較依頼も ABORTED にする(CLAIMED / RUNNING は abort-rapid-crosscheck の対象。確報には適用しない)。reason / source_model に状態「クロスチェック依頼」(REQUESTED → ABORTED)、NFR C.3.3.1(CR-c770d8f0-014)
- system_architecture/tiers/tier-datastore: description(設定ファイルに速報クロスチェック設定)、SP-025(速報クロスチェック設定の所有項目・読み手・off では不要・接続参照名は値を置かない。source_model に 情報「速報クロスチェック設定」、条件「認証情報の非保存」、NFR E.5.1.1)(CR-c770d8f0-013)
- app_architecture/tier_layers/tier-facade: repository 責務(速報クロスチェック設定の読み取り。速報有効時のみ)、gateway 責務(RDB アダプタは接続参照名で接続。完了通知アダプタは自 slot の中止状態を判断しない)(CR-c770d8f0-013 / 014)
- app_architecture/tier_layers/tier-rapid-crosscheck: usecase 責務(並行稼働実行の中止判定を追加)、domain 責務と LP-010(依頼作成可否 = 並行稼働実行の状態 × 両系成功判定の表。REQUESTED → ABORTED を含むライフサイクル)、repository 責務(parallel_run の状態参照、速報クロスチェック設定の読み取り)、gateway 責務(接続参照名)(CR-c770d8f0-013 / 014)
- app_architecture/tier_layers/tier-ops: usecase 責務(abort-blue / abort-green の未着手依頼 ABORTED 化)、domain 責務と LP-019(中止可否判定表に併せて中止する依頼の状態条件)、LP-021(依頼の ABORTED 更新は WHERE status = REQUESTED の条件付き UPDATE。該当なしは正常)(CR-c770d8f0-014)
- data_architecture/entities/E-016 速報実行: completion_status の説明(ABORTED run では比較依頼作成済みへ進めない)、E-013 / E-017 への関係説明(CR-c770d8f0-014)
- data_architecture/entities/E-017 速報比較依頼: status の説明(REQUESTED → ABORTED は abort-blue / abort-green、RUNNING → ABORTED は abort-rapid-crosscheck)、lease_until の説明(RAPID_LEASE_SEC)(CR-c770d8f0-013 / 014)
- data_architecture/entities/E-024 中止指示: resulting_status と E-017 への関係説明に未着手依頼の ABORTED 化(CR-c770d8f0-014)

## 削除

- app_architecture/tier_layers/tier-facade/CLP-002: 「TZ は UTC に統一する」の記述(CR-c770d8f0-015)

## 照合結果(work unit)

| work unit | 種別 | status | 反映先 |
|---|---|---|---|
| CR-c770d8f0-013#1 | causal | changed | E-027(新規)/ storage_mapping E-027 / diagram / BC-005 / AG-002 / SP-008 / SP-010 / SP-025 / tier-facade / tier-rapid-crosscheck / tier-datastore / E-015 / E-017 / repository・gateway 責務 |
| CR-c770d8f0-014#1 | causal | changed | BC-002 / BC-004 / CM-005 / AG-002 / SP-008 / SP-009 / SP-022 / LP-010 / LP-019 / LP-021 / LP-023(新規)/ CLP-004 / E-015 / E-016 / E-017 / E-024 |
| CR-c770d8f0-015#1 | direct(applied)/ causal(changed) | changed | CLP-002 / CLP-004 / CTP-003 / E-025 / E-015 |

## 仮採用(confidence: low)

- なし(今回の差分で新規 low は作らない。既存の low は集約境界仮説 AG-* と storage_mapping E-009 / E-022 で、本 CR の対象外)

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した。LP-021 の「REQUESTED 依頼の該当なしを正常扱い」と E-027 の関係定義は RDRA の条件・情報の記述から導いた設計判断であり、arch-decision-015 / 016 に記録した)
