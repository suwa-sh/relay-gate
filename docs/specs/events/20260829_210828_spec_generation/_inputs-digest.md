# Spec 生成用 入力ダイジェスト

- 転写元: `docs/arch/latest/arch-design.yaml`（event_id: 20260817_152155_arch_infra_feedback）, `docs/nfr/latest/nfr-grade.yaml`（event_id: 20260817_144844_initial_nfr）
- 生成イベント: `20260817_155817_spec_generation`
- 重要注記（プロジェクト背景）: 本システムは Web UI を持たない CLI/バッチ運用基盤。arch-design.yaml の `system_architecture.tiers` に `tier-frontend` 系ティアは存在しない。API 設計は「CLI コマンド契約 + ファイル契約 + DB スキーマ」を正本として扱う。tier-facade / tier-worker の `technology_candidates` は REST/GraphQL/SPA 等の文言を含まないため、機械的なティア種別判定では「その他」になるが、責務上は facade が API 系（エントリポイント）、worker が非同期処理系に相当する。UC 単位 Spec 生成では、tier-facade / tier-worker を「API 系ティア」の tier-{tier_id}.md フォーマットを準用しつつ、「API 仕様」節を「CLI コマンド仕様」（コマンド名・引数・環境変数・終了コード・stdout/stderr 契約）に読み替えて生成する。tier-datastore / tier-external-integration は UC 単位では生成しない（cross-cutting 専用、spec-generate.md の注記どおり）。

## 転写済みセクションのチェックリスト

| セクション | 状態 |
|-----------|------|
| arch: system_architecture.tiers | 転写済み |
| arch: app_architecture.tier_layers | 転写済み |
| arch: data_architecture.entities | 転写済み |
| arch: data_architecture.storage_mapping | 転写済み（先頭数件のみ、残りは元ファイル参照） |
| arch: technology_context | 転写済み |
| arch: domain_architecture（境界づけられたコンテキスト・集約） | 転写済み |
| nfr: 可用性（A） エラーハンドリング/リトライに効く項目 | 転写済み（耐障害性・回復性の主要グレード） |
| nfr: 性能（B） ページネーション/キャッシュ/レスポンスタイムに効く項目 | 転写済み |
| nfr: 運用（C） 障害検知・監視・ログに効く項目 | 転写済み |
| nfr: セキュリティ（E） 認証・認可・PII に効く項目 | 転写済み |
| design: portals/screens/components/tokens | not_applicable（本ダイジェストでは転写しない。design-event.yaml を直接参照すること） |

---

## 1. technology_context（arch-design.yaml 7-18行目）

```yaml
technology_context:
  languages:
    - "Shell Script (POSIX/bash)"
    - "SQL"
  frameworks:
    - "なし（フレームワーク非使用。POSIX準拠シェルスクリプトによる直接実装）"
  constraints:
    - "エアギャップ環境のオンプレミスLinuxサーバへのデプロイ（インターネット接続なし・クラウドマネージドサービス利用なし）"
    - "ジョブスケジューラの既存ジョブ定義を変更しない（strangler facadeとして追加導入のみ）"
    - "Web UIを持たないCLI/バッチ運用中心"
    - "blue実装・green実装のいずれも改変せず、facade層のみで並行稼働・比較・切替を実現する"
    - "外部SaaS型の監視・アラーティングサービスはエアギャップ環境のため利用不可。閉域内監視基盤（ログ集約・可視化）の整備が前提となる（共有プラットフォーム未確定時は構造化ログ+logrotateによるローカル最小構成とする）"
```

## 2. domain_architecture（境界づけられたコンテキスト・集約仮説。arch-design.yaml 19-233行目）

- サブドメイン: SD-001 並行稼働実行(core), SD-002 クロスチェック検証(core), SD-003 実行監視(supporting), SD-004 実行制御(supporting)
- 境界づけられたコンテキスト:
  - BC-001 実行管理コンテキスト（owned_entity_ids: E-001, E-002／owned_buc_ids: 並行稼働実行フロー）
  - BC-002 速報クロスチェックコンテキスト（owned_entity_ids: E-003, E-004／owned_buc_ids: 速報クロスチェックフロー）
  - BC-003 確報クロスチェックコンテキスト（owned_entity_ids: E-005／owned_buc_ids: 確報クロスチェックフロー）
  - BC-004 異常監視コンテキスト（owned_entity_ids: E-006／owned_buc_ids: ハング監視フロー）
  - 注: 実行制御業務（blue中止/green中止/速報比較中止/確報比較中止/background側リランフロー）は related_buc_ids として SD-004 に属するが、専用の bounded_context は定義されていない。中止・リラン操作は対象エンティティ（E-002, E-003, E-005）を所有する BC-001/BC-002/BC-003 のユースケース層（usecase）が担当すると解釈する
