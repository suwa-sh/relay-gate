# Spec 生成 分析根拠

## 分析日時

2026-08-17 15:58 (event_id: 20260817_155817_spec_generation)

## システム名

- 和名（見出し・ドキュメントタイトル用）: RelayGate（システム概要.json `system_name`）
- ブランド名（design-event.yaml `brand.name`）: RelayGate Ops

## UC 一覧（業務/BUC/UC ツリー、23 UC・9 BUC・4 業務）

```
並行稼働実行業務
  └── 並行稼働実行フロー
        ├── 並行稼働実行結果を確認する
        ├── feature flag設定に基づきslotを選択して起動する
        ├── background roleを起動する
        └── foreground roleの標準出力・標準エラー・終了コードを応答する
クロスチェック業務
  ├── 速報クロスチェックフロー
  │     ├── 速報クロスチェック結果を確認する
  │     ├── blue/green runnerの完了通知を受けて速報比較依頼を作成する
  │     └── 速報クロスチェックを実行し差分を検知する
  └── 確報クロスチェックフロー
        ├── 確報クロスチェック結果を確認する
        ├── 全テーブル・全ファイルを対象に確報クロスチェックを実行する
        └── 確報クロスチェック結果をstdout/stderr/exitcodeで応答する
実行監視業務
  └── ハング監視フロー
        ├── ハング疑い・異常の通知を確認する
        ├── background実行の未完了・非0終了・速報比較異常を定期検知する
        └── ハング疑い・異常を運用者へ通知する
実行制御業務
  ├── blue中止フロー
  │     ├── blue background実行の中止を依頼する
  │     └── 対話確認のうえblue background実行をABORTEDへ遷移させる
  ├── green中止フロー
  │     ├── green background実行の中止を依頼する
  │     └── 対話確認のうえgreen background実行をABORTEDへ遷移させる
  ├── 速報比較中止フロー
  │     ├── RUNNING中の速報比較依頼の中止を依頼する
  │     └── 対話確認のうえ速報比較依頼をABORTEDへ遷移させる
  ├── 確報比較中止フロー
  │     ├── RUNNING中の確報比較依頼の中止を依頼する
  │     └── 対話確認のうえ確報比較依頼をABORTEDへ遷移させる
  └── background側リランフロー
        ├── 再実行対象のbackground実行・速報比較依頼を選択する
        └── execution-spec.jsonの実行設定を保ったまま再実行する
```

## アーキテクチャ上の重大な前提（arch-design.yaml 由来）

- `system_architecture.tiers` に **Presentation 系ティアは存在しない**（tier-facade / tier-worker / tier-datastore / tier-external-integration の4つのみ）。プロジェクト背景（Web UIを持たないCLI/バッチ運用）と整合する
- tier-facade は `technology_candidates`（CLI実行基盤、SSH）が spec-generate.md の機械判定キーワード（SPA/SSR/REST/GraphQL/Worker等）のいずれにも該当しないが、責務（Driver Sideの入出力、CLI引数解析、応答整形）から実質的に **API/バックエンド系ティアに相当**すると判断し、`tier-{tier_id}.md`（API系フォーマット）を準用する
- tier-worker は `technology_candidates` に「CronJob」「workerプロセス」を含み、機械判定キーワード（Worker）に合致するため **非同期処理/ワーカー系ティア**として扱う
- tier-datastore / tier-external-integration は UC 単位の Spec では生成しない（spec-generate.md の明記どおり、cross-cutting 専用）

## UC-ティアマッピング（BUC.tsv の関連モデル・arch-design.yaml の bounded context/aggregate owned_entity から判定）

