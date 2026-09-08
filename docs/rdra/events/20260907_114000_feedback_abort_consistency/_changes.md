# 変更サマリ

- event_id: 20260907_114000_feedback_abort_consistency
- 元USDM: docs/usdm/events/20260907_114000_feedback_abort_consistency/requirements.yaml
- 生成日時: 2026-09-07T11:40:00
- feedback request: 20260907_abort_consistency(direct / causal work unit: CR-c770d8f0-016#1, CR-c770d8f0-017#1, CR-c770d8f0-018#1。packet: docs/pipeline/feedback-runs/20260907_abort_consistency/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_abort_consistency"
  input_sha256: "70cda63f92e887e459a3817580e45a840e3ff201065a534085ad113fb8910b81"
  request_ids: ["CR-c770d8f0-016","CR-c770d8f0-017","CR-c770d8f0-018"]
  work_unit_ids: ["CR-c770d8f0-016#1","CR-c770d8f0-017#1","CR-c770d8f0-018#1"]
```

マージ規則の補足: BUC.tsv は BUC + UC のグループ単位、状態.tsv はコンテキスト + 状態モデル + 状態のグループ単位で、イベント側の行集合が latest の同グループを置き換える(グループ内の行の追加を含む)。状態.tsv の追加行 CLAIMED → ABORTED は CLAIMED グループの末尾に配置する。

## 追加

- 状態: クロスチェック依頼 CLAIMED → ABORTED（遷移UC: 実行を ABORTED へ遷移させる。abort-rapid-crosscheck による claim 済み速報比較依頼の中止。速報比較依頼のみ）(CR-c770d8f0-017)

## 変更

- 条件: 中止済み run の比較依頼作成除外 → 判定キーを「並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(aborted.txt 公開済み)」に拡張し、判定材料(parallel_run.status と slot_executions.status)を明記、状態モデルに slot 実行を追加(CR-c770d8f0-016)
- 条件: 両系成功判定 → 除外対象を「中止済み run の比較依頼作成除外」に該当する run(並行稼働実行 ABORTED または slot 実行 ABORTED)に改める(CR-c770d8f0-016)
- 条件: 依頼中止可否判定 → 速報比較依頼は REQUESTED / CLAIMED / RUNNING のいずれかで中止可能、確報比較依頼は RUNNING のみとし、CLAIMED 中止時の競合規則(停止確認 yes + status IN 条件付き UPDATE、worker は RUNNING への更新 0 件なら比較を開始しない)を明記、バリエーションに停止確認応答を追加(CR-c770d8f0-017)
- 条件: slot 中止可否判定 → REQUESTED 依頼の中止を競合窓の保険として位置づけ直し「中止済み run の比較依頼作成除外」との併用を明記(CR-c770d8f0-018)。abort-rapid-crosscheck が REQUESTED / CLAIMED / RUNNING を中止できることを追記(CR-c770d8f0-017)
- 状態: クロスチェック依頼 REQUESTED → ABORTED → 説明を「両系の完了通知で依頼が作成された後に abort-blue / abort-green で slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」に改める(CR-c770d8f0-018)。遷移経路に abort-rapid-crosscheck を追加(CR-c770d8f0-017)
- 状態: クロスチェック依頼 CLAIMED → RUNNING(比較ツールでジョブ単位比較を実行して結果を登録する) → 条件付き UPDATE で遷移し、更新件数 0 件なら比較を開始しないことを追記(CR-c770d8f0-017)
- 状態: クロスチェック依頼 RUNNING → ABORTED → abort-rapid-crosscheck が REQUESTED / CLAIMED も中止できること、abort-final-crosscheck は RUNNING のみであることを追記(CR-c770d8f0-017)
- 状態: クロスチェック依頼 ABORTED(終端) → REQUESTED / CLAIMED の速報比較依頼が abort-rapid-crosscheck で中止された経路を説明に追記(CR-c770d8f0-017)
- 情報: 速報実行(rapid_run) → 依頼を作成しない中止済み run の判定に slot 実行 ABORTED を加え、関連情報に slot 実行を追加(CR-c770d8f0-016)
- 情報: 速報比較依頼(rapid_crosscheck_request) → abort-rapid-crosscheck が REQUESTED / CLAIMED / RUNNING を中止できること、CLAIMED 中止後は worker が比較を開始しないことを追記(CR-c770d8f0-017)
- 情報: 中止指示 → 速報比較依頼は REQUESTED / CLAIMED / RUNNING、確報比較依頼は RUNNING のみを中止対象とすることを明記(CR-c770d8f0-017)
- バリエーション: 中止対象種別 → 速報比較依頼は REQUESTED / CLAIMED / RUNNING、それ以外は RUNNING のみ中止できることを追記(CR-c770d8f0-017)
- BUC: 速報クロスチェックフロー → UC「両系成功時に速報比較依頼を作成する」の中止済み run 判定に slot 実行 ABORTED を加え、入力情報に「slot 実行」を追加(CR-c770d8f0-016)
- BUC: 速報クロスチェックフロー → UC「比較ツールでジョブ単位比較を実行して結果を登録する」に条件「依頼中止可否判定」を関連付け、RUNNING への条件付き UPDATE が 0 件なら比較を開始しないことを追記(CR-c770d8f0-017)
- BUC: 実行中止フロー → UC「実行を ABORTED へ遷移させる」の説明を abort-rapid-crosscheck が REQUESTED / CLAIMED / RUNNING を中止できる内容に更新(CR-c770d8f0-017)。abort-blue / abort-green による REQUESTED 依頼の中止を競合窓の保険として位置づけ直し(CR-c770d8f0-018)

## 削除

- なし
