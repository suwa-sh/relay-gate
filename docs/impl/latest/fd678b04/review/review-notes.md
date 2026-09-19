# review-notes: fd678b04 feature flag を設定する

S9 承認対話の記録(オーケストレータが追記。S8 refresh の入力)。

## 2026-09-17 承認対話(S9 evidence: events/20260917_020150_s9_review_generated_fd678b04)

レビュー資料: docs/impl/latest/fd678b04/review/index.html(パイプライン生成)と tmp/reviews/fd678b04-s9-decision.html(判断ページ。git 管理外)。

### ユーザー回答(原文)

```text
機能=A / 相互運用=A / 監査=A
前提=A-005:承認 / A-006:承認 / A-007:承認 / A-008:承認 / A-010:承認 / A-012:承認 / A-013:承認 / A-015:承認 / A-016:承認 / A-017:承認 / A-018:承認 / A-019:承認 / A-020:承認 / A-021:承認 / A-022:承認 / A-023:承認 / V-001:承認 / V-002:承認
```

### 決定事項

| 問い | 選択 | 意味 | draft への反映 |
|---|---|---|---|
| 機能 | A | 現在の実装を承認する(差し戻しなし) | なし |
| 相互運用 | A | runner `--help` 問い合わせは「1 slot あたり待機上限 4 秒・blue / green を逐次」を希望値として変更要求に添える(現行実装を維持。両 slot 未応答でも約 9.1 秒で NFR B.2.1.1 の 10 秒以内) | CR-fd678b04-002 に希望値(4 秒・逐次・上限到達時は TERM → KILL で停止)を明記する |
| 監査 | A | 運用モード切替 Scenario の Then を検証側(validate-config の operation_mode 変化)に書き換え、実行側は UC「slot 実行モードを選択して runner を起動する」の既存 Scenario で覆う | CR-fd678b04-001 は現行 draft のとおり(変更なし) |
| 前提 | 全 18 件 承認 | 実装者が補った判断(A-005〜A-023 の 16 件)と検証者が検出した未記録の判断(V-001 / V-002)をすべて承認 | 却下(仕様変更)なし → spec-gap の要求追加なし |

### V-002 についての補足

V-002(問い合わせ用の一時ファイルを作成できない場合も runner 未応答と同じ warn と版 `-` で継続する)はユーザーが承認した。
attempt-2 の独立検証が major(F-001)として指摘した「検証側障害と runner 未応答を区別できない」は、
CR-fd678b04-002 の「問い合わせの準備に失敗した場合は runner 未応答と区別し終了コード 6 で報告する」要求に含まれており、
仕様側で確定してから再実装で反映する(この attempt では実装を変更しない)。

### 次のアクション

- S8 `mode=refresh`: CR-fd678b04-002 に「相互運用=A」の希望値を追記する。要求件数は 2 件のまま
- S9 再生成 → 新しい evidence に対して `review_approved`(assumption_decisions: 18 件すべて confirmed)を記録
- S8 `mode=publish` → `blocked_on_spec`


## 2026-09-17 承認対話(2 サイクル目。S9 evidence: events/20260917_083021_s9_review_generated_fd678b04_cycle2)

レビュー資料: docs/impl/latest/fd678b04/review/index.html(パイプライン生成)と tmp/reviews/fd678b04-s9-decision-2.html(判断ページ。git 管理外)。

### ユーザー回答(原文)

```text
実装=承認 / 禁止キー範囲=A / 前提=A-010:承認 / A-024:承認 / A-025:承認 / A-026:承認 / A-027:承認
```

### 決定事項

| 問い | 選択 | 意味 | draft への反映 |
|---|---|---|---|
| 実装 | 承認 | 仕様反映後の実装(runner --help 問い合わせの契約準拠、切替 Scenario 分離)を承認する(差し戻しなし) | なし |
| 禁止キー範囲 | A | 確報の制御キーは `FINAL_` 接頭辞で拒否する(現行実装。確報クロスチェック設定の誤配置も拒否できる) | CR-fd678b04-001 の希望値は draft のとおり `FINAL_` 接頭辞(変更なし) |
| 前提 | 回答必須 A-010 と新規 A-024〜A-027 を承認。前回承認済み・内容不変の 12 件(A-005/006/007/008/015/016/017/018/019/020/021/023)は未回答のため auto_confirmed | 却下(仕様変更)なし → spec-gap の要求追加なし |

相互運用(runner 問い合わせ 4 秒・逐次)と監査(Scenario 分離)は前サイクルで確定し仕様反映済みのため、今回は選び直していない。

### 次のアクション

- draft は変更なし(要求 1 件、希望値 A)→ この S9 evidence へ `review_approved`(assumption_decisions 17 件: confirmed 5 / auto_confirmed 12)を記録
- S8 `mode=publish` → `blocked_on_spec` → NEXT.md を上書きして commit → lease 解放


## 2026-09-18 承認対話(3 サイクル目・最終。S9 evidence: events/20260917_113000_s9_review_generated_fd678b04_cycle3)

レビュー資料: docs/impl/latest/fd678b04/review/index.html(パイプライン生成)と tmp/reviews/fd678b04-s9-decision-3.html(判断ページ。git 管理外)。

### ユーザー回答(原文)

```text
機能=A / 禁止キー=A / 相互運用=A / 監査=A
前提=A-010:承認
A-015:承認
A-007:承認
```

### 決定事項

| 問い | 選択 | 意味 | 反映 |
|---|---|---|---|
| 実装 | A(承認) | 仕様反映後の実装(FINAL_ 接頭辞の拒否範囲、境界 Scenario、前提 A-007 の文面修正)を承認し PR 作成へ進む | delivery_prepared → completed |
| 禁止キー / 相互運用 / 監査 | A / A / A | 前 2 サイクルで確定し仕様反映済み。今回は選び直しなし(回答形式の都合で再掲) | なし |
| 前提 | 回答必須 A-010・A-015 と文面変更 A-007 を承認。残り 13 件(A-005/006/008/016/017/018/019/020/021/024/025/026/027)は未回答のため auto_confirmed | 却下 0 件 → 仕様変更要求なし | review_approved の assumption_decisions 16 件 |

### 次のアクション

- 要求 0 件のため S8 publish なし。`review_approved`(delivery approval)→ `delivery_prepared` → state completed → NEXT.md(還流不要)を同一 commit → lease 解放 → squash(`feat: feature flag を設定する`)→ push → PR 作成
