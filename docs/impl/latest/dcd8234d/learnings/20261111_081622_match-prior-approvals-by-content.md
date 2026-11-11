# 再実行で前提の番号が振り直され、承認済みの前提が新規に見える

## 何が起きたか

- 仕様の還流のあとで同じ UC を再実行すると、実装者が補った前提が A-001 から振り直される
- 今回の A-002(「実行可能」は通常ファイルかつ実行権限)は、2026-10-27 に利用者が承認した A-006 と同じ内容だった
- 番号だけで照合すると「今回新しく出た仕様の不足」に見え、承認済みの事項を要求に格上げしかけた

## 原因

- AssumptionRecord の id は attempt ごとの連番で、サイクルをまたぐ安定した識別子ではない
- 承認記録(review_approved event の assumption_decisions)は、その時点の id で保存される
- 前サイクルの前提ファイルは invalidated/ の下へ移るため、現在の stages/ だけを見ると過去の判断が見えない

## 回避方法

- S8 で前提を分類する前に、invalidated/ の各サイクルの `S4_tier-impl.*.assumptions.yaml` を、前提の文言(target・判定の中身)で突き合わせる
- 一致した前提は `docs/impl/events/*review_approved_{uc_id}*/event.yaml` の assumption_decisions で、当時の判断(approved / confirmed / rejected と種別)を確かめる
- as-built summary の前提の表に「承認済み(当時の id、同じ内容)」と書き、要求にしない

## 次回の対応

- 再実行サイクルの S8 では、前提ごとに「今回新規 / 過去に承認済み / 過去に却下済み」の 3 区分を必ず付ける
- 過去に承認済みの前提は、S9 のレビュー資料でも「引き継ぎの確認だけ」と分け、利用者に同じ判断を求め直さない
