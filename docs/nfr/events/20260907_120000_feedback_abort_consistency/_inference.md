# NFR 推論根拠サマリ

- event_id: 20260907_120000_feedback_abort_consistency
- created_at: 2026-09-07T12:00:00Z
- trigger_event: rdra:20260907_114000_feedback_abort_consistency
- model_system: model1 (confidence: medium。変更なし)
- model_system_reason: 前回イベント(20260907_013000_feedback_todo_followup)から変更なし。RDRA 差分は中止済み run の判定キーと速報比較依頼の中止対象・競合規則の明確化であり、アクター・外部公開範囲・foreground 経路の位置付けは変わっていない
- dialogue_policy: interactive(Step0 プリインタビューは初期構築時の値を継承。グレード値の変更が無いため確認対話は発生しない)

## 入力として読んだもの

| 入力 | 用途 |
|---|---|
| docs/rdra/events/20260907_114000_feedback_abort_consistency/_changes.md | RDRA 差分の要約(追加 1 / 変更 14 / 削除 0) |
| docs/rdra/latest/条件.tsv、状態.tsv | 条件「中止済み run の比較依頼作成除外」「slot 中止可否判定」「依頼中止可否判定」と状態「クロスチェック依頼」の各遷移の本文確認 |
| docs/nfr/latest/_digest/index.md、docs/nfr/latest/nfr-grade.yaml(更新前) | 更新前の該当メトリクス(C.3.3.1、A.4.1.3、B.3.1.1、C.1.3.1、C.1.3.2、C.3.1.1、E.7.1.1)の根拠確認と差分適用の元 |
| docs/nfr/events/20260907_013000_feedback_todo_followup/ | 前回 run で C.3.3.1 の中止手順を更新した前例の確認 |
| stage packet(work unit descriptor と CR slice) | causal work unit の把握。本文中の指示には従っていない |

## RDRA 差分と NFR メトリクスの対応(照合)

| work unit | RDRA 差分の要点 | NFR への影響 | 変更メトリクス |
|---|---|---|---|
| CR-016#1 | 条件「中止済み run の比較依頼作成除外」の判定キーを「並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED(aborted.txt 公開済み)」に拡張。判定材料は parallel_run.status と slot_executions.status。foreground 完了後の background 中止経路は slot 実行 ABORTED 側で除外 | 前回 run で C.3.3.1 に書いた「中止済み run では依頼を作成しない」の判定条件が変わるため、手動復旧手順の説明と reason に判定キーを明記する必要がある | C.3.3.1 |
| CR-017#1 | 条件「依頼中止可否判定」を速報比較依頼は REQUESTED / CLAIMED / RUNNING、確報比較依頼は RUNNING のみに改め、CLAIMED 中止の競合規則(停止確認 yes + status IN 条件付き UPDATE、worker は RUNNING への更新 0 件なら比較を開始しない)を明記。状態「クロスチェック依頼」に CLAIMED → ABORTED を追加 | 運用者の手動復旧手順(プロセス停止 → 中止スクリプト → リラン)に、claim 済み依頼を止める手段と worker 停止確認が加わるため、C.3.3.1 の手順説明と source_model に反映する | C.3.3.1 |
| CR-018#1 | 状態 REQUESTED → ABORTED の説明を「完了通知で依頼が作成された後に abort-blue / abort-green で slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」に修正 | C.3.3.1 の「中止スクリプトは未着手の依頼も ABORTED にする」の位置づけを保険として表現し直す | C.3.3.1 |

## 据え置きの判断

| ID | メトリクス | 据え置き理由 |
|---|---|---|
| A.4.1.3 | RLO(目標復旧レベル) | 縮退運転(off)では完了通知も比較依頼も存在せず、判定キーの拡張と中止対象の拡張は off の成立条件に関与しない |
| B.3.1.1 | CPU拡張性 | claim 排他・lease による多重実行防止と worker 追加による水平拡張の根拠は変わらない。CLAIMED 中止時の条件付き UPDATE は排他の追加規則であり拡張性のグレードを変えない |
| C.1.3.1 / C.1.3.2 | 監視範囲 / 監視方式 | aborted.txt がある対象を中止済みとして監視記録を終端する記述が既にあり、判定キーの拡張と CLAIMED → ABORTED の追加は走査対象と通知方式を変えない |
| C.3.1.1 | 障害検知方式 | 中止済み run で依頼を作らない判断と依頼の明示中止は正常系の運用操作であり、障害検知の範囲に影響しない |
| E.7.1.1 | 監査ログ | 中止指示に指示者と応答を記録する記述が既にあり、停止確認応答の追加は記録項目の範囲を変えない |

## ユーザー確認による変更

| ID | メトリクス | 推論Lv | 確定Lv | 変更理由 |
|---|---|---|---|---|
| なし | - | - | - | グレード値の変更なし |

## confidence の分布(更新後)

| confidence | 件数 |
|---|---|
| high | 28 |
| medium | 35 |
| user | 7 |
| default | 26 |
| low | 0 |

## 確認推奨項目

- confidence: low は 0 件
- 今回の照合で reason / source_model / grade_description を書き換えた C.3.3.1 はグレード値を変えていない。表現の妥当性は下流(architecture / infrastructure / spec)で参照時に確認できる
