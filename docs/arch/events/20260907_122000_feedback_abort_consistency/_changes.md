# 変更サマリ

- event_id: 20260907_122000_feedback_abort_consistency
- trigger_event: rdra:20260907_114000_feedback_abort_consistency, nfr:20260907_120000_feedback_abort_consistency
- created_at: 2026-09-07T12:20:00Z
- mode: 差分更新(arch-design-diff.yaml)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項(2026-09-07 DIST-025 A / DIST-026 A / DIST-027 A)をそのまま採用。確認推奨項目は完了報告で返却)
- feedback request: 20260907_abort_consistency(direct work unit: なし。causal work unit: CR-c770d8f0-016#1, CR-c770d8f0-017#1, CR-c770d8f0-018#1。packet: docs/pipeline/feedback-runs/20260907_abort_consistency/stage-packets/architecture.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_abort_consistency"
  input_sha256: "70cda63f92e887e459a3817580e45a840e3ff201065a534085ad113fb8910b81"
  request_ids: ["CR-c770d8f0-016","CR-c770d8f0-017","CR-c770d8f0-018"]
  work_unit_ids: ["CR-c770d8f0-016#1","CR-c770d8f0-017#1","CR-c770d8f0-018#1"]
```

マージ規則: `bounded_contexts` / `context_map` / `aggregate_hypotheses` は `id`、`tiers` は `id`、`tier_layers` は `tier_id`、`entities` は `id`(= `name`)をキーに、diff の要素で latest の同キー要素を置き換えた(latest に無い要素は追加)。`confidence: "user"` の項目(CTR-005)は diff に含めず変更していない。storage_mapping と diagram_mermaid は変更なし。

## 追加

- app_architecture/tier_layers/tier-rapid-crosscheck/L-rapid-usecase: LP-024 claim 後の比較開始は条件付き UPDATE で判定する(worker は status = CLAIMED 条件の条件付き UPDATE で RUNNING にし、0 件(abort-rapid-crosscheck で ABORTED 済み)なら比較ツールを起動せず comparison_result も登録せず正常終了)(CR-c770d8f0-017)
- data_architecture/entities/E-016 速報実行: E-014(slot 実行)への関係(完了通知の対象 slot の slot 実行が ABORTED なら中止済み run として依頼を作成しない。foreground 完了後の background 中止はこの側で除外)(CR-c770d8f0-016)
- domain_architecture/aggregate_hypotheses/AG-002: 不変条件「CLAIMED から RUNNING への遷移は status = CLAIMED を条件とする条件付き UPDATE で行い、0 件なら worker は比較を開始しない」(CR-c770d8f0-017)

## 変更

- system_architecture/tiers/tier-rapid-crosscheck/SP-009: 中止済み run の判定キーを「並行稼働実行 ABORTED、または完了通知の対象 slot の slot 実行 ABORTED(aborted.txt 公開済み)」に拡張。判定材料(parallel_run.status / slot_executions.status)と foreground 完了後の background 中止が slot 実行 ABORTED 側で除外されることを明記。source_model に 状態・情報「slot 実行」、NFR C.3.3.1(CR-c770d8f0-016)
- system_architecture/tiers/tier-rapid-crosscheck/SP-011: worker の RUNNING 遷移を status = CLAIMED 条件の条件付き UPDATE とし、0 件なら比較を開始しない。source_model に条件「依頼中止可否判定」、状態「クロスチェック依頼」(CR-c770d8f0-017)
- system_architecture/tiers/tier-ops/SP-022: abort-rapid-crosscheck の対象を REQUESTED / CLAIMED / RUNNING に拡張(worker 停止確認のうえ status IN 条件の条件付き UPDATE。CLAIMED 放置時の lease 失効 → 再 claim の抜けを塞ぐ)、abort-final-crosscheck は RUNNING のみ(確報の未着手依頼は polling 上限で扱う)、abort-blue / abort-green の REQUESTED 依頼 ABORTED 化を「完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定(SP-009)と併用」に位置づけ直し。source_model に条件「中止済み run の比較依頼作成除外」、情報「確報比較依頼」、バリエーション「中止対象種別」「停止確認応答」(CR-c770d8f0-017 / 018)
- app_architecture/tier_layers/tier-rapid-crosscheck: usecase 責務(中止済み run 判定に対象 slot の slot 実行を追加。worker の RUNNING 遷移は条件付き UPDATE)、LP-023(parallel_run.status と slot_executions.status のいずれかが ABORTED なら依頼を作成しない)、domain 責務と LP-010(依頼作成可否 = 中止済み判定(並行稼働実行 ABORTED / 対象 slot の slot 実行 ABORTED / いずれでもない)× 両系成功判定。ライフサイクルに REQUESTED / CLAIMED / RUNNING → ABORTED と CLAIMED → RUNNING の条件付き遷移)、repository 責務(slot 実行の状態参照)、gateway 責務(CLAIMED → RUNNING の条件付き UPDATE。更新件数を返す)、CLP-004(worker が 0 件で比較を開始しなかったこともログに残す)(CR-c770d8f0-016 / 017)
- app_architecture/tier_layers/tier-ops: usecase 責務(abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING、abort-final-crosscheck は RUNNING のみ。REQUESTED 依頼 ABORTED 化は競合窓の保険)、domain 責務と LP-019(中止可否判定表にクロスチェック種別 × 依頼状態を追加。source_model にバリエーション「中止対象種別」「クロスチェック依頼状態」)、LP-021(abort-rapid-crosscheck は WHERE status IN ('REQUESTED', 'CLAIMED', 'RUNNING') で 0 件はエラー、abort-final-crosscheck は WHERE status = RUNNING、abort-blue / abort-green の REQUESTED 更新は保険で該当なしは正常)(CR-c770d8f0-017 / 018)
- domain_architecture/bounded_contexts/BC-002: 用語「両系成功」の中止済み run 定義に対象 slot の slot 実行 ABORTED と判定材料を追加。source_model に 情報・状態「slot 実行」、条件「依頼中止可否判定」(CR-c770d8f0-016)
- domain_architecture/bounded_contexts/BC-004: 用語「明示中止」に中止できる状態(速報比較依頼は REQUESTED / CLAIMED / RUNNING、他は RUNNING のみ)と REQUESTED 依頼 ABORTED 化の保険としての位置づけを明記。source_model に条件「依頼中止可否判定」、バリエーション「中止対象種別」「停止確認応答」(CR-c770d8f0-017 / 018)
- domain_architecture/context_map/CM-005: abort-rapid-crosscheck が REQUESTED / CLAIMED / RUNNING を条件付き UPDATE で ABORTED にすること、abort-blue / abort-green の REQUESTED 更新は競合窓の保険、CLAIMED 中止後に比較を開始しない規則は BC-002 の worker が持つことを明記(CR-c770d8f0-017 / 018)
- domain_architecture/aggregate_hypotheses/AG-002: 不変条件「中止済み run(並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)では依頼を作成しない」「REQUESTED 依頼は abort-blue / abort-green(保険)または abort-rapid-crosscheck で ABORTED」に更新。source_model に 情報・状態「slot 実行」、条件「依頼中止可否判定」(CR-c770d8f0-016 / 017 / 018)
- data_architecture/entities/E-016 速報実行: completion_status の説明と E-013 / E-017 への関係説明を中止済み run の新定義に更新(CR-c770d8f0-016)
- data_architecture/entities/E-017 速報比較依頼: status の説明(REQUESTED → ABORTED は abort-blue / abort-green(保険)または abort-rapid-crosscheck、CLAIMED / RUNNING → ABORTED は abort-rapid-crosscheck、CLAIMED → RUNNING は条件付き UPDATE で 0 件なら比較を開始しない)(CR-c770d8f0-017 / 018)
- data_architecture/entities/E-024 中止指示: resulting_status の説明と E-017 / E-019 への関係説明(abort-rapid-crosscheck の対象 3 状態、abort-final-crosscheck は RUNNING のみ、REQUESTED 依頼 ABORTED 化は保険)(CR-c770d8f0-017 / 018)

## 削除

- なし

## 照合結果(work unit)

| work unit | 種別 | status | 反映先 |
|---|---|---|---|
| CR-c770d8f0-016#1 | causal | changed | SP-009 / LP-010 / LP-023 / L-rapid-usecase・domain・repository 責務 / CLP-004 / BC-002 / AG-002 / E-016(E-014 への関係を追加) |
| CR-c770d8f0-017#1 | causal | changed | SP-011 / SP-022 / LP-024(新規)/ LP-019 / LP-021 / L-rapid-usecase・domain・gateway 責務 / L-ops-usecase・domain 責務 / BC-004 / CM-005 / AG-002 / E-017 / E-024 |
| CR-c770d8f0-018#1 | causal | changed | SP-022 / LP-021 / L-ops-usecase 責務 / BC-004 / CM-005 / AG-002 / E-017 / E-024(REQUESTED → ABORTED を競合窓の保険と位置づけ直し) |

## 仮採用(confidence: low)

- なし(今回の差分で新規 low は作らない。既存の low は集約境界仮説 AG-* と storage_mapping E-009 / E-022 で、本 CR の対象外)

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した。LP-024 の「更新件数 0 は comparison_result を登録せず正常終了」と abort-rapid-crosscheck の「終端済みは更新件数 0 をエラー」は RDRA の条件「依頼中止可否判定」「比較結果の登録条件」から導いた設計判断であり、arch-decision-017 に記録した)
