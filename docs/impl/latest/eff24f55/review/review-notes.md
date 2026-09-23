# review-notes: eff24f55 slot ごとのジョブマップを定義する

S9 承認対話の記録(オーケストレータが追記。S8 refresh の入力)。

## 2026-09-19 承認対話(S9 evidence: events/20260919_214500_s9_review_generated_eff24f55)

レビュー資料: docs/impl/latest/eff24f55/review/index.html(パイプライン生成。git 管理外)。

### 事前に確定済みの判断(同セッション内。再質問しない)

- attempt 上限到達時(tmp/reviews/define-slot-job-maps-attempt-limit-review.html): 進め方=A(もう 1 回だけ直し、同種の新しい穴が出たら仕様の確認待ちへ)/ 壊れた入力=拒否(既存のエラー文言で拒否し、表示は安全な表記へ置換。文言の妥当性は変更要求に含める)

### ユーザー回答(原文)

```text
機能: mvの問題をfixして、直ったかの観点だけレビュー。以降は予定通りに
他は推奨でOKです
```

### 決定事項

| 問い | 選択 | 意味 | 反映 |
|---|---|---|---|
| 機能 | B 相当(取り決めの例外) | 検証中のファイル差し替え(attempt 4 の F-001)を今直す。再検証は「その指摘が直ったか」の観点だけに絞り、新しい堅牢性の穴探しはしない | attempt 5 で S4 を再実行。S5 は F-001 の解消確認とゲート再実行に限定。以降(統合テスト → feedback refresh → レビュー再生成 → 公開 → 仕様の反映待ち)は予定どおり |
| 相互運用 | A(推奨) | 変更要求をこのまま公開する | refresh では F-001 の解消に伴う記述の更新だけ行う |
| 監査 | A(推奨) | 回答任意の前提 33 件をグループ単位の規則で一括承認する | approval の assumption_decisions に confirmed / auto_confirmed として記録 |
| 前提 A-012 | 承認(推奨) | credential_ref の形式不一致は警告のみで受理する | 却下(仕様変更)なし → 要求の追加なし |

### 「以降は予定通りに」の解釈

- 修正後のレビュー再生成で、追加の意味変更が無くこの回答と一致する場合は、再質問せずに新しい evidence へ承認を記録して公開へ進む
- 新しい選択肢・詳細決定が増えた場合だけ再質問する
- 変更要求の blocker(守備範囲の確定)は、F-001 が直っても仕様の不足として残るため公開対象に含める

### 次のアクション

- review_rejected(差し戻し先 S4、implementation_change)→ S6〜S9 の done を退避 → attempt 5
- S4(F-001 の修正)→ S5(解消確認のみ)→ S6 / S7 再実行 → S8 refresh → S9 再生成 → approval → S8 publish → blocked_on_spec

## 2026-09-19 承認対話(2 回目。S9 evidence: events/20260919_231500_s9_review_regenerated_eff24f55)

修正後のレビュー資料で、新たに回答必須となった前提(一時コピーの扱い)1 件だけを質問した。

### ユーザー回答(原文)

```text
承認します
```

提示したテンプレート: `機能=A / 相互運用=A / 監査=A / 前提=A-012:承認 / A-047:承認`

### 決定事項

| 問い | 選択 | 意味 |
|---|---|---|
| 機能 | A | 修正済みの実装を承認し、仕様の確認待ちへ進む(PR には進まない) |
| 相互運用 | A | 変更要求 5 件をこのまま公開する |
| 監査 | A | 回答任意の前提 36 件をグループ規則で一括承認する |
| 前提 A-012 | 承認 | credential_ref の形式不一致は警告のみで受理する |
| 前提 A-047 | 承認 | 一時コピーは TMPDIR(未設定なら /tmp)に mktemp で作り(0600)、成功・失敗とも削除し、出力には利用者が指定したパスを表示する |

- 却下(仕様変更)は無い → 要求の追加なし。draft は変更しない
- 承認 event: events/20260919_233000_review_approved_eff24f55
- 次: S8 publish → blocked_on_spec


## 2026-09-22 レビュー(仕様還流後・2 回目)

- 対象 evidence: S9 event `20260922_133000_s9_review_generated_eff24f55_cycle2`(draft `20260922_130000_impl_feedback_eff24f55` sha 8adc8bc9…、gate 6/6 pass、blocker 0 / major 2、assumption evidence 2201c357…)
- 回答: `機能=A / 変更要求の公開=A / CR-007=A / 前提=一括承認`
- 決定:
  - 機能: 承認(attempt 6。4 ゲート + UC BDD 35 + ATDD 2 pass、独立検証 blocker 0)
  - 変更要求 2 件(CR-eff24f55-006 重複 job_id の lines 表記の矛盾 / CR-eff24f55-007 credential_ref の警告境界)を公開する(この承認は公開許可であり PR 許可ではない)
  - CR-007 = 案 A(形に合わない credential_ref は現行どおり warn で受理。error にしない)。還流時にこの選択を仕様へ反映する
  - 前提 24 件: 一括承認。回答必須の A-012(credential_ref の warn)は CR-007=A と整合するため承認。却下 0
- 次: S8 publish → blocked_on_spec → `/distillery:dist-pipeline docs/impl/latest/eff24f55/feedback-requests/20260922_130000_impl_feedback_eff24f55.md`(CR-007 は案 A を採用)


## 2026-09-23 レビュー(仕様還流 cycle 2 後・3 回目)

- 対象 evidence: S9 event `20260923_132000_s9_review_generated_eff24f55_cycle3`(変更要求 0 件、gate 6/6 pass、blocker 0 / major 0、assumption evidence 36a40a0e…)
- 回答: `推奨で進めて下さい`(= `機能=A / 前提=一括承認`、A-016=A)
- 決定:
  - 機能: 承認(attempt 6。処理コードの挙動変更なし。仕様確定 2 点に合わせた BDD step 実装と前提 A-012 の削除のみ)
  - 前提 A-016: 案 A(前提として承認。推奨値 60 との差の専用 info 行は設けず、--verbose の resolved 行でのみ示す)
  - 他の前提 22 件: 回答任意のため auto_confirmed。却下 0
- 次: delivery_ready → squash → push → PR