- コンテキストマップ: CM-001 BC-001→BC-002 (OHS, upstream), CM-002 BC-001→BC-003 (OHS, upstream), CM-003 BC-001→BC-004 (OHS, upstream), CM-004 BC-002→BC-004 (customer_supplier, upstream)
- 集約仮説: AG-001 (BC-001/E-001, 不変条件: BLUE_MODE/GREEN_MODE同時foreground禁止・認証情報参照名のみ保存), AG-002 (BC-001/E-002, 不変条件: exitcode.txt有無・値で実行状態判定、ABORTEDは対話確認による明示遷移のみ), AG-003 (BC-002/E-003, member: E-004, 不変条件: lease失効かつ未着手はREQUESTEDへ差し戻し), AG-004 (BC-003/E-005, 不変条件: 確報比較は全量対象・応答はstdout/stderr/exitcodeの3項目のみ), AG-005 (BC-004/E-006, 不変条件: hang_detect_limit_minutes超過時のみハング疑い記録)

## 3. system_architecture.tiers（arch-design.yaml 235-420行目付近）

### tier-facade（facade実行ティア）
- description: ジョブスケジューラからJOB_IDと追加引数を受け取り、feature flag設定に基づきblue/greenのslotを選択・起動し、foreground roleの標準出力・標準エラー・終了コードのみをジョブスケジューラへ応答するCLIエントリポイント。BC-001（実行管理）を実装する
- technology_candidates: CLI実行基盤（シェルスクリプト）, SSH（対象実装の起動・作業ディレクトリ制御）
- 主要policy: SP-001 ジョブ定義非変更の原則／SP-002 foreground結果限定応答
- 主要rule: SR-001 排他的foreground制約（BLUE_MODE/GREEN_MODE同時foreground拒否）／SR-005 対応OS限定・Web UI非対応（Linux単一OS、ブラウザ対応・WAF対象外）

### tier-worker（バックエンドワーカーティア）
- description: background role実行、速報/確報クロスチェックの非同期実行、hang-detectorによる定期監視を担う。BC-002・BC-003・BC-004と、BC-001のbackground role実行部分を実装する
- technology_candidates: CronJob（cron/systemdタイマー等の定期実行機構）, CLI実行基盤（シェルスクリプト、RDBのlease/claimを用いたworkerプロセス）

### tier-datastore（データストアティア）※UC単位では生成しない
- description: execution-spec.json・Runner実行結果・速報/確報比較依頼・比較結果・ハング検知記録を保持する。RDBがジョブキュー（lease管理）と管理DB（実行系譜の照会）を兼ねる
- technology_candidates: RDB（ジョブキュー兼管理DB）, ファイルシステム（started-at.txt/stdout.log/stderr.log/exitcode.txt 等の実行ログ本体）

### tier-external-integration（外部連携ティア）※UC単位では生成しない
- description: ジョブスケジューラ・blue実装・green実装との連携アダプタ層。3種の外部システムそれぞれの起動・応答形式差異を吸収する
- technology_candidates: アダプタ（シェルスクリプト経由のプロセス起動・SSH）
- 主要policy: SP-006 Runner Result Contractへの変換（blue/green実装の実行結果を共通形式に標準化。Anti-Corruption Layer相当）

### cross_tier_policies（抜粋）
- CTP-002 アクセス制御: RBAC（OS/SSHレベルのユーザー・グループ権限とRDBのアクセス権限）。アクター種別ごとに操作分離
- CTP-004 実行系譜トレーサビリティ: run_id/parent_run_idを全ティア共通の相関IDとし、構造化ログの必須フィールドに含める
- CTP-005 監査ログ・操作ログ: 対話確認を経た中止操作（ABORTEDへの遷移）・リラン操作は、操作者・操作日時・対象run_idを含む監査ログとして記録
- CTP-006 冪等性方針: background側リランはexecution-spec.jsonの実行設定を保ったまま再実行。RDBのlease/claim機構とrun_id/parent_run_idの相関で重複起動を検知・防止
- CTP-009 性能・拡張性の設計方針: CLI応答は10秒以内、スループットは10TPS程度を目安

## 4. app_architecture.tier_layers（arch-design.yaml 502-739行目）

