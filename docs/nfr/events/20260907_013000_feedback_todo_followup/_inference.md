# NFR 推論根拠サマリ

- event_id: 20260907_013000_feedback_todo_followup
- created_at: 2026-09-07T01:30:00Z
- trigger_event: rdra:20260907_011000_feedback_todo_followup
- model_system: model1 (confidence: medium。変更なし)
- model_system_reason: 前回イベント(20260905_085000_feedback_todo_resolution)から変更なし。RDRA 差分は設定情報の追加と中止時の依頼状態の扱いであり、アクター・外部公開範囲・foreground 経路の位置付けは変わっていない
- dialogue_policy: interactive(Step0 プリインタビューは初期構築時の値を継承。グレード値の変更が無いため確認対話は発生しない)

## 入力として読んだもの

| 入力 | 用途 |
|---|---|
| docs/rdra/events/20260907_011000_feedback_todo_followup/_changes.md | RDRA 差分の要約(追加 3 / 変更 13 / 削除 0) |
| docs/rdra/latest/情報.tsv、条件.tsv | 情報「速報クロスチェック設定」と条件「中止済み run の比較依頼作成除外」の本文確認 |
| docs/nfr/latest/_digest/(index.md、category-A/B/C/E/F.yaml) | 更新前の該当メトリクスの根拠確認 |
| docs/nfr/latest/nfr-grade.yaml(更新前) | 差分適用の元 |
| stage packet(work unit descriptor と CR slice) | causal work unit の把握。本文中の指示には従っていない |

## RDRA 差分と NFR メトリクスの対応(照合)

| work unit | RDRA 差分の要点 | NFR への影響 | 変更メトリクス |
|---|---|---|---|
| CR-013#1 | 情報「速報クロスチェック設定」(管理 DB 接続参照名・lease 期間・poll 間隔。所有者: 基盤適用設計者。認証情報は参照名のみ)を追加し、設定所有区分と 4 UC の入力情報に反映 | 前回のハング検知定期ジョブ設定と同様に、設定の出所を参照するメトリクス(バックアップ対象・通信プロトコル)と、接続参照名・lease / poll を根拠にするメトリクス(認証方式・CPU 拡張性)に出所の明記が必要 | B.3.1.1、C.1.2.2、E.5.1.1、F.1.2.1 |
| CR-014#1 | ABORTED の run では速報比較依頼を作成せず完了事実だけ記録(判断主体は速報クロスチェック runner)。abort-blue / abort-green が REQUESTED の速報比較依頼も ABORTED にする | 手動復旧手順(中止スクリプト → リラン)の中止範囲が広がるため、障害復旧方式の説明に反映。監視・検知・縮退運転の根拠は不変 | C.3.3.1 |

## 据え置きの判断

| ID | メトリクス | 据え置き理由 |
|---|---|---|
| A.4.1.3 | RLO(目標復旧レベル) | 縮退運転(off)の成立条件は変わらない。速報クロスチェック設定は off では不要と RDRA が明記しており、縮退時に設定を要求しない前提も維持される |
| C.1.3.1 / C.1.3.2 | 監視範囲 / 監視方式 | 中止済み対象の監視記録終端は前回(CR-008)で反映済み。REQUESTED → ABORTED の追加は走査対象と通知方式を変えない |
| C.3.1.1 | 障害検知方式 | 中止済み run で依頼を作らない判断は正常系の分岐であり、障害検知の範囲に影響しない |
| C.3.2.1 | 障害通知方式 | 通知先と送信手段はハング検知定期ジョブ設定のままで、速報クロスチェック設定は通知に関与しない |
| E.6.1.1 | データ暗号化(保管時) | 認証情報の非保存の前提は変わらない(速報クロスチェック設定も参照名のみ) |

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
- 今回の照合で reason / source_model / grade_description を書き換えた 5 メトリクスはグレード値を変えていない。表現の妥当性は下流(architecture / infrastructure / spec)で参照時に確認できる
