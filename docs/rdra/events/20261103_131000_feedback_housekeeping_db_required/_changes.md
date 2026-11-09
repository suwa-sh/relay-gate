# 変更サマリ

- event_id: 20261103_131000_feedback_housekeeping_db_required
- 元USDM: docs/usdm/events/20261103_131000_feedback_housekeeping_db_required/requirements.yaml
- 生成日時: 2026-11-03T13:10:00
- feedback request: 20261103_housekeeping_db_required(direct / causal work unit: CR-9d2e6c41-001#1。packet: docs/pipeline/feedback-runs/20261103_housekeeping_db_required/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20261103_housekeeping_db_required"
  input_sha256: "94cde505fc6dda4705b1bb75134beaf9a85a7af65d7c90f1e786112e8b1031e7"
  request_ids: ["CR-9d2e6c41-001"]
  work_unit_ids: ["CR-9d2e6c41-001#1"]
```

マージ規則の補足:

- 情報.tsv は情報(2列目)のキーで該当行をイベント側の内容に置き換える。
- 条件.tsv はコンテキスト(1列目)+名前(2列目)のキーで該当行をイベント側の内容に置き換える。

本イベントは、管理 DB を使う機能が 1 つでもある設置(RAPID_CROSSCHECK_MODE が off 以外、または確報クロスチェックを使う設置)ではハウスキープ設定の管理 DB 接続参照名を必須にし、管理 DB に接続しない振る舞いを管理 DB を一切使わない設置に絞る要求(USDM SPEC-014-04 / 07 / 08)を、情報と条件の説明へ反映する(CR-9d2e6c41-001)。新しい要素は追加しない。「確報クロスチェックを使う設置」は既存のバリエーション値「確報クロスチェック worker 設定」の語で表す。

## 追加

- なし

## 変更

- 情報: ハウスキープ設定 → 管理 DB 接続参照名の属性に、RAPID_CROSSCHECK_MODE が off 以外の設置と確報クロスチェックを使う設置では必須で、省略できるのは管理 DB を一切使わない設置だけであることを加え、説明に、必須の設置で接続参照名が無い・空なら設定エラーで終わり何も削除しないこと、確報クロスチェック worker の設定があるとみなす判定方法は仕様で確定することを加える(CR-9d2e6c41-001)
- 条件: ハウスキープの削除判定 → 確報比較依頼の削除は off でも確報クロスチェックを使う設置では同じであること、接続参照名が必須の設置で無い・空なら設定エラーで何も削除しないことを加え、管理 DB に接続しないときの条件を「RAPID_CROSSCHECK_MODE=off で、確報クロスチェック worker の設定が無い設置で、接続参照名が無い・空」に絞る(CR-9d2e6c41-001)

## 削除

- なし
