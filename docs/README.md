# relay-gate 並行稼働実行基盤

> undefined

**最終更新**: 2026-08-30 20:28:51 spec generation (specs)

## 成果物一覧

| ドメイン | 最新 | イベント数 |
|---------|------|-----------:|
| [USDM（要求分解）](#usdm要求分解) | [usdm/latest/](usdm/latest/) | 1 |
| [RDRA（要件定義）](#rdra要件定義) | [rdra/latest/](rdra/latest/) | 1 |
| [NFR（非機能要求）](#nfr非機能要求) | [nfr/latest/](nfr/latest/) | 1 |
| [Arch（アーキテクチャ）](#archアーキテクチャ) | [arch/latest/](arch/latest/) | 2 |
| [Infra（インフラ設計）](#infraインフラ設計) | [infra/latest/](infra/latest/) | 1 |
| [Design（デザイン）](#designデザイン) | - | 0 |
| [Specs（詳細仕様）](#specs詳細仕様) | [specs/latest/](specs/latest/) | 1 |

## USDM（要求分解）

### 主要な成果物

- [requirements.md](usdm/latest/requirements.md)
- [requirements.yaml](usdm/latest/requirements.yaml)

| 項目 | 値 |
|------|-----|
| 要求数 | 13 |
| 仕様数 | 44 |

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
| 外部システム | 7 |
| 情報 | 25 |
| 状態モデル | 5 |
| 条件 | 44 |
| バリエーション | 24 |
| 業務 | 5 |
| BUC | 7 |
| UC | 32 |

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
  SYS --> メール通知(["メール通知"]):::external
  SYS --> 管理_DB_RDB_(["管理 DB RDB "]):::external
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
| 言語 | bash(シェルスクリプト。facade / runner / worker / 監視 / 復旧の全スクリプト), SQL(管理 DB のジョブキュー操作。RDB クライアント CLI 経由), JavaScript(CommonJS。BDD の step 定義のみ。実行時には使用しない) |
| サブドメイン | 4 |
| Bounded Context | 5 |
| コンテキストマップ関係 | 8 |
| ティア | 5 |
| ポリシー | 26 |
| ルール | 6 |
| エンティティ | 25 |

### ドメインアーキテクチャ（コンテキストマップ）

```mermaid
graph LR
BC5["適用構成コンテキスト"]
BC1["並行稼働実行コンテキスト"]
BC2["速報クロスチェックコンテキスト"]
BC3["確報クロスチェックコンテキスト"]
BC4["実行監視・復旧コンテキスト"]
BC1 -->|Conformist| BC5
BC2 -->|Conformist| BC5
BC3 -->|Conformist| BC5
BC1 -->|OHS+PL| BC2
BC2 <-->|Shared Kernel| BC3
BC4 -->|Conformist| BC1
BC4 -->|Conformist| BC2
BC4 -->|Conformist| BC3
```

### コンテナ図（システム構成）

```mermaid
graph TD
SCHED[ジョブスケジューラ] -->|JOB_ID PARAM...| FACADE[tier-facade<br/>facade.sh + blue/green runner]
SCHED -->|別ジョブ定義| FINAL[tier-final-crosscheck<br/>runner + worker]
SCHED -->|定期ジョブ / 専用ジョブ| OPS[tier-ops<br/>hang-detector / background-rerun / abort-*]
OPERATOR[運用者] -->|直接起動| OPS
FACADE -->|SSH| IMPL[現行実装 blue / 新実装 green]
FACADE -->|blue-completed / green-completed| RAPID[tier-rapid-crosscheck<br/>dispatcher + worker]
FACADE --> DS[(tier-datastore<br/>管理 DB + 成果物 + 設定ファイル)]
RAPID --> DS
FINAL --> DS
OPS --> DS
RAPID -->|ジョブ単位比較| CMP[比較ツール]
FINAL -->|全量比較| CMP
OPS -->|warning / error| MAIL[メール通知]
FACADE -->|stdout / stderr / exitcode| SCHED
FINAL -->|stdout / stderr / exitcode| SCHED
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
U --> R[repository: rapid_run / request / comparison_result / 比較定義]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

**tier-final-crosscheck**

```mermaid
graph TD
P[presentation: final runner / worker 起動口] --> U[usecase: 登録・polling・中継 / 比較実行]
U --> D[domain: 依頼ライフサイクル・終了コード対応]
U --> R[repository: final_crosscheck_request / 対象カタログ]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

**tier-ops**

```mermaid
graph TD
P[presentation: hang-detector / background-rerun / abort-* CLI] --> U[usecase: 監視・リラン・中止フロー]
U --> D[domain: 判定表・監視状態遷移]
U --> R[repository: 監視記録 / 状態 / 成果物 / execution-spec]
R --> D
R --> G[gateway: メール / RDB / filesystem / runner 起動]
```

## Infra（インフラ設計）

### 主要な成果物

- [_changes.md](infra/latest/_changes.md)
- [_inference.md](infra/latest/_inference.md)
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
| UC | 32 |
| 非同期イベント | 4 |

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

- [background 異常の通知メールを受け取る](specs/latest/実行監視業務/background 実行監視フロー/background 異常の通知メールを受け取る/spec.md)
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

> 5 業務 / 7 BUC / 32 UC

## ADRs（設計判断記録）

| # | ドメイン | 判断 | ステータス |
|---|---------|------|----------|
| 1 | Arch | [サブドメイン分類: 実装切替とクロスチェックを Core、監視・復旧と適用構成を Supporting](arch/events/20260830_184457_initial_arch/decisions/arch-decision-001.yaml) | approved |
| 2 | Arch | [BC 設計: 並行稼働実行 / 速報 / 確報 / 監視・復旧 / 適用構成の 5 コンテキスト](arch/events/20260830_184457_initial_arch/decisions/arch-decision-002.yaml) | approved |
| 3 | Arch | [コンテキストマップ: 設定契約への Conformist、完了通知の OHS、依頼ライフサイクルの Shared Kernel](arch/events/20260830_184457_initial_arch/decisions/arch-decision-003.yaml) | approved |
| 4 | Arch | [集約境界仮説: parallel_run / rapid_run / final_crosscheck_request / 監視記録 / ジョブマップ を root とする 5 仮説](arch/events/20260830_184457_initial_arch/decisions/arch-decision-004.yaml) | approved |
| 5 | Arch | [テクノロジースタック: bash シェルスクリプト + RDB、フレームワーク非採用](arch/events/20260830_184457_initial_arch/decisions/arch-decision-005.yaml) | approved |
| 6 | Arch | [BC : tier 対応形態: 方針資料の C2 コンテナに対応する CLI スクリプト群 4 tier + データストア 1 tier](arch/events/20260830_184457_initial_arch/decisions/arch-decision-006.yaml) | approved |
| 7 | Arch | [認証・認可方式: SSH 鍵と OS 権限のみ(IdP / API Gateway / 認可サービス非導入)](arch/events/20260830_184457_initial_arch/decisions/arch-decision-007.yaml) | approved |
| 8 | Arch | [レイヤリング戦略: 全スクリプト tier で 5 層(presentation → usecase → domain → repository / gateway)の直接依存](arch/events/20260830_184457_initial_arch/decisions/arch-decision-008.yaml) | approved |
| 9 | Arch | [データモデル戦略: 状態を持つ管理レコードは event_snapshot、記録は event、設定は resource_scd2。成果物ファイルを外部 IF の正本にする](arch/events/20260830_184457_initial_arch/decisions/arch-decision-009.yaml) | approved |
| 10 | Arch | [管理 DB をジョブキューとして使い、worker は poll / claim / lease で多重実行を防ぐ(MQ 非導入)](arch/events/20260830_184457_initial_arch/decisions/arch-decision-010.yaml) | approved |
| 11 | Infra | [スクリプト実行ホストの常駐/定期起動基盤の選定](infra/events/20260830_190412_infra_product_design/docs/cloud-context/decisions/product/product-decision-001.yaml) | accepted |
| 12 | Infra | [管理DB(ジョブキュー兼管理DB)のRDBMS選定](infra/events/20260830_190412_infra_product_design/docs/cloud-context/decisions/product/product-decision-002.yaml) | accepted |
| 13 | Infra | [成果物ディレクトリ(Runner Result)の配置方式選定](infra/events/20260830_190412_infra_product_design/docs/cloud-context/decisions/product/product-decision-003.yaml) | accepted |
| 14 | Infra | [運用者向けメール通知のMTA選定](infra/events/20260830_190412_infra_product_design/docs/cloud-context/decisions/product/product-decision-004.yaml) | accepted |
| 15 | Infra | [バックアップと基盤監視の方式選定](infra/events/20260830_190412_infra_product_design/docs/cloud-context/decisions/product/product-decision-005.yaml) | accepted |
| 16 | Specs | [インターフェース契約の形式: HTTP API を持たず CLI コマンド契約(cli-command-contract.yaml)を正本にする](specs/events/20260830_202851_spec_generation/decisions/spec-decision-001.yaml) | approved |
| 17 | Specs | [イベント駆動パターン: RDB ジョブキュー(poll / claim / lease)と同期プロセス起動の完了通知を AsyncAPI で契約化する](specs/events/20260830_202851_spec_generation/decisions/spec-decision-002.yaml) | approved |
| 18 | Specs | [データ正規化レベル: 第 3 正規形・状態履歴テーブルなし・速報/確報モデル分離(rdb-schema.yaml 7 テーブル)](specs/events/20260830_202851_spec_generation/decisions/spec-decision-003.yaml) | approved |
| 19 | Specs | [横断関心事: 終了コード体系(0/2/3/6)・出力規約(key=value / TSV)・設定ファイル形式(env + TSV)・run_id 形式・通知メール手段](specs/events/20260830_202851_spec_generation/decisions/spec-decision-004.yaml) | approved |

## イベント履歴

| 日時 | ドメイン | イベントID |
|------|---------|-----------|
| 2026-08-30 18:18:41 | USDM（要求分解） | [20260830_181841_initial_build](usdm/events/20260830_181841_initial_build) |
| 2026-08-30 18:18:41 | RDRA（要件定義） | [20260830_181841_initial_build](rdra/events/20260830_181841_initial_build) |
| 2026-08-30 18:37:26 | NFR（非機能要求） | [20260830_183726_initial_nfr](nfr/events/20260830_183726_initial_nfr) |
| 2026-08-30 18:44:57 | Arch（アーキテクチャ） | [20260830_184457_initial_arch](arch/events/20260830_184457_initial_arch) |
| 2026-08-30 19:04:12 | Infra（インフラ設計） | [20260830_190412_infra_product_design](infra/events/20260830_190412_infra_product_design) |
| 2026-08-30 20:24:27 | Arch（アーキテクチャ） | [20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design](arch/events/20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design) |
| 2026-08-30 20:28:51 | Specs（詳細仕様） | [20260830_202851_spec_generation](specs/events/20260830_202851_spec_generation) |

---

*このファイルは `generateReadme.js` により自動生成されています。手動編集しないでください。*
