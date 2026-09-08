# 変更サマリ

- event_id: 20260908_015000_feedback_slot_status_wording
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording(nfr:20260908_013000_feedback_slot_status_wording は no-change manifest。nfr/latest の head event は 20260907_120000_feedback_abort_consistency のまま)
- created_at: 2026-09-08T01:50:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクションは data_architecture のみ)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項(2026-09-08 DIST-029 A)をそのまま採用。確認推奨項目は完了報告で返却)
- feedback request: 20260908_slot_status_wording(direct work unit: なし。causal work unit: CR-c770d8f0-019#1。packet: docs/pipeline/feedback-runs/20260908_slot_status_wording/stage-packets/architecture.md)

```yaml
feedback_request:
  feedback_request_id: "20260908_slot_status_wording"
  input_sha256: "19b24f61aa56ced09d1b35120acf027c40554b785129c5c945f33c55bd8d7fcf"
  request_ids: ["CR-c770d8f0-019"]
  work_unit_ids: ["CR-c770d8f0-019#1"]
```

マージ規則: `entities` は `id`(= `name`)、`storage_mapping` は `entity_id` + `storage_type` をキーに、diff の要素で latest の同キー要素を置き換えた。E-014 の file 側 storage_mapping、diagram_mermaid、domain / system / app の各セクションは変更なし。`confidence: "user"` の項目は diff に含めず変更していない。

## 追加

- なし

## 変更

- data_architecture/entities/E-014 slot 実行: status 属性の説明を「速報有効時は管理 DB にも同じ状態を保持する」から「速報有効時は管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した場合、管理 DB は ABORTED のまま残し、ファイル正本の導出値(exitcode.txt 優先)へ再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料として使う」に改めた(CR-c770d8f0-019)
- data_architecture/storage_mapping/E-014(rdb): 理由の「状態(ABORTED を含む)をファイル正本と同じ値で管理 DB にも保持し」を「状態を管理 DB にも保持し ... status は aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort 後に実装が走り切って exitcode.txt を公開しても ABORTED のまま残し、ファイル正本の導出値へ再同期しない」に改め、用途に dispatcher の中止済み run 判定(条件「中止済み run の比較依頼作成除外」)を追加。二重マッピングの位置づけを「管理 DB 複製」から「管理 DB への一度書き」に改めた(CR-c770d8f0-019)

## 削除

- なし

## 変更なしと判断した関連項目

- LP-021(tier-ops repository): 管理 DB の ABORTED 更新は WHERE 句で現在状態(slot 実行は RUNNING かつ background)を条件にする条件付き UPDATE と既に記述しており、新文言の「条件付き更新(RUNNING のときだけ)」と整合する
- SP-009 / LP-023 / BC-002 用語「両系成功」/ E-016 の E-014 への関係: 判定材料を「slot_executions.status(aborted.txt のミラー)」と記述しており、abort 後に ABORTED が残る新文言と整合する
- LP-005(tier-facade domain): ファイル正本からの状態導出規則をドメイン層の関数として実装する記述で、管理 DB 側の文言を含まない
- CTR-001 / SR-001 / arch-decision-017: 旧文言「同じ状態を保持する」の引用は無い

## 照合結果(work unit)

| work unit | 種別 | status | 反映先 |
|---|---|---|---|
| CR-c770d8f0-019#1 | causal | changed | data_architecture/entities/E-014(status 属性説明)、data_architecture/storage_mapping/E-014(rdb 側の理由)(arch-decision-018) |

## 仮採用(confidence: low)

- なし(今回の差分で新規 low は作らない。既存の low は集約境界仮説 AG-* と storage_mapping E-009 / E-022 で、本 CR の対象外)

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した。実装挙動は不変で、文言参照の追従のみ)
