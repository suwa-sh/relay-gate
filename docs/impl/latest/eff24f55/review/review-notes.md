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


## 2026-10-06 レビュー(Linux CI 修正後・4 回目)

- 経緯: 2026-09-23 の承認後、PR #11 の Linux CI(ubuntu-latest)で facade の単体テスト 5 件が失敗。利用者の決定「A: 同じ branch で修正」(2026-10-06)に従い attempt 6 内で修正
- 対象 evidence: S9 event `20260928_140000_s9_review_generated_eff24f55_ci_linux_fix`(変更要求 0 件、gate 6/6 pass(macOS + Ubuntu 24.04 両ロケール)、blocker 0 / major 0 / minor 30、assumption evidence efbe4937…)
- 独立検証 2 回: 1 回目 blocker 1(F-001 空白判定のロケール依存)→ 修正 → 2 回目 blocker 0
- 回答: `機能=A / 前提=一括承認`
- 決定: 機能承認 / A-058(空白 = ASCII 6 種のみ)= A / A-053(sed 失敗時は tr の終了状態を見ない)= A / 他 22 件 auto_confirmed。却下 0
- 次: delivery_ready → 修正分を squash して PR #11 へ push → CI pass 確認 → merge


## 2026-11-16 レビュー(仕様更新後の再実行・5 回目)— 回答待ち

- 経緯: 2026-10 〜 2026-11-16 の仕様更新を受けた完了済み UC の再実行(attempt 6 のまま)。S2 で 13 件追加(red 0)、S4 は性能改善のみ(behavior_changed: false)、S5 blocker 0 / major 0 / minor 27、S6 55/55、S7 3/3(+ 完了済み 12/12)、S8 draft 2 件(CR-eff24f55-008 / 009、sha 57d58b7c…)
- レビュー資料: docs/impl/latest/eff24f55/review/index.html(git 管理外の再生成物)
- 聞いている 7 問(推奨): 全体=承認 / 問 2 性能の目標と解析の決まり=案 A(CR-008)+ Linux 基準を書き添える / 問 3 ハウスキープ=案 A(CR-009)/ 問 4 前提 26 件 + V-001 = すべて承認(A-061 は仕様変更・実装修正で個別に差し戻せる選択肢あり)/ 問 5 SPEC-004-01-10 を atdd_scenarios に確定 / 問 6 heavy タグ運用 = このまま / 問 7 = 案 A(仕様反映と再確認の後、1 コミット・新規 PR・CI pass でマージ)
- 回答必須の前提: 0 件(security / persistence 分類なし)。S8 done の review_attention は A-061 / V-001 を required としていたが、S9 は dist-impl-review の規則で 0 件とし、2 件は個別に示した
- 注意: 問 5 の仮追加シナリオは「--job-map は feature-flag.env の場所キーによらず渡したパスを検証する」(SPEC-004-01-10)。オーケストレータ指示の「5,000 行超を拒否しない」ではない(event 20261116_045152 と feature 本文で確認)
- 回答: (未回答)

## 2026-11-17 〜 18 検証の高速化後: 最終確認(利用者の承認と、性能についての要求の取り下げ)

- ユーザー回答(2026-11-17、原文): 【全体】今回の実装(ジョブマップの検証の高速化。出力と終了コードは変えていない)を承認します。 / 【実装者が補った前提】26 件と、記録から漏れていた 1 件(言語設定に左右されない設定で検証する)を、すべて承認します。 / 【受け入れテスト】仮に加えた 1 件(feature flag に場所を書いていても、検証コマンドは渡したパスのジョブマップを検証する)を、この機能の受け入れテストとして確定してください。 / 【重いテストの扱い】1 件 2 秒以上か MB 級の入力のテストに印を付け、仕組みを変えたときだけ流す今の運用で、このままでよいです。 / 【本線への取り込み】案 A: 仕様への反映と再確認を済ませてから 1 コミットにまとめて取り込み依頼を作り、自動検査が通ったらマージまで進めてください。 / 重いテストを実行するのは対象ファイルを変更したときで良いですが、実行は実装作業の最後・レビュー直前にして下さい。何度も実行するものではなく、パフォーマンスの劣化が起きていないかを確認するのが目的です。
- 同じ回答のうち、性能の目標についての 3 点(対象外の入力の形を数で書く / Linux で測ると書き添える / ハウスキープ設定の検証を対象に含める)は、2026-11-18 の発言で取り下げになった
- ユーザー発言(2026-11-18、原文): 「ずっとどうでも良いエッジケースを考えすぎです。大きなデータに意味はなく、ムダな処理がないことを見たいだけです。」「推奨ですすめるというか、実装の効率が下がるなら仕様を取り下げてもよいです。重いテストも削除しても良いくらいです。」
- 決定: 実装を承認。前提 26 件と記録漏れ 1 件を承認。仮に加えた受け入れテスト 1 件を確定。性能についての仕様への要求 2 件は公開せず取り下げ、仕様は変えない(要求 0 件 = 最終承認)。性能で見るのはムダな処理がないことだけで、目標から外すために作った入力は扱わない。1 コミットにまとめて取り込み依頼を作り、自動検査が通ったらマージする
- オーケストレータの解釈: 2026-11-18 に作り直した最終確認の資料は新しい判断を求めないため、利用者へ再提示していない。重いテストは、次の機能の実装のはじめに仕分けの仕組みごと削除する予定(利用者へ報告済み。未実施)
- 記録: 20261117_200745_config_confirmed_eff24f55_atdd_scenarios_confirmed_by_user / 20261118_004308_s8_feedback_completed_eff24f55_refresh_no_requests / 20261118_005133_s9_review_generated_eff24f55_no_requests / 20261118_005134_review_approved_eff24f55_final / 20261118_005135_delivery_prepared_eff24f55_job_map_validation_speed_up
