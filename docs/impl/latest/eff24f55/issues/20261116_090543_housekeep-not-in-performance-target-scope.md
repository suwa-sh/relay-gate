# 性能の目標の対象に `validate-config.sh --housekeep` が入っているかが読み取れない(検証種別は 5 つ、目標の対象は「4 検証種別すべて」)

- uc_id: eff24f55(slot ごとのジョブマップを定義する / define-slot-job-maps)
- 起票 stage: S8 feedback(2026-11-16 の再実行。オーケストレータが見つけた記載の食い違いを、現物を読んで確かめた)
- 種別: 仕様の記載漏れ(本 UC の blocker ではない。本 UC の `--job-map` は目標の対象に明記されている)
- 実装への影響: なし(`--housekeep` は未実装。`facade/` と `ops/` に housekeep の実装は無い)

## 仕様の記載

| 記載 | 場所 |
|---|---|
| 入力の規則を適用するコマンドは「validate-config.sh の 5 検証種別 --feature-flag / --job-map / --rapid-crosscheck / --final-crosscheck / --housekeep」。env 5 ファイルに housekeep.env を含む | `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml` 1330 行 `config_input_rules.scope` |
| validate-config.sh の書式に `--housekeep <path>` がある | 同 1205 行 `synopsis`、1238 行 |
| 性能の目標の対象は「validate-config.sh の 4 検証種別(--feature-flag / --job-map / --rapid-crosscheck / --final-crosscheck)すべてと、facade.sh の設定読み込み」。env 形式は「feature-flag.env / rapid-crosscheck.env / final-crosscheck.env」 | 同 1375 行 `config_input_rules.performance_target.applies_to` |
| 大きさの共通前提が及ぶのは「設定検証の 4 種別(--feature-flag / --job-map / --rapid-crosscheck / --final-crosscheck)が読む設定ファイルのすべて」。env 形式は「feature flag 設定・速報クロスチェック設定・確報クロスチェック worker の設定」 | `docs/nfr/latest/nfr-grade.yaml` B.1.1.2 の grade_description |
| 設定ファイルの検査の目標の対象は「設定検証の 4 種別(同じ 4 つ)すべてと facade の設定読み込み」 | 同 B.2.1.1 の grade_description |

## 判明した事実

- 検証種別は 5 つある。目標の対象の記載は、そのうち 4 つを並べて「すべて」と書いている。`--housekeep` と housekeep.env は、目標の対象・大きさの前提のどちらの記載にも無く、対象外とする記載も無い。
- 同じ CLI 契約の 1247 行は「env 形式の 4 検証種別」を `--feature-flag / --rapid-crosscheck / --final-crosscheck / --housekeep` の意味で使っている。「4 検証種別」が指す組が箇所によって違う。
- 経緯(イベントの日付):
  - ハウスキープ設定と `--housekeep` は 2026-11-01〜11-03 の仕様の更新で入った(`docs/specs/events/20261101_125000_feedback_mail_removal_housekeeping`、`20261103_135000_feedback_housekeeping_db_required`)
  - 目標の対象の記載は 2026-11-15 の更新で入った(`docs/specs/events/20261115_142000_feedback_impl_feedback_fd678b04_cycle3`、`docs/nfr/events/20261115_135000_feedback_impl_feedback_fd678b04_cycle3`)。もとの変更要求(`docs/impl/latest/fd678b04/feedback-requests/20261115_093126_impl_feedback_fd678b04.md` の CR-fd678b04-001)の選択肢が 4 つの検証種別だけを並べていた
  - 利用者の回答(2026-11-15、`docs/impl/latest/fd678b04/review/review-notes.md`)は「案 A: 4 種類の設定検証すべてに適用する」。示された選択肢が 4 つだけだったため、`--housekeep` を外す意図があったかは回答から読み取れない
- NFR B.1.1.2 の根拠欄は「閾値を機能ごとに考え直さない方針のため、共通の前提として 1 か所に定める」と書く。

## 提案(利用者が決める)

| 選択肢 | 内容 | 長所 | 短所 |
|---|---|---|---|
| A(推奨) | 目標の対象を「validate-config.sh の 5 検証種別すべて」とし、`--housekeep` と housekeep.env を CLI 契約の `performance_target.applies_to` と NFR B.1.1.2 / B.2.1.1 に足す | 「閾値を機能ごとに考え直さない」「すべてに適用する」という既存の決定の考え方と同じになる。ハウスキープの機能を実装するときに目標を考え直さずに済む | 記載の更新が 3 か所になる |
| B | `--housekeep` を目標の対象外と明記し、理由を書く(例: 1 日 1 回の定期ジョブで、設定は保持日数の 1 キーだけ) | 現在の 4 つの並びを変えない | 機能ごとに目標を決める例外が 1 つ増える |

- どちらの選択でも、CLI 契約の中で「4 検証種別」が指す組が箇所によって違う書き方をそろえる(例: 1247 行は「env 形式の検証種別」と書く)。
