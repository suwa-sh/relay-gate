# 次の作業: 変更要求の還流(dist-pipeline)→ 実装フェーズ再開

## 現在の状態

- state: `blocked_on_spec`(distillery 反映待ち)
- feedback ID: `20260822_085257_impl_feedback_6078c4ed`(supersedes なし。前回 2 件の還流は反映済み)
- 要求件数: 8 件 / blocker 2 件(CR-6078c4ed-011〜018。severity: blocker 2・spec-gap 6・improvement 0)
- published event: `20260822_143300_feedback_request_published`
- 承認: `20260822_143100_feedback_publication_approved`(S9 evidence `20260822_143000_s9_review_regenerated`)。
  この承認は feedback 公開許可であり PR 許可ではない
- 実装の到達点(attempt 6、還流後仕様 spec `20260819_114307` に追随):
  - tier-facade: 4 ゲート pass(bats 51/51 ×3、実 PostgreSQL テスト 5 件含む / tier BDD 3/3)
  - 独立検証(Codex gpt-5.6-sol): blocker 0 / major 0 / minor 0
  - UC BDD 9/9(後続 UC 責務の 1 Scenario はハーネス注入)/ ATDD 6/6
- resolved_models: implementer `claude-fable-5` / verifier `gpt-5.6-sol`(codex exec。サンドボックス有効だと
  PostgreSQL 実体テストが socket/shm 制限で開始不能 → `--dangerously-bypass-approvals-and-sandbox` で実行)
- PR: 未作成。還流 → 再実装 → 最終レビューが終わるまで作成しない

## 次に実行するコマンド(新セッションまたは `/clear` 後に 1 回)

```text
/distillery:dist-pipeline docs/impl/latest/6078c4ed/feedback-requests/20260822_085257_impl_feedback_6078c4ed.md
```

- `--recommended-auto` の判断材料: 8 件すべて採用案が確定済み(ユーザー回答
  `実装=A / CR-012=A / CR-011=A / CR-014=A / CR-015=A / CR-013=A / CR-016=A / CR-017=A / CR-018=C-1`)。
  CR-018(slot 別ジョブマップ)は rdb-schema 変更(`job_map_version` を slot_execution_specs へ移動)と
  CLI 契約変更(`RELAYGATE_JOB_MAP_PATH_BLUE` / `_GREEN` 相当)を伴う。CR-011 / CR-012 が blocker。
  安全な推奨 routing を自動採用してよい場合のみ付ける

## pipeline 完了後の再開コマンド

```text
/distillery-impl:dist-impl-run 6078c4ed
```

- distillery 側の仕様更新で input hash が変わった done だけが projection 照合で再実行される(tier-scoped staleness)。
  今回の変更は spec.md / tier-facade.md / rdb-schema / cli-command-contract に及ぶため、S1〜S9 の再実行が見込まれる
- bootstrap(S0)も rdb-schema・spec_event・arch の変化で P2/P4/P7 が再実行される(contracts scope は全テーブル規則を継続)
- 再開時の注意:
  - verifier を Codex で起動する場合はサンドボックスを外す(上記)
  - `.github/workflows/ci.yml` の tdd ジョブに PostgreSQL(initdb / pg_ctl / psql)の PATH 配線が必要
    (issue 20260821T220045Z §1。bootstrap P6 の write-set。未対応だと CI の tdd が PG テストで fail)
  - ローカル `main` が `origin/main`(= base_head a4c2bc2)より 21 commit 先行している(旧 run の UC commit 列を指す)。
    PR 作成前に `git branch -f main origin/main` 相当で整理する(ユーザー確認のうえ)
  - bootstrap の再実行 commit(`impl(bootstrap): ...`)が feature branch に混在している。最終 squash で UC commit に含まれる

## 参照

- 公開 Markdown: `docs/impl/latest/6078c4ed/feedback-requests/20260822_085257_impl_feedback_6078c4ed.md`
- レビュー資料(gitignore): `docs/impl/latest/6078c4ed/review/index.html`
- レビュー回答: `docs/impl/latest/6078c4ed/review/review-notes.md`
- 実装事実: `docs/impl/latest/6078c4ed/feedback/as-built-summary.md`
- 仕様疑義の経緯: `docs/impl/latest/6078c4ed/issues/20260821T220045Z_select-slot-spec-reflow-test-boundary.md`
- 学び: `docs/impl/latest/6078c4ed/learnings/20260822_085257_*.md`
