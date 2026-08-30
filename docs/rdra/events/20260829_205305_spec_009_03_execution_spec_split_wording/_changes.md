# 変更サマリ

- event_id: 20260829_205305_spec_009_03_execution_spec_split_wording
- 元USDM: 20260829_205305_spec_009_03_execution_spec_split_wording
- 生成日時: 2026-08-29T20:53:05

```yaml
feedback_request:
  feedback_request_id: "20260822_085257_impl_feedback_6078c4ed"
  input_sha256: "8129956bff632d9c271356ef56e3256319c7613b030adfd5477fe9f60d748bf5"
  request_ids: ["CR-6078c4ed-016"]
  work_unit_ids: ["CR-6078c4ed-016#1"]
```

## 追加

- なし

## 変更

- 情報: execution-spec.json → 説明を「execution specはファイルではなくRDBへ保存し、run共通の実行設定（execution_specs）とslot別実行設定（slot_execution_specs）に分離して保持する。hang_detect_limit_minutesはrun共通の1値として保存し、background roleに選ばれたslotのジョブマップの値を採用する（role別・slot別の値は保存しない）」に変更（属性・関連情報は変更なし。「roleごとのhang_detect_limit_minutes」の記述を除去）
- 条件: hang_detect_limit_minutes → 条件の説明を「background roleごとに設定する」から「run共通の1値。background roleに選ばれたslotのジョブマップで解決され、run共通の実行設定（execution_specs）にRDBで保存される。role別・slot別の値は持たない」に変更（バリエーション・状態モデルは変更なし）

## 削除

- なし

情報.tsv のマージは「情報」列（execution-spec.json）で行を特定し、説明列のみを差し替える。
条件.tsv のマージは「コンテキスト + 条件」（異常監視管理 + hang_detect_limit_minutes）で行を特定し、条件の説明のみを差し替える。
情報エンティティ名「execution-spec.json」は他の情報・状態・BUC から参照される論理名として維持し、改名しない。