| # | UC名 | 対象ティア | 判定根拠 |
|---|------|-----------|---------|
| 1 | 並行稼働実行結果を確認する | tier-facade | BC-001所属。E-001/E-002参照読み取り |
| 2 | feature flag設定に基づきslotを選択して起動する | tier-facade | SP-001/SP-002/SR-001（facadeのpolicy/rule） |
| 3 | background roleを起動する | tier-facade + tier-worker | L-facade-usecase「background role先行起動」= facadeが起動トリガー。tier-worker description「BC-001のbackground role実行部分を実装する」= 実際の実行はworker |
| 4 | foreground roleの標準出力・標準エラー・終了コードを応答する | tier-facade | SP-002 foreground結果限定応答 |
| 5 | 速報クロスチェック結果を確認する | tier-worker | BC-002 owned_buc_ids=速報クロスチェックフロー |
| 6 | blue/green runnerの完了通知を受けて速報比較依頼を作成する | tier-worker | BC-002 |
| 7 | 速報クロスチェックを実行し差分を検知する | tier-worker | BC-002 |
| 8 | 確報クロスチェック結果を確認する | tier-worker | BC-003 owned_buc_ids=確報クロスチェックフロー |
| 9 | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | tier-worker | BC-003 |
| 10 | 確報クロスチェック結果をstdout/stderr/exitcodeで応答する | tier-worker | 確報runnerは独立バッチであり、blue/green foreground経由のSP-002とは別系統。BC-003状態SUCCEEDED/FAILEDの説明「runnerがstdout/stderr/exitcodeのみジョブスケジューラへ中継」から worker責務と判断 |
| 11 | ハング疑い・異常の通知を確認する | tier-worker | BC-004 owned_buc_ids=ハング監視フロー |
| 12 | background実行の未完了・非0終了・速報比較異常を定期検知する | tier-worker | BC-004。tier-worker description「hang-detectorによる定期監視」 |
| 13 | ハング疑い・異常を運用者へ通知する | tier-worker | BC-004 |
| 14 | blue background実行の中止を依頼する | tier-facade | 対象=E-002(Runner実行結果, BC-001/AG-002)。L-facade-domain「ABORTEDへの明示的遷移制御」 |
| 15 | 対話確認のうえblue background実行をABORTEDへ遷移させる | tier-facade | 同上 |
| 16 | green background実行の中止を依頼する | tier-facade | 同上（green） |
| 17 | 対話確認のうえgreen background実行をABORTEDへ遷移させる | tier-facade | 同上（green） |
| 18 | RUNNING中の速報比較依頼の中止を依頼する | tier-worker | 対象=E-003(速報比較依頼, BC-002) |
| 19 | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる | tier-worker | 同上 |
| 20 | RUNNING中の確報比較依頼の中止を依頼する | tier-worker | 対象=E-005(確報比較依頼, BC-003) |
| 21 | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる | tier-worker | 同上 |
| 22 | 再実行対象のbackground実行・速報比較依頼を選択する | tier-facade + tier-worker | background実行(E-002/facade)と速報比較依頼(E-003/worker)の双方から選定するため両ティア |
| 23 | execution-spec.jsonの実行設定を保ったまま再実行する | tier-facade + tier-worker | execution-spec.json(E-001/facade)の実行設定復元＋background実行(facade)・速報比較依頼(worker)双方の再実行を含む |

**Presentation相当の内容の扱い**: design-event.yaml には23画面が定義され、23 UCと1:1対応する（`運用ポータル ops` = CLI出力／将来運用ダッシュボード）。arch-design.yaml にPresentation系ティアが存在しないため、専用の `tier-frontend.md` は生成しない。代わりに、各UCが対象とする tier-facade.md / tier-worker.md 内に「CLI 出力/画面表示マッピング」節を設け、design-event.yaml の画面・コンポーネント・トークン参照をそこに統合する。

## サブエージェント分割（Step3 並列実行）

| グループ | UC数 | 内容 |
|---------|------|------|
| Group A | 8 | 並行稼働実行業務(4) + blue中止フロー(2) + green中止フロー(2) |
| Group B | 9 | クロスチェック業務(速報3+確報3) + ハング監視フロー(3) |
| Group C | 6 | 速報比較中止フロー(2) + 確報比較中止フロー(2) + background側リランフロー(2) |

## API 設計方式の確認推奨項目（dialogue-format準拠、auto_adopt により⭐採用）

### 1: API 設計方式（HTTP API不在環境でのAPI契約表現）
- **Option A** (⭐推奨): CLI コマンド契約（独自YAMLスキーマ `_cross-cutting/api/cli-command-contract.yaml`）を正本とする。`openapi.yaml`は生成しない — プロジェクト背景「HTTP API は原則ありません。API 設計は「CLI コマンド契約 + ファイル契約 + DB スキーマ」を正本として扱ってください」に直接合致
- **Option B**: 従来通りHTTP OpenAPI 3.1で仮想的なREST APIとして表現する — dist-specスキル既定動作に忠実だが実態と乖離した架空エンドポイントを生む
- **Option C**: OpenAPI構文（path/operationId）を流用しCLIコマンドを表現するハイブリッド — redocly lint等ツールチェーン互換は保てるが読み手に誤解を与える

**推奨理由**: high — team-lead指示のプロジェクト背景に直接明記された制約