### tier-facade レイヤー構成
| layer id | 名前 | 責務（要約せず原文） |
|---|---|---|
| L-facade-presentation | プレゼンテーション層 | Driver Side の入出力。ジョブスケジューラからのJOB_ID・追加引数の解析、foreground role実行結果（標準出力・標準エラー・終了コード）のみへの整形出力 |
| L-facade-usecase | ユースケース層 | feature flag設定に基づくslot選択・起動制御、background role先行起動、foreground実行結果応答のフロー制御、トランザクション境界 |
| L-facade-domain | ドメイン層 | 実行設定（execution-spec.json）・実行状態（Runner実行結果）に関するビジネスルール。BLUE_MODE/GREEN_MODE排他制約、exitcode.txtの有無・値からの実行状態判定、ABORTEDへの明示的遷移制御 |
| L-facade-repository | リポジトリ層 | domainのデータアクセス方法。execution-spec.json（AG-002）・Runner実行結果（AG-001）のaggregate rootと1:1で定義し、gateway/adapterを利用して永続化・取得する ※原文ママ。arch-design.yaml 553行目の記述だが、同ファイルの domain_architecture.aggregate_hypotheses（本書53行目「AG-001 (BC-001/E-001, ...)」「AG-002 (BC-001/E-002, ...)」）とはAG-001/AG-002の対応が逆転しており、upstream側の表記揺れである。Spec側は aggregate_hypotheses の定義（AG-001=execution-spec.json, AG-002=Runner実行結果）を正として統一済み（Step6.5 C-001/S-009対応） |
| L-facade-gateway | ゲートウェイ層 | Driven Sideの入出力。RDBへのadapter（execution-spec.json/Runner実行結果テーブルと1:1）と、blue/green実装をSSH経由で起動するclient（Runner Result Contractへの変換を担う） |

主要ルール: LR-001 Aggregate Root対応、LR-002 Event/Snapshot併用パターン（repository.save は historyAdapter.insert + snapshotAdapter.upsert）、LR-003 冪等性の保証（run_idの一意性）、LP-001 入力バリデーション（CLI引数解析時点で全て検証）、LP-002 操作の監査ログ記録、LP-003 状態遷移の整合性保証、LP-004 ログ出力禁止（domain層）
cross_layer: CLP-002 エラーハンドリング伝播（domain例外はusecaseで集約キャッチし1回だけログ出力、presentationでCLI終了コードに変換、gatewayは技術例外としてスロー）

### tier-worker レイヤー構成
| layer id | 名前 | 責務（要約せず原文） |
|---|---|---|
| L-worker-presentation | プレゼンテーション層 | Driver Side の入出力。CronJob/定期実行のエントリポイント、RDBのlease/claim取得、ハング・異常検知結果の通知出力 |
| L-worker-usecase | ユースケース層 | 速報/確報クロスチェックの実行フロー制御、hang-detectorによるbackground実行異常の定期検知フロー制御、対話確認を伴う中止・リランのフロー制御、トランザクション境界 |
| L-worker-domain | ドメイン層 | 速報/確報比較依頼の状態遷移ルール、比較判定ロジック、hang_detect_limit_minutesに基づく異常検知しきい値判定 |
| L-worker-repository | リポジトリ層 | domainのデータアクセス方法。速報比較依頼（AG-003）・確報比較依頼（AG-004）・ハング検知記録（AG-005）のaggregate rootと1:1で定義 |
| L-worker-gateway | ゲートウェイ層 | Driven Sideの入出力。RDBへのadapter（速報/確報比較依頼、速報比較結果、ハング検知記録テーブルと1:1）と、比較対象データ取得・通知送信のclient |

主要ルール: LR-006 Aggregate Root対応、LR-007 Event/Snapshot併用パターン、LR-008 楽観ロック競合ログ（lease/claim更新時）、LP-005 キュー（lease）劣化ログ、LP-006 操作の監査ログ記録、LP-007 状態遷移の整合性保証、LP-008 ログ出力禁止（domain層）

## 5. data_architecture.entities（arch-design.yaml 740-1046行目）

| entity id | 名前 | model_type | 主属性 (name:type) | 関連 |
|---|---|---|---|---|
| E-001 | execution-spec.json | event | run_id:string(PK), parent_run_id:string(nullable), job_id:string, host:string, exec_user:string, script_path:string, work_dir:string, fixed_args:text(nullable), additional_args:text(nullable), job_map_version:string, impl_version:string, hang_detect_limit_minutes:integer, credential_ref:string(nullable) | 1:N→E-002, 1:N→E-003, 1:N→E-005, 1:N→E-006 |
| E-002 | Runner実行結果 | event_snapshot | run_id:string(PK), slot_type:string, role_type:string(PK), started_at:datetime, stdout_path:string(nullable), stderr_path:string(nullable), exit_code:integer(nullable), status:string | N:1→E-001 |
| E-003 | 速報比較依頼 | event_snapshot | run_id:string(PK), job_id:string, requested_at:datetime, status:string, lease_expires_at:datetime(nullable), worker_id:string(nullable) | N:1→E-001, N:1→E-002, 1:1→E-004 |
| E-004 | 速報比較結果 | event | run_id:string(PK), comparison_result:string(OK/NG), diff_count:integer, diff_detail_uri:string(nullable), completed_at:datetime | 1:1→E-003 |
| E-005 | 確報比較依頼 | event_snapshot | run_id:string(PK), target_date:date, status:string, lease_expires_at:datetime(nullable), worker_id:string(nullable), target_tables:text, target_files:text | N:1→E-001 |
| E-006 | ハング検知記録 | event | detection_id:string(PK), run_id:string, detection_type:string, detected_at:datetime, threshold_minutes:integer(nullable), slot_type:string(nullable), notify_target:string | N:1→E-001, N:1→E-002, N:1→E-004 |

