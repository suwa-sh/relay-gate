# 速報クロスチェックフロー

## 概要

blue/green双方のbackground runnerが完了したジョブについて、日次の全量比較（確報クロスチェック）を待たずにジョブ単位で早期に差分を検知するBUC。job_id単位でblue・green双方のRunner実行結果（role=background）がSUCCEEDED/FAILEDで揃ったこと（job_idペアリング）を確認したうえで速報比較依頼を作成し、worker（lease/claim方式）が比較を実行し、障害調査担当者が結果を確認する一連の流れを扱う。

## 所属 UC 一覧

| UC名 | アクター | 主な操作 | 関連情報 |
|------|---------|---------|---------|
| [blue/green runnerの完了通知を受けて速報比較依頼を作成する](blue-green runnerの完了通知を受けて速報比較依頼を作成する/spec.md) | 運用者（トリガーはCronJob） | job_id単位でblue/green双方のRunner実行結果（role=background）が確定済みか判定（job_idペアリング）し、RAPID_CROSSCHECK_MODE=onの場合のみ速報比較依頼を新規作成する | execution-spec.json, Runner実行結果, 速報比較依頼 |
| [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md) | 運用者（トリガーはCronJob） | REQUESTED状態の速報比較依頼をlease/claim取得し、blue/green実行結果を比較して差分を検知する | 速報比較依頼, Runner実行結果, 速報比較結果 |
| [速報クロスチェック結果を確認する](速報クロスチェック結果を確認する/spec.md) | 障害調査担当者 | job_id/run_id指定で速報比較依頼・速報比較結果を参照する | 速報比較依頼, 速報比較結果 |

## UC 横断データフロー

blue/green runnerの完了通知を受けて速報比較依頼を作成するUCは、Runner実行結果（role=background）をrun_id経由でexecution-spec.jsonとJOINしてjob_idを引き当て、**同一job_idについてblue・green双方の実行結果がSUCCEEDED/FAILEDで揃った場合のみ（job_idペアリング判定）**速報比較依頼をREQUESTEDで生成する。片方のみ完了の場合は依頼を作成せず、次回CronJobサイクルで再判定する。以降、実行UCが比較を行い、確認UCが結果を参照する。

### データフロー図

```mermaid
graph LR
  ExecSpec[("execution-spec.json")] -->|"R: run_id→job_id JOIN"| UC1
  Runner[("Runner実行結果\n(role=background)")] -->|"R: job_idペアリング判定"| UC1["blue/green runnerの完了通知を受けて\n速報比較依頼を作成する"]
  UC1 -->|"C: 速報比較依頼(REQUESTED)"| UC2["速報クロスチェックを実行し\n差分を検知する"]
  Runner -->|"R: blue/green比較対象"| UC2
  UC2 -->|"U: 速報比較依頼(SUCCEEDED/FAILED)\nC: 速報比較結果"| UC3["速報クロスチェック結果を\n確認する"]
```

### 情報 CRUD マトリクス

| 情報名 | blue/green runnerの完了通知を受けて速報比較依頼を作成する | 速報クロスチェックを実行し差分を検知する | 速報クロスチェック結果を確認する |
|--------|:-------:|:-------:|:-------:|
| execution-spec.json | R |  |  |
| Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） | R | R |  |
| 速報比較依頼 | C | R/U | R |
| 速報比較結果 |  | C | R |

## 状態遷移全体図

```mermaid
stateDiagram-v2
  [*] --> REQUESTED: blue/green runnerの完了通知を受けて速報比較依頼を作成する（job_idペアリング完了時のみ）
  REQUESTED --> CLAIMED: 速報クロスチェックを実行し差分を検知する（lease取得）
  CLAIMED --> REQUESTED: 速報クロスチェックを実行し差分を検知する（lease失効かつ未着手）
  CLAIMED --> RUNNING: 速報クロスチェックを実行し差分を検知する
  RUNNING --> SUCCEEDED: 速報クロスチェックを実行し差分を検知する（差分なし）
  RUNNING --> FAILED: 速報クロスチェックを実行し差分を検知する（差分あり）
  SUCCEEDED --> [*]
  FAILED --> [*]
```

### 状態遷移 UC マッピング

| 状態モデル | 遷移元 | 遷移先 | 担当 UC |
|-----------|--------|--------|--------|
| 速報比較依頼状態 | （新規） | REQUESTED | [blue/green runnerの完了通知を受けて速報比較依頼を作成する](blue-green runnerの完了通知を受けて速報比較依頼を作成する/spec.md)（job_idペアリング完了時のみ生成） |
| 速報比較依頼状態 | REQUESTED | CLAIMED | [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md) |
| 速報比較依頼状態 | CLAIMED | REQUESTED | [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md)（lease失効かつ未着手） |
| 速報比較依頼状態 | CLAIMED | RUNNING | [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md) |
| 速報比較依頼状態 | RUNNING | SUCCEEDED | [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md) |
| 速報比較依頼状態 | RUNNING | FAILED | [速報クロスチェックを実行し差分を検知する](速報クロスチェックを実行し差分を検知する/spec.md) |

速報クロスチェック結果を確認するUCは参照専用であり、状態遷移を発生させない。

## BUC 内共有条件一覧

条件.tsv・各UCの分岐条件一覧を突合した結果、本BUC内の2つ以上のUCで共有される条件は存在しない。

| 条件名 | 条件の説明 | 適用 UC |
|--------|----------|--------|
| 該当なし | 各UCの条件（feature flag設定（RAPID_CROSSCHECK_MODE）／blue-greenペアリング完了判定は作成UCのみ、lease/claim判定・比較判定は実行UCのみ）はいずれか1つのUCでのみ適用される | - |

## BUC 内共有バリエーション一覧

| バリエーション名 | 値 | 適用 UC |
|----------------|---|--------|
| クロスチェック種別 | 速報クロスチェック | blue/green runnerの完了通知を受けて速報比較依頼を作成する, 速報クロスチェックを実行し差分を検知する, 速報クロスチェック結果を確認する |