### 2: エラーハンドリング戦略
- **Option A** (⭐推奨): 終了コード規約（0=正常、1=業務エラー、2=バリデーションエラー、124=タイムアウト、130=SIGINT中断）+ domain例外はusecase層で集約キャッチし1回ログ出力、presentation層でCLI終了コードへ変換（CLP-002準拠） — 既存アーキ方針と完全一致、ジョブスケジューラ契約（stdout/stderr/exitcodeのみ）を壊さない
- **Option B**: 例外スタックトレースをそのままstderrへ出力し終了コード1固定 — 実装コスト最小だが原因切り分け困難でNFR C.3.1.1(障害検知Lv3)未達
- **Option C**: 全エラーをRDBの共通errorsテーブルに記録しCLIは常に終了コード0を返す — SP-002（foreground結果限定応答）と矛盾するため不採用

**推奨理由**: high — arch-design.yaml CLP-002に具体的方針が明記済み

### 3: RDB 正規化レベル
- **Option A** (⭐推奨): 第3正規形を基本とし、Runner実行結果等のevent_snapshot型はhistory（追記専用）+snapshot（最新状態キャッシュ）に分離する非正規化を許容（LR-002/LR-007 Event/Snapshot併用パターン準拠） — 履歴の完全性と状態照会の高速化を両立
- **Option B**: 第3正規形を厳格維持しsnapshotテーブルを持たない — 正規化は最も厳格だがhang-detectorの頻繁なポーリングでhistory全走査が必要になりCLI応答10秒以内(CTP-009)を満たしにくい
- **Option C**: execution-spec.jsonの内容もRunner実行結果テーブルに冗長保持する積極的非正規化 — クエリは単純化するが実行設定変更時の整合性維持コストが増す

**推奨理由**: high — arch-design.yaml LR-002/LR-007に明記済みのパターンを踏襲

### 4: CLI コマンド命名規則
- **Option A** (⭐推奨): サブコマンド階層方式（例: `relaygate concurrent-run select-slot`）。design-event.yaml の route（`/cli/{セクション}/{操作}`）と1:1対応 — 既存デザインシステムのroute構造と一致させ仕様間の整合コストを最小化
- **Option B**: フラットな単一コマンド+オプション方式（例: `relaygate-select-slot`） — 実装は単純だが23コマンドがフラットに並び発見性が低い
- **Option C**: 環境変数駆動の単一エントリポイント — facade本体には近いが運用系コマンド（中止・リラン）まで環境変数駆動にすると誤操作リスクが増す

**推奨理由**: medium — design-event.yaml のroute構造から導出。ジョブスケジューラ起動対象（facade本体）と運用者操作コマンドの体系を区別する必要がある

## 採用一覧

### 採用済み（high/medium）
| # | 項目 | 採用値 | confidence | 推奨理由 | 他の選択肢 |
|---|------|--------|-----------|----------|-----------|
| 1 | API 設計方式 | CLIコマンド契約（cli-command-contract.yaml、openapi.yaml不生成） | high | プロジェクト背景の明示的制約 | Option B / C |
| 2 | エラーハンドリング戦略 | 終了コード規約+CLP-002準拠のログ集約 | high | arch-design.yaml CLP-002 | Option B / C |
| 3 | RDB正規化レベル | 3NF基本+Event/Snapshot併用パターン | high | arch-design.yaml LR-002/LR-007 | Option B / C |
| 4 | CLIコマンド命名規則 | サブコマンド階層方式（designのroute準拠） | medium | design-event.yaml route構造 | Option B / C |

### 仮採用（low・要確認）
なし

## 非同期イベント（AsyncAPI）

RDRA外部システム.tsv・arch-design.yamlのtechnology_candidatesにMQ/イベントバス系技術（Kafka, SQS, EventBridge等）の記載がなく、非同期連携はすべてRDBのlease/claim機構（ポーリング）とCronJob定期実行で実現される。パブリッシュ/サブスクライブ型のメッセージチャネルは存在しないため、`_cross-cutting/api/asyncapi.yaml` は生成しない。

## NFR 反映事項

- CLI応答10秒以内・スループット10TPS目安（CTP-009）→ 各tier-*.md のティア完了条件・データモデル変更にレスポンスタイム制約として反映
- 監査ログ（grade 3, CTP-005）→ 中止・リラン系UCのビジネスルールに「操作者・操作日時・対象run_idを含む監査ログとして記録する」を明記
- 認証方式（grade 3, CTP-001）→ SSH鍵認証+MFAをアクセス制御節に反映
- WAF/Webアプリケーション対策（grade 0）→ 該当なしとして扱う（Web UIなし）
