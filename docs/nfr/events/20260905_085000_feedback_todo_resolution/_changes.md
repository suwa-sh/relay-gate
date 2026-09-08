# 変更サマリ

- event_id: 20260905_085000_feedback_todo_resolution
- trigger_event: rdra:20260905_083000_feedback_todo_resolution
- created_at: 2026-09-05T08:50:00Z
- mode: 差分更新(nfr-grade-diff.yaml)
- dialogue_policy: interactive(CR-c770d8f0-012 は利用者の決定のため確認対話なしで適用)
- feedback request: 20260905_todo_resolution(direct work unit: CR-c770d8f0-012#1。causal work unit: CR-c770d8f0-001#1 〜 CR-c770d8f0-012#1。packet: docs/pipeline/feedback-runs/20260905_todo_resolution/stage-packets/quality_attributes.md)

```yaml
feedback_request:
  feedback_request_id: "20260905_todo_resolution"
  input_sha256: "285429579e9c9d28307d4c779317f01941b915a1203d0e5b5f53a6c014ed7108"
  request_ids: ["CR-c770d8f0-001","CR-c770d8f0-002","CR-c770d8f0-003","CR-c770d8f0-004","CR-c770d8f0-005","CR-c770d8f0-006","CR-c770d8f0-007","CR-c770d8f0-008","CR-c770d8f0-009","CR-c770d8f0-010","CR-c770d8f0-011","CR-c770d8f0-012"]
  work_unit_ids: ["CR-c770d8f0-001#1","CR-c770d8f0-002#1","CR-c770d8f0-003#1","CR-c770d8f0-004#1","CR-c770d8f0-005#1","CR-c770d8f0-006#1","CR-c770d8f0-007#1","CR-c770d8f0-008#1","CR-c770d8f0-009#1","CR-c770d8f0-010#1","CR-c770d8f0-011#1","CR-c770d8f0-012#1"]
```

マージ規則: メトリクス `id` をキーに latest/nfr-grade.yaml の該当メトリクスの `grade_description` / `reason` / `source_model` / `confidence` を上書きした。`grade` はすべて据え置き。モデルシステム(model1)は変更なし。

## 追加

- なし

## 変更

### CR-c770d8f0-012(direct): 低確信度 7 項目を既定値として確定

グレード値は変更せず、confidence を `low` → `user` に上げ、reason に確定日と「適用側で上書き可能な既定値」である旨を追記した。

| ID | メトリクス | Lv(据え置き) | confidence | 補足 |
|---|---|---|---|---|
| A.2.1.1 | サーバ内の冗長化 | 2 | low → user | source_model を内部データストア表記へ更新(CR-006 と併合) |
| A.3.1.1 | 災害対策の範囲 | 0 | low → user | |
| A.3.1.2 | 業務継続の要否 | 0 | low → user | |
| C.2.1.2 | パッチ適用方針 | 1 | low → user | |
| C.4.1.1 | テスト環境 | 2 | low → user | |
| C.5.1.1 | サポート時間 | 1 | low → user | 元資料の「warning / error でメールを飛ばし静観してもらう運用」を根拠として追記 |
| C.6.1.1 | ログ保管期間 | 2 | low → user | |

### RDRA 差分の照合(causal work unit)による追従

| ID | メトリクス | 起因 CR | 変更内容 |
|---|---|---|---|
| A.2.5.1 | ストレージの冗長化 | CR-006 | source_model の「外部システム: 管理 DB(RDB)」を「システム概要: ジョブキュー兼管理 DB(内部データストア)」へ |
| A.4.1.3 | RLO(目標復旧レベル) | CR-004 / CR-001 | 縮退運転(off)で中止(aborted.txt)とリランも成立することを reason に反映。source_model に条件「slot 実行の状態導出規則」と 3 値のモードを追加 |
| B.2.1.2 | スループット | CR-006 | reason / source_model を内部データストア表記へ |
| C.1.2.2 | バックアップ対象 | CR-010 / CR-007 | ハング検知定期ジョブ設定と適用構成文書(調整記録)を対象に追加 |
| C.1.3.2 | 監視方式 | CR-004 | 走査対象に aborted.txt を追加し、中止済み対象の監視記録終端を明記 |
| C.2.2.1 | ライフサイクル管理 | CR-001 / CR-002 | 「設定版」を廃し、実装版は BLUE_IMPL / GREEN_IMPL、マップ版はジョブマップ側の任意列とする表現へ |
| C.3.1.1 | 障害検知方式 | CR-005 | 完了通知の送信失敗は自動検知の対象外であることを reason に明記(Lv3 は据え置き) |
| C.3.2.1 | 障害通知方式 | CR-010 | 宛先・送信コマンド・件名プレフィックスの出所をハング検知定期ジョブ設定と明記 |
| C.3.3.1 | 障害復旧方式 | CR-005 | 完了通知失敗の復旧(同一引数再実行、冪等・先勝ち)を手動復旧手段に追加 |
| E.5.2.1 | アクセス制御 | CR-002 | ジョブマップの列名を user / host に揃え、ローカル実行 slot の省略可を反映 |
| E.6.1.2 | データ暗号化(通信時) | CR-006 | 管理 DB を内部データストア表記へ |
| F.1.2.1 | 通信プロトコル | CR-006 / CR-010 | 管理 DB を内部データストア表記へ。メール送信コマンドの出所を追記 |
| F.1.2.2 | 帯域要件 | CR-004 | Runner Result の構成に aborted.txt(中止時のみ)を反映 |

## 削除

- なし

## 照合結果(NFR に影響なし)

- CR-c770d8f0-003(run_id 形式): run_id の形式は NFR のグレード根拠に含まれないため変更なし
- CR-c770d8f0-008(監視状態の値集合統一・終端遷移): 監視範囲・障害検知方式のグレードと根拠は変わらないため変更なし
- CR-c770d8f0-009(並行稼働実行の遷移追加): 状態遷移の追加は NFR の根拠に影響しないため変更なし
- CR-c770d8f0-011(比較結果の登録条件): 比較結果の登録条件は NFR の根拠に影響しないため変更なし

## 仮採用(confidence: low)

- なし(0 件。今回の確定で low は解消)
