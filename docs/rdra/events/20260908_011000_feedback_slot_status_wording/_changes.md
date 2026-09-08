# 変更サマリ

- event_id: 20260908_011000_feedback_slot_status_wording
- 元USDM: docs/usdm/events/20260908_011000_feedback_slot_status_wording/requirements.yaml
- 生成日時: 2026-09-08T01:10:00
- feedback request: 20260908_slot_status_wording(direct / causal work unit: CR-c770d8f0-019#1。packet: docs/pipeline/feedback-runs/20260908_slot_status_wording/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20260908_slot_status_wording"
  input_sha256: "19b24f61aa56ced09d1b35120acf027c40554b785129c5c945f33c55bd8d7fcf"
  request_ids: ["CR-c770d8f0-019"]
  work_unit_ids: ["CR-c770d8f0-019#1"]
```

マージ規則の補足: 条件.tsv はコンテキスト + 条件のキーで latest の同一行をイベント側の内容で置き換える。変更は条件の説明列のみで、バリエーション列・状態モデル列・判定表の説明(縦軸 exitcode.txt、横軸 aborted.txt)は変更しない。

## 追加

- なし

## 変更

- 条件: slot 実行の状態導出規則 → 管理 DB 側の文言「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」を「速報クロスチェック有効時は、管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した場合、管理 DB は ABORTED のまま残し、ファイル正本の導出値(exitcode.txt 優先)へ再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料として使う」に改める(CR-c770d8f0-019)

## 削除

- なし
