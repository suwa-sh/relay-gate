# 変更サマリ

- event_id: 20261103_081000_feedback_housekeeping_followups
- 元USDM: docs/usdm/events/20261103_081000_feedback_housekeeping_followups/requirements.yaml
- 生成日時: 2026-11-03T08:10:00
- feedback request: 20261103_housekeeping_followups(direct / causal work unit: CR-f3b8a1d0-001#1。packet: docs/pipeline/feedback-runs/20261103_housekeeping_followups/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20261103_housekeeping_followups"
  input_sha256: "7a81f28ce6fef4c2f70e2839d657a3f8e8480671bd846b460edab3d22b3ba775"
  request_ids: ["CR-f3b8a1d0-001"]
  work_unit_ids: ["CR-f3b8a1d0-001#1"]
```

マージ規則の補足:

- 条件.tsv はコンテキスト(1列目)+名前(2列目)のキーで該当行をイベント側の内容に置き換える。

本イベントは、管理 DB に接続しないとき(RAPID_CROSSCHECK_MODE=off でハウスキープ設定の管理 DB 接続参照名が無い・空)のハウスキープの振る舞いを、要求(USDM SPEC-014-08)に合わせて条件へ反映する(CR-f3b8a1d0-001)。仕様(CLI 契約の housekeep.sh)の振る舞いは変えない。新しい要素は追加しない。

## 追加

- なし

## 変更

- 条件: ハウスキープの削除判定 → 管理 DB に接続しないときは、確報比較依頼と管理 DB の行を削除せず起動のたびに warn を 1 行出すこと、execution-spec.json に記録された速報クロスチェックのモードが off でない実行は経過日数にかかわらず単位ごと残して warn を出すこと、off の期間に作られた成果物だけの実行は成果物だけの規則どおりに判定すること、warn は終了コードに影響しないことを説明に加える(CR-f3b8a1d0-001)

## 削除

- なし
