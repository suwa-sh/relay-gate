# アーキテクチャ推論根拠サマリ

- event_id: 20260817_150512_initial_arch
- created_at: 2026-08-17T15:05:12

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 4業務/9フロー | 並行稼働実行・クロスチェック(速報/確報)・実行監視・実行制御の4業務。バッチ/定期監視・対話確認を伴う中止操作・選択的リランを含む |
| アクター | 4 | 全て社内アクター（外部アクター無し）。運用者/移行運用責任者/障害調査担当者/リリース判断者 |
| 外部システム | 3 | ジョブスケジューラ（起動元）、blue実装/green実装（strangler対象・移行先） |
| 情報 | 6 | 実行管理/速報クロスチェック管理/確報クロスチェック管理/異常監視管理の4コンテキストに整理済み |
| 状態 | 3状態モデル | background slot実行状態、速報比較依頼状態、確報比較依頼状態。いずれも5遷移以上 |
| 条件 | 2 | feature flag設定（BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODE）、hang_detect_limit_minutes |

### 参照した NFR グレード

| カテゴリ | 主な影響 |
|---------|---------|
| A. 可用性 | 24時間無停止(Lv5)→常時稼働方針、コールドスタンバイ切替・DR/RPO/RTO(medium confidence、Step0仮置き) |
| B. 性能・拡張性 | 少人数運用者中心の小規模トラフィック(Lv1中心)→スケールアップ方針、確報バッチ8時間以内 |
| C. 運用・保守性 | アプリケーション監視(Lv3)→run_id相関トレーサビリティ、監査ログ+改ざん検知の障害検知方式(Lv3) |
| D. 移行性 | 並行運用+段階移行方式(Lv3, high confidence)がシステム概要と直結 |
| E. セキュリティ | エアギャップによるネットワーク分離(high)、WAF/Web対策なし(high)、認証・アクセス制御はRDRAに詳細記載なくlow/medium仮置き |
| F. 環境 | 単一OS(Linux)限定、ブラウザ非対応(いずれもhigh confidence) |

## ドメインアーキテクチャ推論（Part 0）

- Q1 サブドメイン分類: BUCクラスタ4件をCore2/Supporting2に分類。Core判定（並行稼働実行・クロスチェック検証）は経営判断要素を含むためconfidence: medium上限
- Q2 BC分割: 情報.tsvのコンテキスト列（実行管理/速報クロスチェック管理/確報クロスチェック管理/異常監視管理）を機械的根拠としてBC-001〜BC-004に対応付け。confidence: medium上限
- Q3 コンテキストマップ: システム概要の「Runner Result Contract」を公開言語とみなし、BC-001を上流としたOHS+Published Languageパターンで整理
- Q4 集約仮説: 情報.tsvのrelationships・状態.tsvの遷移波及から5件の集約仮説を抽出。confidence: low（戦略段階の仮説）

## システムアーキテクチャ推論（Part 1）

| ティア | テクノロジー候補 | confidence | 根拠 |
|--------|----------------|-----------|------|
| facade実行ティア | CLI実行基盤(シェルスクリプト), SSH | high | 外部アクター無し・Web UI無しのためAPI Gateway/IdP/フロントエンド不要と判定し、CLIエントリポイントとして設計 |
| バックエンドワーカーティア | CronJob(cron/systemdタイマー), CLI実行基盤(lease/claim) | high | BUC「ハング監視フロー」の定期検知、速報/確報クロスチェックの非同期lease/claim機構 |
| データストアティア | RDB(ジョブキュー兼管理DB), ファイルシステム(ログ本体) | high | プロジェクト背景「RDBをジョブキュー兼管理DBとして利用」に直接合致 |
| 外部連携ティア | アダプタ(シェルスクリプト経由プロセス起動・SSH) | high | 外部システム3件（ジョブスケジューラ/blue実装/green実装）との連携が必須 |

BC:tier対応形態はモジュラモノリス相当（facade実行ティア+バックエンドワーカーティア内にBC-001〜BC-004をモジュールとして配置）とした。認可は検出パターンがロールベースのみのためRBAC+Backend作り込みを選定。

## アプリケーションアーキテクチャ推論（Part 2）

### facade実行ティア・バックエンドワーカーティア

| レイヤー | 責務 | confidence | 根拠 |
|---------|------|-----------|------|
| presentation | Driver Sideの入出力（CLI引数解析/lease claim/結果出力） | high | 状態遷移が5種以上(3状態モデル)存在するため5層を選定 |
| usecase | フロー制御・トランザクション境界 | high | 同上 |
| domain | ビジネスルール（排他制約・状態遷移整合性） | high | 状態.tsvの複雑な遷移パス |
| repository | aggregate root(execution-spec.json/Runner実行結果/速報・確報比較依頼/ハング検知記録)と1:1 | default | DDD集約パターンの標準適用 |
| gateway | RDB adapter + 外部実装client(Runner Result Contract変換) | high | 外部システム3件との連携 |

## データアーキテクチャ推論（Part 3）

| エンティティ | ストレージ | confidence | 根拠 |
|-------------|----------|-----------|------|
| execution-spec.json | rdb | high | リラン復元・実行系譜追跡の基準（プロジェクト背景のRDBジョブキュー方針） |
| Runner実行結果 | rdb | high | 状態モデルを持ち頻繁に横断参照される |
| 速報比較依頼 | rdb | high | lease/claim排他制御が必要 |
| 速報比較結果 | rdb | high | 速報比較依頼と1:1、障害調査担当者の早期検知に利用 |
| 確報比較依頼 | rdb | high | lease/claim排他制御、リリース判断の正本 |
| ハング検知記録 | rdb | high | run_id起点の横断参照による異常判定 |

## 要確認項目

以下は confidence: low の項目であり、dialogue_policy: auto_adopt により保守的な⭐推奨を仮採用のうえ docs/todo.md に登録した。詳細は完了報告の「採用一覧」を参照。

- CTP-001 認証方式（SSH鍵+MFAの具体的な運用要否）
- CTP-009 性能・拡張性の設計方針（CLI応答時間・スループット目標値の妥当性）
- SR-004 データ移行量の前提（blueからのデータ移行が本当に不要か）
- AG-001〜AG-005 集約境界仮説（戦略段階の仮説であり、dist-spec/ddd-tactical-implementationでの最終確定が前提）
