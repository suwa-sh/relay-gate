# relay-gate 並行稼働実行基盤

> 既存実装(blue)と新実装(green)をジョブスケジューラの同一ジョブ定義から並行稼働させ、クロスチェックで整合性を検証しながら段階的に切り替えるための feature flag 付きストラングラーファサード型の実行基盤。facade が feature flag(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)で slot ごとの実行モード(foreground / background / off)を選択し、background slot を先に起動してから foreground の Runner Result(stdout.log / stderr.log / exitcode.txt)だけをジョブスケジューラへ中継する。slot runner がジョブマップで JOB_ID から実行先を解決し execution-spec.json として確定保存する。速報クロスチェックはジョブ実行ごとに blue / green の完了結果を非同期に比較し、確報クロスチェックは別ジョブ定義から全テーブル・全ファイルの日次全量比較を行って stdout・stderr・exitcode をジョブスケジューラへ返す。ハング検知の定期ジョブが background 実行の異常を自身の終了結果(警告終了 / 失敗)と標準エラーで運用者へ知らせ、運用者は中止スクリプトで停止確認済みの実行を ABORTED にしてから background 側リランで元の execution-spec.json から再実行する。ハウスキープの定期ジョブが、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、終端した確報比較依頼を削除する。シェルスクリプトと relay-gate 内部のデータストアである RDB(ジョブキュー兼管理 DB。外部システムではなく relay-gate の構成要素)で構成し、実装固有のホスト配置(リモート実行ホストへの SSH 接続など)は適用側の関心事として slot の runner に閉じ込め、UI 画面を持たず CLI と定期ジョブだけで動作する。

**最終更新**: 2026-11-10 15:30:00 feedback impl feedback dcd8234d (specs)

## 成果物一覧