storage_mapping: 全エンティティ storage_type=rdb（E-001〜E-005 は確認済み。E-006 は元ファイル参照）。E-002 の stdout/stderr 本体はファイルシステム上のログファイルをパス参照する。

## 6. NFR グレード抜粋（confidence とグレードは原文のまま）

### A. 可用性
- 運用時間（通常）: grade 5
- サービス切替時間: grade 3
- サーバ内の冗長化: grade 3
- 回線の冗長化: grade 2 / ネットワーク機器の冗長化: grade 2 / ストレージの冗長化: grade 2
- 災害対策の範囲: grade 2 / 業務継続の要否: grade 1
- RPO（目標復旧地点）: grade 1（reason: 「Step0確認(自動採用)でDRはRPO/RTO 24h許容と仮置きしたため」）
- RTO（目標復旧時間）: grade 1
- RLO（目標復旧レベル）: grade 2

### B. 性能・拡張性
- 同時アクセス数: grade 1（reason: 「利用者はエンタープライズの少人数運用者に限定され、Web UIを持たないCLI/バッチ運用のため一般的な同時アクセス概念が当てはまりにくく、保守的にLv1と推定」）
- オンラインリクエスト件数: grade 2
- バッチ処理件数: grade 2（reason: 「確報クロスチェックが全テーブル・全ファイルを対象とする日次バッチであるため」）
- レスポンスタイム: grade 2（reason: 「Web UIを持たないCLI起動のため一般的なオンラインレスポンス基準の直接適用は難しく、保守的に推定」。cross_tier_policies CTP-009 で「CLI応答は10秒以内」と具体化）
- スループット: grade 1（reason: 「CLI/バッチ中心のジョブ実行のため一般的なオンラインTPS概念は該当しにくく、保守的に推定」）
- バッチ処理時間: grade 2 / バッチ処理量: grade 2
- CPU/メモリ/ストレージ/ネットワーク拡張性: grade 1（エアギャップオンプレのためスケールアップ前提）

### C. 運用・保守性
- 運用監視時間: grade 5
- 監視範囲: grade 3 / 監視方式: grade 2 / 監視間隔: grade 2
- 障害検知方式: grade 3（自動検知+自動通知+自動記録、動的ログレベル変更の根拠）
- 障害通知方式: grade 2 / 障害復旧方式: grade 2
- ログ保管期間: grade 3（6ヶ月。cross_layer_policies CLP-003/CLP-006 で明記） / ログ種別: grade 3

### E. セキュリティ
- 認証方式: grade 3（reason: 「CLI/シェル実行環境における具体的な認証方式（SSH鍵等）の詳細がRDRAから判断できないため、モデルシステム2のデフォルト値を保守的に仮置き」）
- アクセス制御: grade 2（reason: 「アクター種別ごとに役割が分かれているが、権限制御方式自体はRDRAに明記がないため保守的に仮置き」）
- 利用制限: grade 1
- データ暗号化（保管時）: grade 1（reason: execution-spec.jsonは認証情報参照名のみ保存し実値は保存しない設計のため） / データ暗号化（通信時）: grade 2
- データマスキング: grade 1
- 監査ログ: grade 3（reason: 「run_id/parent_run_idによる実行系譜の追跡、および対話確認を経たABORTED遷移など操作記録の明確な要求があるため」）
- 不正監視: grade 1
- ファイアウォール: grade 2 / IDS/IPS: grade 1 / ネットワーク分離: grade 2（reason: 「インターネット接続なし・クラウドサービス利用なしが前提として明示されているため」）
- マルウェア対策: grade 1（reason: 「エアギャップ環境のためインターネット経由の自動定義ファイル更新が困難なため、モデルシステム2デフォルトより引き下げ」）
- WAF: grade 0（reason: 「Web UIを持たないCLI/バッチ運用のためWebアプリケーション対策の対象がない」） / Webアプリケーション対策: grade 0（reason: 「Web UIを持たないCLI/バッチ運用のため該当しない」）
