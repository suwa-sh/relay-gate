# 変更サマリ

- event_id: 20260818_133855_rerun_identity_new_run_id
- 元USDM: 20260818_133855_rerun_identity_new_run_id
- 生成日時: 2026-08-18T13:38:55

```yaml
feedback_request:
  feedback_request_id: "20260818_113601_impl_feedback_6078c4ed"
  input_sha256: "57396b15a51da62949a111f13ef986398ac2e22674e9f47751100f6b24960746"
  request_ids: ["CR-6078c4ed-003"]
  work_unit_ids: ["CR-6078c4ed-003#1"]
```

## 追加

- 状態: background slot実行状態 → 初期遷移「(生成) → RUNNING」を追加（遷移UC: execution-spec.jsonの実行設定を保ったまま再実行する。再実行は新しいrun_idの実行を新規作成しparent_run_idで元run_idに関連付ける。元の実行のレコードと履歴は不変）
- 状態: 速報比較依頼状態 → 初期遷移「(生成) → REQUESTED」を追加（遷移UC: execution-spec.jsonの実行設定を保ったまま再実行する。再実行は新しいrun_idの速報比較依頼を新規作成しparent_run_idで元依頼に関連付ける。元依頼のレコード・状態・履歴は不変）

## 変更

- なし

## 削除

- 状態: background slot実行状態 → 再実行を既存実行の差し戻しとして表現していた遷移行 3 行を削除（SUCCEEDED → RUNNING / FAILED → RUNNING / ABORTED → RUNNING。いずれも遷移UC: execution-spec.jsonの実行設定を保ったまま再実行する）
- 状態: 速報比較依頼状態 → 再実行を完了済み依頼の REQUESTED への差し戻しとして表現していた遷移行 3 行を削除（SUCCEEDED → REQUESTED / FAILED → REQUESTED / ABORTED → REQUESTED。いずれも遷移UC: execution-spec.jsonの実行設定を保ったまま再実行する）

削除は「コンテキスト + 状態モデル + 状態 + 遷移UC + 遷移先状態」で該当する遷移行のみを対象とする。
同じ状態キーを持つ終端説明行（SUCCEEDED / FAILED / ABORTED の遷移UCなし行）は削除しない。
