# ハング監視フロー

## 概要

hang-detectorが定期実行（CronJob）でbackground実行の未完了（ハング疑い）・非0終了（background実行エラー）・速報クロスチェック異常（NG判定）を検知しハング検知記録として記録・background slot実行状態を確定（終了コードからSUCCEEDED/FAILED。timeoutや結果取得不能時はUNKNOWNとし、推測でFAILEDを確定しない）したうえで、移行運用責任者から運用者へ通知し、運用者が通知内容を確認して対応要否を判断する一連の流れを扱うBUC。hang-detectorは実行状態を自動でABORTEDへ変更しない（ABORTEDへの遷移は実行制御業務の対話確認による明示的操作でのみ発生する）。

## 所属 UC 一覧

| UC名 | アクター | 主な操作 | 関連情報 |
|------|---------|---------|---------|
| [background実行の未完了・非0終了・速報比較異常を定期検知する](background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) | 移行運用責任者（トリガーはCronJob） | STARTING/RUNNING状態の起動試行（identity = run_id, slot_type, role_type, attempt_id）の経過時間・終了コード、速報比較結果のNG判定から異常を検知し、ハング検知記録を作成しbackground slot実行状態をSUCCEEDED/FAILED（結果取得不能時はUNKNOWN）へ確定する。状態確定は履歴INSERT + snapshot UPSERTを同一transactionで行い、最終状態確定の監査イベント（slot_final_status）をaudit_logsへ追記する | Runner実行結果, 速報比較結果, ハング検知記録, audit_logs |
| [ハング疑い・異常を運用者へ通知する](ハング疑い・異常を運用者へ通知する/spec.md) | 移行運用責任者（通知先は運用者） | notified_at未設定のハング検知記録を対象にbanner/emailで通知し、notified_atを更新する | ハング検知記録 |
| [ハング疑い・異常の通知を確認する](ハング疑い・異常の通知を確認する/spec.md) | 運用者 | 通知済み（notified_at設定済み）のハング検知記録を検知日時降順、または対象run_id指定で確認する | ハング検知記録 |

## UC 横断データフロー

検知UCはSTARTING/RUNNING状態の起動試行（role_type='background'）のRunner実行結果と速報比較結果を参照してハング検知記録を新規作成し、あわせてbackground slot実行状態をSUCCEEDED/FAILED（結果取得不能時はUNKNOWN）へ確定する。状態確定はrunner_result_eventsへの履歴INSERTとrunner_resultsのsnapshot UPSERTを同一transactionで実行し、最終状態確定の監査イベント（event_name=slot_final_status、operation=status_finalize）をaudit_logsへ追記する。通知UCは未通知（notified_at IS NULL）のハング検知記録を取得して運用者へ通知しnotified_atを更新する。確認UCは通知済み（notified_at設定済み）のハング検知記録のみを参照する。

### データフロー図

```mermaid
graph LR
  Runner[("Runner実行結果\n(role=background, STARTING/RUNNING)")] -->|"R/U: 経過時間・終了コード判定\n履歴INSERT + snapshot UPSERT"| UC1["background実行の未完了・非0終了・\n速報比較異常を定期検知する"]
  Rapid[("速報比較結果\n(comparison_result=NG)")] -->|"R"| UC1
  UC1 -.->|"C: slot_final_status監査イベント"| Audit[("audit_logs + audit_chain_heads")]
  UC1 -->|"C: ハング検知記録\n(notified_at=NULL)"| UC2["ハング疑い・異常を\n運用者へ通知する"]
  UC2 -->|"U: notified_at設定"| UC3["ハング疑い・異常の\n通知を確認する"]
```

### 情報 CRUD マトリクス

| 情報名 | background実行の未完了・非0終了・速報比較異常を定期検知する | ハング疑い・異常を運用者へ通知する | ハング疑い・異常の通知を確認する |
|--------|:-------:|:-------:|:-------:|
| Runner実行結果（runner_result_events 履歴 + runner_results snapshot） | R/U（履歴INSERT + snapshot UPSERTを同一transaction） |  |  |
| 速報比較結果 | R |  |  |
| ハング検知記録 | C | R/U | R |
| audit_logs（+ audit_chain_heads） | C |  |  |

## 状態遷移全体図

```mermaid
stateDiagram-v2
  RUNNING --> SUCCEEDED: background実行の未完了・非0終了・速報比較異常を定期検知する（exitcode.txt=0を検知）
  RUNNING --> FAILED: background実行の未完了・非0終了・速報比較異常を定期検知する（exitcode.txt≠0を検知）
  STARTING --> UNKNOWN: background実行の未完了・非0終了・速報比較異常を定期検知する（timeout・結果取得不能。推測でFAILEDを確定しない）
  RUNNING --> UNKNOWN: background実行の未完了・非0終了・速報比較異常を定期検知する（timeout・結果取得不能。推測でFAILEDを確定しない）
```

### 状態遷移 UC マッピング

| 状態モデル | 遷移元 | 遷移先 | 担当 UC |
|-----------|--------|--------|--------|
| background slot実行状態 | RUNNING | SUCCEEDED | [background実行の未完了・非0終了・速報比較異常を定期検知する](background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) |
| background slot実行状態 | RUNNING | FAILED | [background実行の未完了・非0終了・速報比較異常を定期検知する](background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) |
| background slot実行状態 | STARTING / RUNNING | UNKNOWN | [background実行の未完了・非0終了・速報比較異常を定期検知する](background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md)（UNKNOWNからの確定は実結果の回収または対話確認による回復処理でのみ行う） |

hang-detectorはABORTEDへの自動遷移を行わない（ABORTEDへの遷移は実行制御業務blue/green中止フローの対話確認による明示的操作でのみ発生する）。ハング検知記録には状態モデルが定義されておらず（情報.tsvに状態モデル列なし）、notified_atの有無（NULL/設定済み）で未通知／通知済みを管理する。通知UCはnotified_atをNULLから現在時刻へ更新するのみで、状態遷移UCマッピングの対象外とする。ハング疑い・異常の通知を確認するUCは参照専用であり状態・notified_atのいずれも変更しない。

## BUC 内共有条件一覧

条件.tsv・各UCの分岐条件一覧を突合した結果、本BUC内の2つ以上のUCで共有される条件は存在しない。

| 条件名 | 条件の説明 | 適用 UC |
|--------|----------|--------|
| 該当なし | hang_detect_limit_minutes・role_type='background'限定・重複検知抑止は検知UCのみ、notified_at未設定は通知UCのみ、run_id指定の有無は確認UCのみに適用される | - |

## BUC 内共有バリエーション一覧

| バリエーション名 | 値 | 適用 UC |
|----------------|---|--------|
| 異常検知種別 | ハング疑い、background実行エラー、速報クロスチェック異常 | background実行の未完了・非0終了・速報比較異常を定期検知する, ハング疑い・異常を運用者へ通知する, ハング疑い・異常の通知を確認する |
