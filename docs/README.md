# RelayGate

> undefined

**最終更新**: 2026-08-17 18:02:35 spec stories (design)

## 成果物一覧

| ドメイン | 最新 | イベント数 |
|---------|------|-----------:|
| [USDM（要求分解）](#usdm要求分解) | [usdm/latest/](usdm/latest/) | 1 |
| [RDRA（要件定義）](#rdra要件定義) | [rdra/latest/](rdra/latest/) | 1 |
| [NFR（非機能要求）](#nfr非機能要求) | [nfr/latest/](nfr/latest/) | 1 |
| [Arch（アーキテクチャ）](#archアーキテクチャ) | [arch/latest/](arch/latest/) | 2 |
| [Infra（インフラ設計）](#infraインフラ設計) | [infra/latest/](infra/latest/) | 1 |
| [Design（デザイン）](#designデザイン) | [design/latest/](design/latest/) | 2 |
| [Specs（詳細仕様）](#specs詳細仕様) | [specs/latest/](specs/latest/) | 1 |

## USDM（要求分解）

### 主要な成果物

- [requirements.md](usdm/latest/requirements.md)
- [requirements.yaml](usdm/latest/requirements.yaml)

| 項目 | 値 |
|------|-----|
| 要求数 | 12 |
| 仕様数 | 38 |

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
| アクター | 4 |
| 外部システム | 3 |
| 情報 | 6 |
| 状態モデル | 3 |
| 条件 | 2 |
| バリエーション | 7 |
| 業務 | 4 |
| BUC | 9 |
| UC | 23 |

### 外部ツール連携

| ツール | データファイル | 手順 |
|--------|-------------|------|
| [RDRA Graph](https://vsa.co.jp/rdratool/graph/v0.94/) | [関連データ.txt](rdra/latest/関連データ.txt) | ファイル内容をコピーし、RDRA Graph に貼り付け |
| [RDRA Sheet](https://docs.google.com/spreadsheets/d/1h7J70l6DyXcuG0FKYqIpXXfdvsaqjdVFwc6jQXSh9fM/) | [ZeroOne.txt](rdra/latest/ZeroOne.txt) | ファイル内容をコピーし、テンプレートに貼り付け |

### システムコンテキスト図

```mermaid
graph TB
  SYS["RelayGate"]
  運用者(["運用者"]):::actor --> SYS
  移行運用責任者(["移行運用責任者"]):::actor --> SYS
  障害調査担当者(["障害調査担当者"]):::actor --> SYS
  リリース判断者(["リリース判断者"]):::actor --> SYS
  SYS --> ジョブスケジューラ(["ジョブスケジューラ"]):::external
  SYS --> blue実装(["blue実装"]):::external
  SYS --> green実装(["green実装"]):::external
  classDef actor fill:#2563EB,color:#fff,stroke:none
  classDef external fill:#6B7280,color:#fff,stroke:none
```

## NFR（非機能要求）

### 主要な成果物

- [nfr-grade.md](nfr/latest/nfr-grade.md)
- [nfr-grade.yaml](nfr/latest/nfr-grade.yaml)

| 項目 | 値 |
|------|-----|
| モデルシステム | model2 |
| カテゴリ | 6 |
| 重要項目 | 66 |

## Arch（アーキテクチャ）

### 主要な成果物

- [arch-design.md](arch/latest/arch-design.md)
- [arch-design.yaml](arch/latest/arch-design.yaml)
- [coverage-report.md](arch/latest/coverage-report.md)

| 項目 | 値 |
|------|-----|
| 言語 | Shell Script (POSIX/bash), SQL |
| サブドメイン | 4 |
| Bounded Context | 4 |
| コンテキストマップ関係 | 4 |
| ティア | 4 |
| ポリシー | 12 |
| ルール | 5 |
| エンティティ | 6 |

### ドメインアーキテクチャ（コンテキストマップ）

```mermaid
graph LR
BC1["実行管理コンテキスト"]
BC2["速報クロスチェックコンテキスト"]
BC3["確報クロスチェックコンテキスト"]
BC4["異常監視コンテキスト"]
BC1 -->|OHS+PL| BC2
BC1 -->|OHS+PL| BC3
BC1 -->|OHS+PL| BC4
BC2 -->|Customer-Supplier| BC4
```

### コンテナ図（システム構成）

```mermaid
graph TD
SCHED[外部システム: ジョブスケジューラ] -->|JOB_ID/追加引数| FACADE[facade実行ティア]
FACADE -->|foreground結果のみ応答| SCHED
FACADE -->|起動/中止指示| EXT[外部連携ティア]
EXT -->|Runner Result Contract| BLUE[外部システム: blue実装]
EXT -->|Runner Result Contract| GREEN[外部システム: green実装]
FACADE --> DS[(データストアティア)]
WORKER[バックエンドワーカーティア] --> DS
WORKER -->|background起動/中止| EXT
WORKER -->|定期検知/通知| DS
```

### コンポーネント図（レイヤー依存）

**tier-facade**

```mermaid
graph TD
P[presentation] --> U[usecase]
U --> D[domain]
U --> R[repository]
R --> D
R --> G[gateway]
```

**tier-worker**

```mermaid
graph TD
P[presentation] --> U[usecase]
U --> D[domain]
U --> R[repository]
R --> D
R --> G[gateway]
```

## Infra（インフラ設計）

### 主要な成果物

- [_changes.md](infra/latest/_changes.md)
- [_inference.md](infra/latest/_inference.md)
- [infra-event.md](infra/latest/infra-event.md)
- [infra-event.yaml](infra/latest/infra-event.yaml)
- [product-input.yaml](infra/latest/product-input.yaml)

## Design（デザイン）

### 主要な成果物

- [design-event.md](design/latest/design-event.md)
- [design-event.yaml](design/latest/design-event.yaml)
- [assets/](design/latest/assets) (SVG 11 ファイル)

### ブランド

| 項目 | 値 |
|------|-----|
| 名称 | RelayGate Ops |
| プライマリカラー | `'#475569'` |
| セカンダリカラー | `'#D97706'` |
| トーン | 簡潔・断定的・運用者向け。装飾語を排し、状態と次のアクションを明示する |

### Storybook

```bash
cd docs/design/latest/storybook-app && npm run storybook
```

Stories: 24 ファイル

## Specs（詳細仕様）

### 主要な成果物

- [spec-event.md](specs/latest/spec-event.md)
- [spec-event.yaml](specs/latest/spec-event.yaml)

| 項目 | 値 |
|------|-----|
| UC | 23 |
| API | 24 |

### 横断設計

| 仕様 | ファイル |
|------|---------|
| UX デザイン仕様 | [ux-ui/ux-design.md](specs/latest/_cross-cutting/ux-ui/ux-design.md) |
| UI デザイン仕様 | [ux-ui/ui-design.md](specs/latest/_cross-cutting/ux-ui/ui-design.md) |
| データ可視化仕様 | [ux-ui/data-visualization.md](specs/latest/_cross-cutting/ux-ui/data-visualization.md) |
| 共通コンポーネント設計 | [ux-ui/common-components.md](specs/latest/_cross-cutting/ux-ui/common-components.md) |
| OpenAPI 3.1 | [api/openapi.yaml](specs/latest/_cross-cutting/api/openapi.yaml) |
| RDB スキーマ | [datastore/rdb-schema.yaml](specs/latest/_cross-cutting/datastore/rdb-schema.yaml) |
| トレーサビリティマトリクス | [traceability-matrix.md](specs/latest/_cross-cutting/traceability-matrix.md) |

### 並行稼働実行業務

**並行稼働実行フロー**

- [並行稼働実行結果を確認する](specs/latest/並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する/spec.md)
- [feature flag設定に基づきslotを選択して起動する](specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md)
- [background roleを起動する](specs/latest/並行稼働実行業務/並行稼働実行フロー/background roleを起動する/spec.md)
- [foreground roleの標準出力・標準エラー・終了コードを応答する](specs/latest/並行稼働実行業務/並行稼働実行フロー/foreground roleの標準出力・標準エラー・終了コードを応答する/spec.md)

### クロスチェック業務

**速報クロスチェックフロー**

- [速報クロスチェック結果を確認する](specs/latest/クロスチェック業務/速報クロスチェックフロー/速報クロスチェック結果を確認する/spec.md)
- blue/green runnerの完了通知を受けて速報比較依頼を作成する
- [速報クロスチェックを実行し差分を検知する](specs/latest/クロスチェック業務/速報クロスチェックフロー/速報クロスチェックを実行し差分を検知する/spec.md)

**確報クロスチェックフロー**

- [確報クロスチェック結果を確認する](specs/latest/クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md)
- [全テーブル・全ファイルを対象に確報クロスチェックを実行する](specs/latest/クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する/spec.md)
- 確報クロスチェック結果をstdout/stderr/exitcodeで応答する

### 実行監視業務

**ハング監視フロー**

- [ハング疑い・異常の通知を確認する](specs/latest/実行監視業務/ハング監視フロー/ハング疑い・異常の通知を確認する/spec.md)
- [background実行の未完了・非0終了・速報比較異常を定期検知する](specs/latest/実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md)
- [ハング疑い・異常を運用者へ通知する](specs/latest/実行監視業務/ハング監視フロー/ハング疑い・異常を運用者へ通知する/spec.md)

### 実行制御業務

**blue中止フロー**

- [blue background実行の中止を依頼する](specs/latest/実行制御業務/blue中止フロー/blue background実行の中止を依頼する/spec.md)
- [対話確認のうえblue background実行をABORTEDへ遷移させる](specs/latest/実行制御業務/blue中止フロー/対話確認のうえblue background実行をABORTEDへ遷移させる/spec.md)

**green中止フロー**

- [green background実行の中止を依頼する](specs/latest/実行制御業務/green中止フロー/green background実行の中止を依頼する/spec.md)
- [対話確認のうえgreen background実行をABORTEDへ遷移させる](specs/latest/実行制御業務/green中止フロー/対話確認のうえgreen background実行をABORTEDへ遷移させる/spec.md)

**速報比較中止フロー**

- [RUNNING中の速報比較依頼の中止を依頼する](specs/latest/実行制御業務/速報比較中止フロー/RUNNING中の速報比較依頼の中止を依頼する/spec.md)
- [対話確認のうえ速報比較依頼をABORTEDへ遷移させる](specs/latest/実行制御業務/速報比較中止フロー/対話確認のうえ速報比較依頼をABORTEDへ遷移させる/spec.md)

**確報比較中止フロー**

- [RUNNING中の確報比較依頼の中止を依頼する](specs/latest/実行制御業務/確報比較中止フロー/RUNNING中の確報比較依頼の中止を依頼する/spec.md)
- [対話確認のうえ確報比較依頼をABORTEDへ遷移させる](specs/latest/実行制御業務/確報比較中止フロー/対話確認のうえ確報比較依頼をABORTEDへ遷移させる/spec.md)

**background側リランフロー**

- [再実行対象のbackground実行・速報比較依頼を選択する](specs/latest/実行制御業務/background側リランフロー/再実行対象のbackground実行・速報比較依頼を選択する/spec.md)
- [execution-spec.jsonの実行設定を保ったまま再実行する](specs/latest/実行制御業務/background側リランフロー/execution-spec.jsonの実行設定を保ったまま再実行する/spec.md)

> 4 業務 / 9 BUC / 23 UC

## ADRs（設計判断記録）

| # | ドメイン | 判断 | ステータス |
|---|---------|------|----------|
| 1 | Arch | [サブドメイン分類とBC分割: 並行稼働実行とクロスチェック検証をCoreとする](arch/events/20260817_150512_initial_arch/decisions/arch-decision-001.yaml) | approved |
| 2 | Arch | [ティア構成: Web UI/IdP/API Gatewayを持たないシェルスクリプト中心の4ティア構成](arch/events/20260817_150512_initial_arch/decisions/arch-decision-002.yaml) | approved |
| 3 | Infra | [デプロイ先をオンプレミス単一ベンダーに限定](infra/events/20260817_151023_infra_product_design/docs/cloud-context/decisions/product/product-decision-onprem-only.yaml) | accepted |
| 4 | Infra | [永続化はRDB（PostgreSQL）+ ローカルファイルシステムの組合せとする](infra/events/20260817_151023_infra_product_design/docs/cloud-context/decisions/product/product-decision-storage-approach.yaml) | accepted |
| 5 | Design | [デザインシステムの適用範囲をCLI出力規約 + 最小トークンに限定する](design/events/20260817_153235_design_system/decisions/design-decision-001.yaml) | approved |
| 6 | Design | [ブランド・トークン・コンポーネントスタイルの採用（auto_adopt方針）](design/events/20260817_153235_design_system/decisions/design-decision-002.yaml) | approved |
| 7 | Specs | [API契約表現方式: CLIコマンド契約を正本としopenapi.yaml/asyncapi.yamlを生成しない](specs/events/20260817_155817_spec_generation/decisions/spec-decision-001.yaml) | approved |
| 8 | Specs | [同期/非同期境界: RDBのlease/claimポーリング+CronJobを非同期実行の唯一の機構とする](specs/events/20260817_155817_spec_generation/decisions/spec-decision-002.yaml) | approved |
| 9 | Specs | [RDB正規化レベル: 第3正規形を基本とし、event_snapshot型エンティティはhistory+snapshotの非正規化を許容](specs/events/20260817_155817_spec_generation/decisions/spec-decision-003.yaml) | approved |
| 10 | Specs | [横断関心事の解決方針: 終了コード規約によるエラーハンドリング、監査ログのスコープ限定、対話確認の二段階パターン統一](specs/events/20260817_155817_spec_generation/decisions/spec-decision-004.yaml) | approved |

## イベント履歴

| 日時 | ドメイン | イベントID |
|------|---------|-----------|
| 2026-08-17 14:22:58 | USDM（要求分解） | [20260817_142258_initial_build](usdm/events/20260817_142258_initial_build) |
| 2026-08-17 14:22:58 | RDRA（要件定義） | [20260817_142258_initial_build](rdra/events/20260817_142258_initial_build) |
| 2026-08-17 14:48:44 | NFR（非機能要求） | [20260817_144844_initial_nfr](nfr/events/20260817_144844_initial_nfr) |
| 2026-08-17 15:05:12 | Arch（アーキテクチャ） | [20260817_150512_initial_arch](arch/events/20260817_150512_initial_arch) |
| 2026-08-17 15:10:23 | Infra（インフラ設計） | [20260817_151023_infra_product_design](infra/events/20260817_151023_infra_product_design) |
| 2026-08-17 15:21:55 | Arch（アーキテクチャ） | [20260817_152155_arch_infra_feedback](arch/events/20260817_152155_arch_infra_feedback) |
| 2026-08-17 15:32:35 | Design（デザイン） | [20260817_153235_design_system](design/events/20260817_153235_design_system) |
| 2026-08-17 15:58:17 | Specs（詳細仕様） | [20260817_155817_spec_generation](specs/events/20260817_155817_spec_generation) |
| 2026-08-17 18:02:35 | Design（デザイン） | [20260817_180235_spec_stories](design/events/20260817_180235_spec_stories) |

---

*このファイルは `generateReadme.js` により自動生成されています。手動編集しないでください。*
