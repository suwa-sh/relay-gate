# 変更サマリ

- event_id: 20260907_120000_feedback_abort_consistency
- trigger_event: rdra:20260907_114000_feedback_abort_consistency
- created_at: 2026-09-07T12:00:00Z
- mode: 差分更新(nfr-grade-diff.yaml)
- dialogue_policy: interactive(グレード値の変更なし。根拠と説明の追従のみのため確認対話は不要)
- feedback request: 20260907_abort_consistency(direct work unit: なし。causal work unit: CR-c770d8f0-016#1, CR-c770d8f0-017#1, CR-c770d8f0-018#1。packet: docs/pipeline/feedback-runs/20260907_abort_consistency/stage-packets/quality_attributes.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_abort_consistency"
  input_sha256: "70cda63f92e887e459a3817580e45a840e3ff201065a534085ad113fb8910b81"
  request_ids: ["CR-c770d8f0-016","CR-c770d8f0-017","CR-c770d8f0-018"]
  work_unit_ids: ["CR-c770d8f0-016#1","CR-c770d8f0-017#1","CR-c770d8f0-018#1"]
```

マージ規則: メトリクス `id` をキーに latest/nfr-grade.yaml の該当メトリクスの `grade_description` / `reason` / `source_model` を上書きした。`grade` と `confidence` はすべて据え置き。`confidence: "user"` のメトリクスは対象に含まれない。モデルシステム(model1)は変更なし。

## 追加

- なし

## 変更

### RDRA 差分の照合(causal work unit)による追従

| ID | メトリクス | Lv(据え置き) | 起因 CR | 変更内容 |
|---|---|---|---|---|
| C.3.3.1 | 障害復旧方式 | 1 | CR-016 | 中止済み run の判定キーを「並行稼働実行が ABORTED、または対象 slot の slot 実行が ABORTED」に改め、判定材料(parallel_run.status と slot_executions.status)と foreground 完了後の background 中止経路が slot 実行 ABORTED 側で除外されることを reason に明記 |
| C.3.3.1 | 障害復旧方式 | 1 | CR-017 | 速報比較依頼の明示中止を REQUESTED / CLAIMED / RUNNING(worker 停止確認のうえ abort-rapid-crosscheck)、確報比較依頼は RUNNING のみ(abort-final-crosscheck)と手動復旧手順に追記。CLAIMED を放置すると lease 失効で再 claim される点と、条件付き UPDATE により worker が比較を開始しない競合規則を reason に追加。source_model に条件「依頼中止可否判定」と状態「クロスチェック依頼」を追加 |
| C.3.3.1 | 障害復旧方式 | 1 | CR-018 | abort-blue / abort-green による REQUESTED 依頼の中止を「完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険」と位置づけ直し、dispatcher 側の中止済み run 判定との併用が読み取れる表現に改めた |

## 削除

- なし

## 照合結果(グレード値への影響なし)

- CR-c770d8f0-016(中止済み run の判定キーに slot 実行 ABORTED を追加): 障害復旧方式(C.3.3.1)の中止済み run の説明に反映した。監視方式(C.1.3.2)は aborted.txt がある対象を中止済みとして監視記録を終端する記述が既にあり、判定キーの拡張は走査対象と通知方式を変えないため据え置き。RLO(A.4.1.3)の縮退運転(off)の成立条件も変わらない
- CR-c770d8f0-017(速報比較依頼の中止対象を REQUESTED / CLAIMED / RUNNING に拡張、CLAIMED 中止の競合規則): 障害復旧方式(C.3.3.1)の手動復旧手順に反映した。CPU 拡張性(B.3.1.1)の claim 排他・lease による多重実行防止の根拠は変わらず据え置き。監査ログ(E.7.1.1)は中止指示に指示者と応答を記録する記述が既にあり、停止確認応答の追加で記録範囲は変わらないため据え置き
- CR-c770d8f0-018(REQUESTED → ABORTED の説明文修正): 障害復旧方式(C.3.3.1)の中止スクリプトの説明に反映した。他メトリクスへの影響なし

## 仮採用(confidence: low)

- なし(0 件)
