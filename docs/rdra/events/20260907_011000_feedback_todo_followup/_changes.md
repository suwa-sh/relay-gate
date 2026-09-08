# 変更サマリ

- event_id: 20260907_011000_feedback_todo_followup
- 元USDM: docs/usdm/events/20260907_011000_feedback_todo_followup/requirements.yaml
- 生成日時: 2026-09-07T01:10:00
- feedback request: 20260907_todo_followup(direct / causal work unit: CR-c770d8f0-013#1, CR-c770d8f0-014#1。packet: docs/pipeline/feedback-runs/20260907_todo_followup/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_todo_followup"
  input_sha256: "193823ac1e6f02400269d6bdca461150a1fc8951393f332ef28580e045261389"
  request_ids: ["CR-c770d8f0-013","CR-c770d8f0-014"]
  work_unit_ids: ["CR-c770d8f0-013#1","CR-c770d8f0-014#1"]
```

マージ規則の補足: BUC.tsv は BUC + UC のグループ単位、状態.tsv はコンテキスト + 状態モデル + 状態のグループ単位で、イベント側の行集合が latest の同グループを置き換える(グループ内の行の追加・削除を含む)。情報.tsv の追加行はハング検知定期ジョブ設定の直後、条件.tsv の追加行は両系成功判定の直後に配置する。

## 追加

- 情報: 速報クロスチェック設定（属性: 管理 DB 接続参照名, lease 期間(秒), worker の poll 間隔(秒)。関連: 速報比較依頼, 並行稼働実行, 完了通知, ハング検知定期ジョブ設定。所有者: 基盤適用設計者。認証情報は値を置かず参照名のみ）(CR-c770d8f0-013)
- 状態: クロスチェック依頼 REQUESTED → ABORTED（遷移UC: 実行を ABORTED へ遷移させる。abort-blue / abort-green による未着手の速報比較依頼の中止。速報比較依頼のみ）(CR-c770d8f0-014)
- 条件: 中止済み run の比較依頼作成除外（並行稼働実行が ABORTED の run では完了通知を受けても速報比較依頼を作成せず、完了事実だけを記録して実行ログに警告を残す。判断主体は速報クロスチェック runner）(CR-c770d8f0-014)

## 変更

- 情報: 速報実行(rapid_run) → ABORTED の run では完了事実だけを記録して速報比較依頼を作成しない旨を追記し、関連情報に実行ログを追加(CR-c770d8f0-014)
- 情報: 速報比較依頼(rapid_crosscheck_request) → REQUESTED の未着手依頼が abort-blue / abort-green でも ABORTED になることを追記(CR-c770d8f0-014)
- 情報: 中止指示 → abort-blue / abort-green が対象 run の REQUESTED の速報比較依頼も ABORTED にすることを追記(CR-c770d8f0-014)
- 情報: 完了通知 → slot runner が自 slot の中止状態を判断せず通常どおり送ることを追記(CR-c770d8f0-014)。関連情報に 速報クロスチェック設定 を追加(CR-c770d8f0-013)
- 状態: クロスチェック依頼 ABORTED(終端) → 未着手依頼が abort-blue / abort-green で中止された経路を説明に追記(CR-c770d8f0-014)
- 条件: 両系成功判定 → ABORTED の run は「中止済み run の比較依頼作成除外」で除外されることを追記(CR-c770d8f0-014)
- 条件: 完了通知の系統独立 → slot runner が自 slot の中止状態も判断しないことを追記(CR-c770d8f0-014)
- 条件: slot 中止可否判定 → abort-blue / abort-green が REQUESTED の速報比較依頼も ABORTED にすることを追記し、状態モデルにクロスチェック依頼を追加(CR-c770d8f0-014)
- 条件: 設定所有区分 → 速報クロスチェック設定(管理 DB 接続参照名・lease 期間・poll 間隔)の所有区分を追加(CR-c770d8f0-013)
- バリエーション: 設定所有区分 → 速報クロスチェック設定(所有者: 基盤適用設計者)を追加(CR-c770d8f0-013)
- BUC: 実装切替ジョブ実行フロー / 速報クロスチェックフロー → UC「slot 実行モードを選択して runner を起動する」「速報クロスチェック runner へ完了通知を送信する」「両系成功時に速報比較依頼を作成する」「速報比較依頼を claim する」の入力情報に「速報クロスチェック設定」を追加(CR-c770d8f0-013)
- BUC: 速報クロスチェックフロー → UC「両系成功時に速報比較依頼を作成する」に条件「中止済み run の比較依頼作成除外」と情報「実行ログ」を関連付け、ABORTED run の扱いを説明に追記(CR-c770d8f0-014)
- BUC: 速報クロスチェックフロー → UC「速報クロスチェック runner へ完了通知を送信する」の説明に slot runner が自 slot の中止状態を判断しないことを追記(CR-c770d8f0-014)
- BUC: 実行中止フロー → UC「実行を ABORTED へ遷移させる」の説明に未着手の速報比較依頼の ABORTED 化を追記(CR-c770d8f0-014)

## 削除

- なし
