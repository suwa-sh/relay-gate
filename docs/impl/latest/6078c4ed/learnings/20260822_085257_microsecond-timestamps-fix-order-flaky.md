# 履歴テーブルの時刻は契約型が許す最大精度で記録し、テストは順序に依存しない

## 何が起きたか

`runner_result_events.occurred_at` を秒精度(`date -u +%Y-%m-%dT%H:%M:%SZ`)で記録していたため、同一秒内の 2 イベントの順序が SQL の ORDER BY で定まらず、履歴順序を検証する TDD が 2 回に 1 回失敗した(attempt 5 F-002。first_exit=1、second_exit=0)。

## 原因

契約は occurred_at を「履歴の時系列順序の基準」と定めるが精度を定義していない。bash の `date` は秒精度しか返さず、テストは同秒のときに event_name 昇順へ落ちる並びを前提にしていなかった。

## 回避方法

- 時刻生成を 1 箇所(`clock_now_utc`)に集約し、perl `Time::HiRes` でマイクロ秒精度の UTC ISO 8601 を返す。同一 transaction 内の accepted_at / occurred_at / updated_at は同じ値を使う
- テストは時系列順序を前提にせず、イベントの内容(event_name・status の集合)で検証する。順序を検証する必要があるときは明示的な sequence を持たせる
- 精度の正本化は契約側へ差し戻す(CR-015)

## 次回の対応

- 履歴テーブルを持つ UC では、実装前に契約の時刻精度と順序基準を確認し、未定義なら仕様へ問い合わせる
- TDD gate は 3 回連続実行で安定性を確認する
