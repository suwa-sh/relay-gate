# bootstrap 再実行(feedback 20260822_085257 の還流後)の完了

spec event `20260829_210828_spec_generation` への還流で spec_event / usdm / design / storybook src /
rdb-schema のハッシュが変わったため、P2 / P4 / P5 / P7 を invalidate して再実行した(P1 / P3 / P6 は done のまま skip)。

- P2: 導出結果(tiers / contracts scope / uc-map 23 UC・並び順)は既存と完全一致。content-stable 規則によりファイル未変更・`config_confirmed` なし
  - rdb-schema はテーブル増減なし(11 テーブル)。列変更は `job_map_version` の `execution_specs` → `slot_execution_specs` 移動のみ(CR-6078c4ed-018)
- P4: `packages/contracts/relay-gate-db/schema-constants.sh` を再生成(上記列移動を反映)。lock の input sha256 / generated.at を更新
- P5: `packages/ui/` を storybook-app/src(59 ファイル)から再取り込み。内容変更 3 件(ExecutionSpecCard.tsx / 起動slot選択画面 / 実行結果応答管理画面)。削除 0
- P7: `features/atdd/` を 42 SPEC / 57 Scenario で再生成。変更は SPEC-009-03 のみ(Scenario 1 の文言更新 + SPEC-009-03-2 追加)。既存 `@uc_6078c4ed` タグ 6 件を引き継ぎ(欠落 0)
- criteria 欠落 SPEC: なし / 縮退モード: なし / 矛盾検査: なし
