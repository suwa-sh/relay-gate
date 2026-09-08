# 変更サマリ

- event_id: 20260907_013000_feedback_todo_followup
- trigger_event: rdra:20260907_011000_feedback_todo_followup
- created_at: 2026-09-07T01:30:00Z
- mode: 差分更新(nfr-grade-diff.yaml)
- dialogue_policy: interactive(グレード値の変更なし。根拠と説明の追従のみのため確認対話は不要)
- feedback request: 20260907_todo_followup(direct work unit: なし。causal work unit: CR-c770d8f0-013#1, CR-c770d8f0-014#1。packet: docs/pipeline/feedback-runs/20260907_todo_followup/stage-packets/quality_attributes.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_todo_followup"
  input_sha256: "193823ac1e6f02400269d6bdca461150a1fc8951393f332ef28580e045261389"
  request_ids: ["CR-c770d8f0-013","CR-c770d8f0-014"]
  work_unit_ids: ["CR-c770d8f0-013#1","CR-c770d8f0-014#1"]
```

マージ規則: メトリクス `id` をキーに latest/nfr-grade.yaml の該当メトリクスの `grade_description` / `reason` / `source_model` を上書きした。`grade` と `confidence` はすべて据え置き。`confidence: "user"` のメトリクスは対象に含まれない。モデルシステム(model1)は変更なし。

## 追加

- なし

## 変更

### RDRA 差分の照合(causal work unit)による追従

| ID | メトリクス | Lv(据え置き) | 起因 CR | 変更内容 |
|---|---|---|---|---|
| B.3.1.1 | CPU拡張性 | 2 | CR-013 | lease 期間と poll 間隔の出所を速報クロスチェック設定(RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC)と明記。source_model に情報「速報クロスチェック設定」を追加 |
| C.1.2.2 | バックアップ対象 | 1 | CR-013 | 設定ファイルの列挙に速報クロスチェック設定を追加。接続参照名のみで秘匿情報を含まないことを reason に明記 |
| C.3.3.1 | 障害復旧方式 | 1 | CR-014 | 中止スクリプト(abort-blue / abort-green)が対象 run の未着手(REQUESTED)の速報比較依頼も ABORTED にし、中止済み run では速報比較依頼を作成しないことを手動復旧の説明に追加。source_model に条件「中止済み run の比較依頼作成除外」「slot 中止可否判定」を追加 |
| E.5.1.1 | 認証方式 | 1 | CR-013 | 管理 DB 接続も速報クロスチェック設定の接続参照名(RAPID_DB_CONN_REF)で解決し値を置かないことを追記 |
| F.1.2.1 | 通信プロトコル | 1 | CR-013 | RDB 接続の接続先が速報クロスチェック設定の接続参照名で解決されること(off では不要)を追記 |

## 削除

- なし

## 照合結果(グレード値への影響なし)

- CR-c770d8f0-013(速報クロスチェック設定の追加): 設定所有区分・バックアップ対象・認証情報の非保存・通信プロトコル・worker 拡張の根拠に設定の出所を反映した。グレード値は変わらない
- CR-c770d8f0-014(ABORTED run では速報比較依頼を作らない・abort が未着手依頼も ABORTED にする): 障害復旧方式(C.3.3.1)の中止手順の説明に反映した。監視範囲(C.1.3.1)・監視方式(C.1.3.2)・障害検知方式(C.3.1.1)・RLO(A.4.1.3)は、中止済み対象の監視記録終端と縮退運転の根拠が変わらないため据え置き

## 仮採用(confidence: low)

- なし(0 件)