| ドメイン | 最新 | イベント数 |
|---------|------|-----------:|
| [USDM（要求分解）](#usdm要求分解) | [usdm/latest/](usdm/latest/) | 11 |
| [RDRA（要件定義）](#rdra要件定義) | [rdra/latest/](rdra/latest/) | 11 |
| [NFR（非機能要求）](#nfr非機能要求) | [nfr/latest/](nfr/latest/) | 11 |
| [Arch（アーキテクチャ）](#archアーキテクチャ) | [arch/latest/](arch/latest/) | 12 |
| [Infra（インフラ設計）](#infraインフラ設計) | [infra/latest/](infra/latest/) | 15 |
| [Design（デザイン）](#designデザイン) | - | 0 |
| [Specs（詳細仕様）](#specs詳細仕様) | [specs/latest/](specs/latest/) | 22 |

## USDM（要求分解）

### 主要な成果物

- [requirements.md](usdm/latest/requirements.md)
- [requirements.yaml](usdm/latest/requirements.yaml)

| 項目 | 値 |
|------|-----|
| 要求数 | 14 |
| 仕様数 | 59 |

## RDRA（要件定義）

### 主要な成果物

- [アクター.tsv](rdra/latest/アクター.tsv)
- [外部システム.tsv](rdra/latest/外部システム.tsv)
- [情報.tsv](rdra/latest/情報.tsv)
- [状態.tsv](rdra/latest/状態.tsv)
- [条件.tsv](rdra/latest/条件.tsv)
- [バリエーション.tsv](rdra/latest/バリエーション.tsv)
- [BUC.tsv](rdra/latest/BUC.tsv)
- [関連データ.txt](rdra/latest/関連データ.txt)
- [ZeroOne.txt](rdra/latest/ZeroOne.txt)
- [システム概要.json](rdra/latest/システム概要.json)
- [views/（人間可読ビュー: Mermaid 図解つき Markdown）](rdra/latest/views/README.md)

| 項目 | 値 |
|------|-----|
| アクター | 2 |
| 外部システム | 5 |
| 情報 | 24 |
| 状態モデル | 5 |
| 条件 | 49 |
| バリエーション | 21 |
| 業務 | 6 |
| BUC | 8 |
| UC | 34 |

### 外部ツール連携

| ツール | データファイル | 手順 |
|--------|-------------|------|
| [RDRA Graph](https://vsa.co.jp/rdratool/graph/v0.94/) | [関連データ.txt](rdra/latest/関連データ.txt) | ファイル内容をコピーし、RDRA Graph に貼り付け |
| [RDRA Sheet](https://docs.google.com/spreadsheets/d/1h7J70l6DyXcuG0FKYqIpXXfdvsaqjdVFwc6jQXSh9fM/) | [ZeroOne.txt](rdra/latest/ZeroOne.txt) | ファイル内容をコピーし、テンプレートに貼り付け |

### システムコンテキスト図

```mermaid
graph TB
  SYS["relay-gate 並行稼働実行基盤"]
  運用者(["運用者"]):::actor --> SYS
  基盤適用設計者(["基盤適用設計者"]):::actor --> SYS
  SYS --> ジョブスケジューラ(["ジョブスケジューラ"]):::external
  SYS --> 現行実装_blue_(["現行実装 blue "]):::external
  SYS --> 新実装_green_(["新実装 green "]):::external
  SYS --> 比較ツール(["比較ツール"]):::external
  SYS --> リモート実行ホスト_SSH_(["リモート実行ホスト SSH "]):::external
  classDef actor fill:#2563EB,color:#fff,stroke:none
  classDef external fill:#6B7280,color:#fff,stroke:none
```

## NFR（非機能要求）

### 主要な成果物

- [nfr-grade.md](nfr/latest/nfr-grade.md)
- [nfr-grade.yaml](nfr/latest/nfr-grade.yaml)

| 項目 | 値 |
|------|-----|
| モデルシステム | model1 |
| カテゴリ | 6 |
| 重要項目 | 76 |

## Arch（アーキテクチャ）

### 主要な成果物

- [arch-design.md](arch/latest/arch-design.md)
- [arch-design.yaml](arch/latest/arch-design.yaml)
- [coverage-report.md](arch/latest/coverage-report.md)

| 項目 | 値 |
|------|-----|
| 言語 | bash(シェルスクリプト。facade / runner / worker / 監視 / 復旧 / ハウスキープの全スクリプト), SQL(管理 DB のジョブキュー操作。RDB クライアント CLI 経由), JavaScript(CommonJS。BDD の step 定義のみ。実行時には使用しない) |
| サブドメイン | 5 |
| Bounded Context | 6 |
| コンテキストマップ関係 | 13 |
| ティア | 5 |
| ポリシー | 28 |
| ルール | 6 |
| エンティティ | 24 |

### ドメインアーキテクチャ（コンテキストマップ）

```mermaid
graph LR
BC5["適用構成コンテキスト"]
BC1["並行稼働実行コンテキスト"]
BC2["速報クロスチェックコンテキスト"]
BC3["確報クロスチェックコンテキスト"]
BC4["実行監視・復旧コンテキスト"]
BC6["ハウスキープコンテキスト"]
BC1 -->|Conformist| BC5
BC2 -->|Conformist| BC5
BC3 -->|Conformist| BC5
BC1 -->|OHS+PL| BC2
BC2 <-->|Shared Kernel| BC3
BC4 -->|Conformist| BC1
BC4 -->|Conformist| BC2
BC4 -->|Conformist| BC3
BC6 -->|Conformist| BC1
BC6 -->|Conformist| BC2
BC6 -->|Conformist| BC3
BC6 -->|Conformist| BC4
BC6 -->|Conformist| BC5
```

### コンテナ図（システム構成）

```mermaid
graph TD
SCHED[ジョブスケジューラ] -->|JOB_ID PARAM...| FACADE[tier-facade<br/>facade.sh + blue/green runner]
SCHED -->|別ジョブ定義| FINAL[tier-final-crosscheck<br/>runner + worker]
SCHED -->|定期ジョブ / 専用ジョブ| OPS[tier-ops<br/>hang-detector / housekeep / background-rerun / abort-*]
OPERATOR[運用者] -->|直接起動| OPS
FACADE -->|SSH| IMPL[現行実装 blue / 新実装 green]
FACADE -->|blue-completed / green-completed| RAPID[tier-rapid-crosscheck<br/>dispatcher + worker]
FACADE --> DS[(tier-datastore<br/>管理 DB + 成果物 + 設定ファイル)]
RAPID --> DS
FINAL --> DS
OPS --> DS
RAPID -->|ジョブ単位比較| CMP[比較ツール]
FINAL -->|全量比較| CMP
FACADE -->|stdout / stderr / exitcode| SCHED
FINAL -->|stdout / stderr / exitcode| SCHED
OPS -->|stdout / stderr / exitcode<br/>ハング検知の警告終了・失敗<br/>ハウスキープの削除件数・失敗| SCHED
SCHED -->|障害通知| OPERATOR
```

### コンポーネント図（レイヤー依存）

**tier-facade**

```mermaid
graph TD
P[presentation: facade.sh / runner CLI] --> U[usecase: slot 起動フロー]
U --> D[domain: 判定表・状態遷移]
U --> R[repository: parallel_run / execution-spec / Runner Result / 設定]
R --> D
R --> G[gateway: SSH / filesystem / RDB / completed 通知]
```

**tier-rapid-crosscheck**

```mermaid
graph TD
P[presentation: blue-completed / green-completed / worker 起動口] --> U[usecase: dispatcher / worker フロー]
U --> D[domain: 両系成功判定・依頼ライフサイクル]
U --> R[repository: rapid_run / request / 起動コマンド]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

**tier-final-crosscheck**

```mermaid
graph TD
P[presentation: final runner / worker 起動口] --> U[usecase: 登録・polling・中継 / 比較実行]
U --> D[domain: 依頼ライフサイクル・終了コード対応]
U --> R[repository: final_crosscheck_request / 起動コマンド]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

**tier-ops**

```mermaid
graph TD
P[presentation: hang-detector / housekeep / background-rerun / abort-* CLI] --> U[usecase: 監視・ハウスキープ・リラン・中止フロー]
U --> D[domain: 判定表・監視状態遷移・削除判定]
U --> R[repository: 監視記録 / 通知済みの印 / 状態 / 成果物 / execution-spec / 設定]
R --> D
R --> G[gateway: RDB 業務用 / RDB ハウスキープ専用 / filesystem / runner 起動]
```

## Infra（インフラ設計）

### 主要な成果物

- [_changes.md](infra/latest/_changes.md)
- [_inference.md](infra/latest/_inference.md)
- [infra-event-diff.yaml](infra/latest/infra-event-diff.yaml)
- [infra-event.md](infra/latest/infra-event.md)
- [infra-event.yaml](infra/latest/infra-event.yaml)
- [product-input.yaml](infra/latest/product-input.yaml)

## Design（デザイン）

design ステージは pipeline-config の `skip_steps` で skip されている（UI 画面を持たないプロダクト）。

## Specs（詳細仕様）

### 主要な成果物

- [spec-event.md](specs/latest/spec-event.md)
- [spec-event.yaml](specs/latest/spec-event.yaml)

| 項目 | 値 |
|------|-----|
| UC | 34 |
| 非同期イベント | 3 |

### 横断設計

| 仕様 | ファイル |
|------|---------|
| UX デザイン仕様 | [ux-ui/ux-design.md](specs/latest/_cross-cutting/ux-ui/ux-design.md) |
| UI デザイン仕様 | [ux-ui/ui-design.md](specs/latest/_cross-cutting/ux-ui/ui-design.md) |
| データ可視化仕様 | [ux-ui/data-visualization.md](specs/latest/_cross-cutting/ux-ui/data-visualization.md) |
| OpenAPI 3.1 | [api/openapi.yaml](specs/latest/_cross-cutting/api/openapi.yaml) |
| AsyncAPI 3.0 | [api/asyncapi.yaml](specs/latest/_cross-cutting/api/asyncapi.yaml) |
| RDB スキーマ | [datastore/rdb-schema.yaml](specs/latest/_cross-cutting/datastore/rdb-schema.yaml) |
| トレーサビリティマトリクス | [traceability-matrix.md](specs/latest/_cross-cutting/traceability-matrix.md) |

### 実装切替業務

**実装切替ジョブ実行フロー**

- [業務ジョブの実行結果を確認する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/業務ジョブの実行結果を確認する/spec.md)
- [slot 実行モードを選択して runner を起動する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md)
- [ジョブマップで JOB_ID から実行先を解決する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md)
- [execution-spec.json を確定保存する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/execution-spec.json を確定保存する/spec.md)
- [実装スクリプトを実行して Runner Result を出力する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/実装スクリプトを実行して Runner Result を出力する/spec.md)
- [foreground slot の結果をジョブスケジューラへ中継する](specs/latest/実装切替業務/実装切替ジョブ実行フロー/foreground slot の結果をジョブスケジューラへ中継する/spec.md)

### クロスチェック業務

**速報クロスチェックフロー**

- [速報比較結果を参照する](specs/latest/クロスチェック業務/速報クロスチェックフロー/速報比較結果を参照する/spec.md)
- [速報クロスチェック runner へ完了通知を送信する](specs/latest/クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/spec.md)
- [両系成功時に速報比較依頼を作成する](specs/latest/クロスチェック業務/速報クロスチェックフロー/両系成功時に速報比較依頼を作成する/spec.md)
- [速報比較依頼を claim する](specs/latest/クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/spec.md)
- [比較ツールでジョブ単位比較を実行して結果を登録する](specs/latest/クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md)

**確報クロスチェックフロー**

- [確報クロスチェック結果を確認する](specs/latest/クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md)
- [確報比較依頼を登録して終端状態まで待機する](specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を登録して終端状態まで待機する/spec.md)
- [確報比較依頼を claim する](specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を claim する/spec.md)
- [比較ツールで日次全量比較を実行して結果を保存する](specs/latest/クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md)
- [保存済みの確報結果をジョブスケジューラへ返す](specs/latest/クロスチェック業務/確報クロスチェックフロー/保存済みの確報結果をジョブスケジューラへ返す/spec.md)

### 実行監視業務

**background 実行監視フロー**

- [ハング検知ジョブの異常終了を確認する](specs/latest/実行監視業務/background 実行監視フロー/ハング検知ジョブの異常終了を確認する/spec.md)
- [background 実行の経過時間と終了状態を判定する](specs/latest/実行監視業務/background 実行監視フロー/background 実行の経過時間と終了状態を判定する/spec.md)
- [ハング疑い・実行エラー・比較異常を通知する](specs/latest/実行監視業務/background 実行監視フロー/ハング疑い・実行エラー・比較異常を通知する/spec.md)
- [監視記録を保存する](specs/latest/実行監視業務/background 実行監視フロー/監視記録を保存する/spec.md)
- [hang_detect_limit_minutes をジョブごとに調整する](specs/latest/実行監視業務/background 実行監視フロー/hang_detect_limit_minutes をジョブごとに調整する/spec.md)

### 実行復旧業務

**実行中止フロー**

- [現在状態を確認して停止確認に応答する](specs/latest/実行復旧業務/実行中止フロー/現在状態を確認して停止確認に応答する/spec.md)
- [実行を ABORTED へ遷移させる](specs/latest/実行復旧業務/実行中止フロー/実行を ABORTED へ遷移させる/spec.md)

**background 側リランフロー**

- [リラン結果を parent_run_id で追跡する](specs/latest/実行復旧業務/background 側リランフロー/リラン結果を parent_run_id で追跡する/spec.md)
- [リラン対象を検証する](specs/latest/実行復旧業務/background 側リランフロー/リラン対象を検証する/spec.md)
- [元の execution-spec.json から復元して新しい run_id で起動する](specs/latest/実行復旧業務/background 側リランフロー/元の execution-spec.json から復元して新しい run_id で起動する/spec.md)
- [速報比較依頼だけを新規作成する](specs/latest/実行復旧業務/background 側リランフロー/速報比較依頼だけを新規作成する/spec.md)

### 適用構成業務

**適用構成定義フロー**

- [切り替えた運用モードで業務ジョブを実行する](specs/latest/適用構成業務/適用構成定義フロー/切り替えた運用モードで業務ジョブを実行する/spec.md)
- [feature flag を設定する](specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md)
- [slot runner の実体スクリプトを割り当てる](specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md)
- [slot ごとのジョブマップを定義する](specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/spec.md)
- [クロスチェックのジョブマップと比較定義を定義する](specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md)

### ハウスキープ業務

**ハウスキープフロー**

- [保持日数を過ぎた終了済みの実行と確報比較依頼を判定する](specs/latest/ハウスキープ業務/ハウスキープフロー/保持日数を過ぎた終了済みの実行と確報比較依頼を判定する/spec.md)
- [成果物と管理 DB の履歴を削除する](specs/latest/ハウスキープ業務/ハウスキープフロー/成果物と管理 DB の履歴を削除する/spec.md)

> 6 業務 / 8 BUC / 34 UC

## ADRs（設計判断記録）

全64件。ドメイン別の一覧から個別の判断記録を参照できます。

| ドメイン | 件数 | 一覧 |
|---------|-----:|------|
| Arch | 26 | [判断記録を開く](_indexes/adrs/arch.md) |
| Infra | 5 | [判断記録を開く](_indexes/adrs/infra.md) |
| Specs | 33 | [判断記録を開く](_indexes/adrs/specs.md) |

## Pipeline feedback runs

distillery-impl が公開した feedback-request Markdown を `dist-pipeline` が差分実行した記録。
`input.md`（不変 snapshot）/ `routing.json`（所有 stage の判定）/ `plan.json`（work unit と実行順）/ `result.json`（要求ごとの最終判定）を含む。

| feedback_id | 状態 | 要求 | applied | merged | deferred | 実行 stage | run dir |
|-------------|------|-----:|--------:|-------:|---------:|-----------|---------|
| 20260905_todo_resolution | completed | 12 | 12 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20260905_todo_resolution) |
| 20260907_abort_consistency | completed | 3 | 3 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20260907_abort_consistency) |
| 20260907_todo_followup | completed | 3 | 3 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20260907_todo_followup) |
| 20260908_slot_status_wording | completed | 1 | 1 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20260908_slot_status_wording) |
| 20260908_spec_machine_readable | completed | 3 | 3 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20260908_spec_machine_readable) |
| 20260917_014138_impl_feedback_fd678b04 | completed | 2 | 2 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20260917_014138_impl_feedback_fd678b04) |
| 20260917_081430_impl_feedback_fd678b04 | completed | 1 | 1 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20260917_081430_impl_feedback_fd678b04) |
| 20260919_213000_impl_feedback_eff24f55 | completed | 5 | 5 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20260919_213000_impl_feedback_eff24f55) |
| 20260922_130000_impl_feedback_eff24f55 | completed | 2 | 2 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20260922_130000_impl_feedback_eff24f55) |
| 20261010_104636_impl_feedback_dcd8234d | completed | 4 | 4 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261010_104636_impl_feedback_dcd8234d) |
| 20261027_053600_impl_feedback_dcd8234d | completed | 1 | 1 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20261027_053600_impl_feedback_dcd8234d) |
| 20261027_091000_impl_feedback_dcd8234d | completed | 2 | 2 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261027_091000_impl_feedback_dcd8234d) |
| 20261101_mail_removal_housekeeping | completed | 3 | 3 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261101_mail_removal_housekeeping) |
| 20261103_env_duplicate_key | completed | 1 | 1 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20261103_env_duplicate_key) |
| 20261103_housekeeping_db_required | completed | 2 | 2 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261103_housekeeping_db_required) |
| 20261103_housekeeping_followups | completed | 3 | 3 | 0 | 0 | requirements → quality_attributes → architecture → infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261103_housekeeping_followups) |
| 20261104_external_review_fixes | completed | 4 | 4 | 0 | 0 | infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261104_external_review_fixes) |
| 20261104_rapid_env_deploy_check | completed | 1 | 1 | 0 | 0 | infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261104_rapid_env_deploy_check) |
| 20261105_external_review_round2 | completed | 2 | 2 | 0 | 0 | infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261105_external_review_round2) |
| 20261105_single_management_db | completed | 1 | 1 | 0 | 0 | infrastructure → spec | [feedback-runs/](pipeline/feedback-runs/20261105_single_management_db) |
| 20261110_080548_impl_feedback_dcd8234d | completed | 2 | 2 | 0 | 0 | spec | [feedback-runs/](pipeline/feedback-runs/20261110_080548_impl_feedback_dcd8234d) |

## イベント履歴

全82件。ドメイン別の履歴から個別のイベントを参照できます。

| ドメイン | 件数 | 履歴 |
|---------|-----:|------|
| USDM（要求分解） | 11 | [履歴を開く](_indexes/events/usdm.md) |
| RDRA（要件定義） | 11 | [履歴を開く](_indexes/events/rdra.md) |
| NFR（非機能要求） | 11 | [履歴を開く](_indexes/events/nfr.md) |
| Arch（アーキテクチャ） | 12 | [履歴を開く](_indexes/events/arch.md) |
| Infra（インフラ設計） | 15 | [履歴を開く](_indexes/events/infra.md) |
| Specs（詳細仕様） | 22 | [履歴を開く](_indexes/events/specs.md) |

---

*このファイルは `generateReadme.js` により自動生成されています。手動編集しないでください。*
