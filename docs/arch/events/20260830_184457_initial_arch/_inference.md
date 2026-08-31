# アーキテクチャ推論根拠サマリ

- event_id: 20260830_184457_initial_arch
- created_at: 2026-08-30T18:44:57
- trigger_event: rdra:20260830_181841_initial_build, nfr:20260830_183726_initial_nfr

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 5 業務 / 8 BUC / 34 UC | 実装切替・速報/確報クロスチェック・監視・中止/リラン・適用構成。定期ジョブ(ハング検知)と専用ジョブ(リラン)を含む |
| アクター | 2 | 運用者 / 基盤適用設計者。いずれも社内。外部アクターなし |
| 外部システム | 7 | ジョブスケジューラ / 現行実装 / 新実装 / 比較ツール / メール通知 / 管理 DB(RDB) / リモート実行ホスト(SSH) |
| 情報 | 25 | 設定系 8、実行系 6、速報系 4、確報系 2、監視・復旧系 4、実行ログ 1 |
| 状態 | 5 モデル / 55 遷移行 | 並行稼働実行 / slot 実行 / クロスチェック依頼 / 速報実行の完了状況 / 監視状態 |
| 条件 | 44 | 判定表形式が多い(foreground 排他 / ハング検知 / リラン事前検証 / 中止可否 / 両系成功 / 終了コード対応) |
| バリエーション | 24 | 実装スロット / slot 実行モード / 運用モード / 依頼状態 / role 区分 等 |

### 参照した NFR グレード

| カテゴリ | 主なグレード | 主な影響 |
|---------|--------|---------|
| A. 可用性 | 運用時間 Lv3、冗長化 Lv1-2、災害対策 Lv0、RPO/RTO Lv2 | 単一 RDB + 部品冗長化。execution-spec と Runner Result からのリランで復旧 |
| B. 性能・拡張性 | 同時アクセス Lv1、レスポンス Lv2(10 秒)、バッチ Lv2(8 時間)、スケールアウト Lv2 | 基盤オーバーヘッド限定。worker の poll/claim による水平拡張 |
| C. 運用・保守性 | 監視範囲 Lv3、障害検知 Lv3、バックアップ Lv2、ログ保管 Lv2(3 ヶ月) | ハング検知の自動検知+通知+記録。日次バックアップ。run_id 付き実行ログ |
| D. 移行性 | 移行方式 Lv1(feature flag で段階切替) | 導入は一括、業務切替は運用モードの段階切替 |
| E. セキュリティ | 認証 Lv1(SSH 鍵・OS)、暗号化 Lv0/1、監査 Lv2、WAF Lv0 | IdP/APIGW/認可サービス非導入。認証情報の参照名管理 |
| F. 環境 | 対応 OS Lv1(Linux 単一)、ブラウザ Lv0 | bash 実装。OS 差異は runner に閉じ込め |

## 設計判断サマリ

### ドメインアーキテクチャ

| 要素 | 内容 | confidence |
|------|------|-----------|
| Subdomain | 実装切替(core) / クロスチェック(core) / 監視と復旧(supporting) / 適用構成(supporting) | medium |
| BC | 並行稼働実行 / 速報 / 確報 / 監視・復旧 / 適用構成。方針資料の C2 コンテナと 1:1 | medium |
| Context Map | 実行系 → 適用構成 Conformist、並行稼働実行 → 速報 OHS+PL、速報 ↔ 確報 Shared Kernel(規則のみ)、監視・復旧 → 実行系 Conformist | medium |
| Aggregate | parallel_run / rapid_run / final_crosscheck_request / 監視記録 / ジョブマップ を root とする仮説 | low |

### システムアーキテクチャ

| ティア | テクノロジー候補 | confidence | 根拠 |
|--------|----------------|-----------|------|
| tier-facade | bash CLI / SSH / ファイルシステム / RDB クライアント | high | 方針資料 C3 facade、条件「facade の責務限定」「slot 起動順序」 |
| tier-rapid-crosscheck | bash CLI(dispatcher 都度起動 + worker 常駐) / RDB / 比較ツール起動 | high | 方針資料 C3 rapid-crosscheck、条件「両系成功判定」「claim 排他」 |
| tier-final-crosscheck | bash CLI(runner + DB セグメント worker) / RDB / 比較ツール起動 | high | 方針資料 C3 final-crosscheck、条件「確報結果の中継制約」 |
| tier-ops | bash CLI(定期/専用/対話) / メールコマンド / RDB / ファイル走査 | high | 方針資料 C4、条件「監視は通知のみ」「リラン事前検証」「停止確認応答」 |
| tier-datastore | RDB(単一) / ファイルシステム | high | 外部システム「管理 DB(RDB)」、Runner Result Contract |

### アプリケーションアーキテクチャ

4 つのスクリプト tier すべてに 5 層(presentation → usecase → domain → repository / gateway)、直接依存(IF なし)。domain に判定表と状態遷移を集約し、gateway に外部連携(SSH / RDB / 比較ツール / メール / ファイル)を閉じ込める。confidence: high(状態遷移 5 種・条件 44 件)。

### データアーキテクチャ

| 区分 | エンティティ | model_type / storage | confidence |
|------|-------------|----------|-----------|
| 設定 | E-001〜E-008 | resource_scd2(適用文書のみ mutable)/ file | high(対象カタログは medium) |
| 実行記録 | E-009〜E-012, E-025 | event / file | high(ジョブ起動要求 low、応答 medium) |
| 管理レコード | E-013, E-016, E-017, E-018, E-019, E-020, E-021 | event_snapshot または event / rdb | high(監視記録 medium) |
| slot 実行 | E-014 | event_snapshot / file + rdb | medium + low |
| 通知・指示 | E-015, E-022, E-023, E-024 | event / rdb または file | medium(通知メール low) |

## ユーザー確認による変更

auto_adopt モードのため対話なし。ユーザーの事前指定(bash + RDB、UI なし、presentation tier なし、IdP/APIGW/認可サービス非導入、方針資料の構成尊重、中立表現)を confidence: user 相当として採用した(CTR-005)。

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| system_architecture | 外部連携 tier | 推論ルール上は統合レイヤー候補(外部システム 7 種) | tier 化せず gateway 層アダプタ(CTR-003) | 方針資料のコンテナに無い構造を追加しないため |
| system_architecture | ワーカー基盤 | 推論ルール上は MQ + CronJob 候補 | 管理 DB ジョブキュー + 常駐 worker / 定期ジョブ | 方針資料「管理 DB = ジョブキュー」とエアーギャップ制約 |

## confidence 内訳

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| ドメインアーキテクチャ | 0 | 17 | 5 | 0 | 0 | 22 |
| システムアーキテクチャ | 34 | 4 | 1 | 1 | 1 | 41 |
| アプリケーションアーキテクチャ | 25 | 5 | 0 | 8 | 0 | 38 |
| データアーキテクチャ(storage_mapping) | 17 | 6 | 3 | 0 | 0 | 26 |
| 合計 | 76 | 32 | 9 | 9 | 1 | 127 |

## 要確認項目(low 仮採用。docs/todo.md に登録済み)

- slot 実行の永続化方式(file 正本 + 速報有効時 rdb の二重マッピング)
- ジョブ起動要求・通知メールのストレージマッピング(永続レコードを持たず実行ログのみ)
- 集約境界仮説 5 件(root / member / 不変条件)
- 運用体制(サポート時間・夜間メールの受け手)
