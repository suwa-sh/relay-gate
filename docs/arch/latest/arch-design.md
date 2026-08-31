# アーキテクチャ設計書

## 概要

| 項目 | 内容 |
|------|------|
| イベントID | 20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design |
| 作成日時 | 2026-08-30T20:24:27 |
| ソース | インフラ設計 20260830_190412_infra_product_design に基づくアーキテクチャフィードバック |
| 言語 | bash(シェルスクリプト。facade / runner / worker / 監視 / 復旧の全スクリプト), SQL(管理 DB のジョブキュー操作。RDB クライアント CLI 経由), JavaScript(CommonJS。BDD の step 定義のみ。実行時には使用しない) |
| フレームワーク | なし(フレームワーク非採用。bash 標準コマンド + ssh + RDB クライアント CLI + OS のメール送信コマンドで構成) |
| 技術的制約 | エアーギャップ環境のオンプレミス Linux。実行時にインターネット接続・外部 SaaS を要求しない, UI 画面を持たない。CLI(標準出力・標準エラー・終了コード)と定期ジョブとメール通知だけで動作する。presentation 系 tier(frontend / web / ui)は作らない, HTTP API は無い。IdP / API Gateway / 認可サービスは導入しない(SSH 鍵と OS 権限のみ), 方針資料の C2/C3/C4 構成(facade / slot runner / rapid-crosscheck runner・worker / final-crosscheck runner・worker / hang-detector / background-rerun / abort-*)と Runner Result Contract(stdout.log / stderr.log / exitcode.txt + execution-spec.json)を spec 都合で変更しない, 設定契約(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 適用文書)の設定所有区分を維持する, 管理 DB は RDB 1 種(ジョブキュー兼管理 DB)。速報側と確報側のデータモデルを分離する, 成果物に特定案件の固有名(製品名・サーバ名・業務名)を記載しない(中立表現), 実行履歴・監査の正本はジョブスケジューラ。relay-gate はファイル(成果物・実行ログ)と管理レコードを残すだけ |

## ドメインアーキテクチャ

### コンテキストマップ図

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

### サブドメイン分類

| ID | 名前 | 分類 | 投資方針 | 関連 BUC | confidence | 根拠 |
|----|------|:----:|---------|---------|:----------:|------|
| SD-001 | 実装切替(ストラングラーファサード) | core | 最優先で深いモデリングと継続的リファクタリングに投資。チーム最強の人材を配置 | 実装切替ジョブ実行フロー | 中 | システム概要が「feature flag 付きストラングラーファサード型の実行基盤」を目的そのものとしており、同一ジョブ定義から blue / green を並行稼働させ foreground 結果だけを中継する仕組みが差別化の核であるため |
| SD-002 | クロスチェック(整合性検証) | core | 最優先で深いモデリングと継続的リファクタリングに投資。チーム最強の人材を配置 | 速報クロスチェックフロー, 確報クロスチェックフロー | 中 | 並行稼働の目的は整合性を検証しながら段階的に切り替えることであり、速報(原因調査)と確報(リリース判断の正本)の二段構えの比較規約が基盤の価値を決めるため。比較ツール自体は外部システムに委譲する |
| SD-003 | background 実行の監視と復旧 | supporting | good enough な品質で安定運用。標準的なフレームワーク採用 | background 実行監視フロー, 実行中止フロー, background 側リランフロー | 中 | ジョブスケジューラのジョブステータスに現れない background 異常を補完する運用機能であり、監視は通知のみ・復旧は運用者判断という限定責務のため supporting とする |
| SD-004 | 適用構成の定義 | supporting | good enough な品質で安定運用。標準的なフレームワーク採用 | 適用構成定義フロー | 中 | feature flag・ジョブマップ・比較定義・適用文書の設定契約を保守する業務で、案件ごとの差し替えを支える。設定所有区分の分離が主要関心であり、差別化要因ではない |

### 境界づけられたコンテキスト (Bounded Context)

| ID | 名前 | 所属 SD | 所有 entity | 所有 BUC | チーム | confidence | 根拠 |
|----|------|:------:|-----------|---------|--------|:----------:|------|
| BC-001 | 並行稼働実行コンテキスト | SD-001 | E-009, E-010, E-011, E-012, E-013, E-014, E-025 | 実装切替ジョブ実行フロー | - | 中 | 状態モデル「並行稼働実行」「slot 実行」が独立して閉じ、facade と slot runner が扱う語彙(run / slot / mode / Runner Result)が他コンテキストと異なるため |
| BC-002 | 速報クロスチェックコンテキスト | SD-002 | E-015, E-016, E-017, E-018 | 速報クロスチェックフロー | - | 中 | 方針資料が「速報と確報の比較規約はそれぞれ別ドメインが所有する」と明示し、rapid_run / rapid_crosscheck_request / comparison_result のモデルが確報側と分離されているため |
| BC-003 | 確報クロスチェックコンテキスト | SD-002 | E-019, E-020 | 確報クロスチェックフロー | - | 中 | 条件「速報と確報のモデル分離」により final_crosscheck_request と対象カタログを用い、速報側の rapid_run / rapid_crosscheck_request を作成・変更しないと定義されているため独立 BC とする |
| BC-004 | 実行監視・復旧コンテキスト | SD-003 | E-021, E-022, E-023, E-024 | background 実行監視フロー, 実行中止フロー, background 側リランフロー | - | 中 | 状態モデル「監視状態」が独立し、hang-detector / background-rerun / abort-* が通常起動の facade から分離された運用スクリプト群として方針資料に定義されているため |
| BC-005 | 適用構成コンテキスト | SD-004 | E-001, E-002, E-003, E-004, E-005, E-006, E-007, E-008 | 適用構成定義フロー | - | 中 | 基盤適用設計者だけが扱う設定契約の語彙(feature flag / ジョブマップ / 比較定義 / 適用文書)で閉じており、実行系コンテキストは読み取り専用で従うため |

#### ユビキタス言語

**BC-001 並行稼働実行コンテキスト**

| 用語 | 定義 |
|------|------|
| run | 1 回の並行稼働。run_id で成果物・rapid_run・比較依頼を相関付ける。parent_run_id でリラン系譜を追跡する |
| slot | 実装系統(blue / green)の枠。feature flag で実行モード(foreground / background / off)を選ぶ。foreground は同時に 1 slot だけ |
| Runner Result | slot runner が成果物ディレクトリに残す stdout.log / stderr.log / exitcode.txt(+ started-at.txt)。外部 IF の正本 |
| execution-spec | run 開始時にジョブマップから解決して一度だけ確定保存する実行設定。以後のジョブマップ変更に影響されない |

**BC-002 速報クロスチェックコンテキスト**

| 用語 | 定義 |
|------|------|
| 完了通知 | blue / green runner が自系統の公開 function(blue-completed / green-completed)で送る一方向の完了結果。相手側の状態は判断しない |
| 両系成功 | blue と green の両方が exitcode 0 で完了した状態。このときに限り速報比較依頼を 1 件だけ作成する |
| 比較依頼 | 管理 DB 上のジョブキューのレコード。速報では run_id を主キーとし、worker が claim / lease で多重実行を防ぐ |

**BC-003 確報クロスチェックコンテキスト**

| 用語 | 定義 |
|------|------|
| 確報比較依頼 | business_date と対象カタログの版で登録する日次全量比較の依頼。runner が終端状態まで同期 polling し、保存済み stdout / stderr / exitcode だけを中継する |
| 対象カタログ | 全テーブル・全ファイルを target_type / target_identifier と版で定義する比較対象の一覧。リリース判断の正本となる比較範囲 |

**BC-004 実行監視・復旧コンテキスト**

| 用語 | 定義 |
|------|------|
| ハング疑い | exitcode.txt が未出力のまま started-at.txt からの経過時間が hang_detect_limit_minutes を超えた background role。warning で通知するが状態は変更しない |
| 明示中止 | 運用者がプロセス停止を自身で確認し、中止スクリプトに yes と答えて RUNNING を ABORTED へ更新すること。スクリプトはプロセスを停止しない |
| background 側リラン | 完了済みまたは明示中止済みの background slot / 速報比較依頼を、元の execution-spec.json から新しい run_id で再実行すること |

**BC-005 適用構成コンテキスト**

| 用語 | 定義 |
|------|------|
| feature flag | slot ごとの実行モード・runner 実体・RAPID_CROSSCHECK_MODE を切り替える正本。運用モード(並行稼働 / 単独本番 / 次世代並行稼働)を組み合わせで表現する |
| ジョブマップ | JOB_ID から実行先(ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes)を slot ごとに解決する正本 |
| 設定所有区分 | 各設定項目の正本をどこ(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 適用文書)が所有するかの区分 |

### コンテキストマップ

| ID | from BC | to BC | パターン | 方向 | 翻訳責務 | 統合イベント | confidence |
|----|---------|-------|:-------:|:----:|---------|--------------|:----------:|
| CM-001 | BC-001 | BC-005 | conformist | downstream | BC-001(並行稼働実行)は BC-005 の設定契約(feature flag / slot ジョブマップ)をそのまま読み込み従う。翻訳層は持たず、run 開始時に execution-spec.json へ確定保存することで以後の変更から隔離する | - | 中 |
| CM-002 | BC-001 | BC-002 | ohs | upstream | BC-001 が Runner Result Contract と完了通知の公開 function(blue-completed / green-completed)を公開言語として提供し、BC-002 が受け取る。runner は相手側の状態や比較依頼の要否を判断しない | blue-completed, green-completed | 中 |
| CM-003 | BC-002 | BC-003 | shared_kernel | symmetric | クロスチェック依頼のライフサイクル(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)、claim / lease 規則、比較ツール終了コード契約(0 / 3 / 6)を共有する。データモデル(レコード)は共有しない | - | 中 |
| CM-004 | BC-004 | BC-001 | conformist | downstream | BC-004(監視・復旧)は BC-001 の成果物(started-at.txt / exitcode.txt / execution-spec.json)と slot 実行・parallel_run の状態をそのまま読み、監視は通知のみ、中止は状態更新のみ、リランは execution-spec.json からの復元で新 run を作る | - | 中 |
| CM-005 | BC-004 | BC-002 | conformist | downstream | BC-004 は速報比較依頼の状態と終了コードを読み取り異常を通知し、abort-rapid-crosscheck で RUNNING を ABORTED に更新し、background-rerun(--role rapid-crosscheck)で新 run_id の速報比較依頼を作成する | - | 中 |
| CM-006 | BC-004 | BC-003 | conformist | downstream | BC-004 は abort-final-crosscheck で RUNNING の確報比較依頼を ABORTED に更新するだけ。確報の再実行はジョブスケジューラの正規ジョブに委ね、background-rerun の対象にしない | - | 中 |
| CM-007 | BC-002 | BC-005 | conformist | downstream | BC-002 は BC-005 のクロスチェックジョブマップ(job_id ごとの比較定義)を読み、比較ツールの起動コマンド・比較対象・オプションをそのまま用いる | - | 中 |
| CM-008 | BC-003 | BC-005 | conformist | downstream | BC-003 は BC-005 の対象カタログ(版付き)を読み、確報比較依頼に版を紐付けて全量比較の範囲を確定する | - | 中 |

### 集約境界の仮説

> 注: これらは戦略段階の仮説です。最終確定は dist-spec or ddd-tactical-implementation で行います。

| ID | BC | root entity | members | invariants | confidence | 備考 |
|----|----|-----------|---------|-----------|:----------:|------|
| AG-001 | BC-001 | E-013 | E-014, E-010, E-011, E-012 | • blue と green の両方が foreground の構成は許可しない(入力検証でエラー終了し、どの slot も起動しない)<br/>• background slot をすべて起動してから foreground slot を起動し、foreground の PID だけを待機する<br/>• execution-spec.json は run 開始時に一度だけ確定保存し、以後上書きしない。認証情報の値は保存しない<br/>• slot 実行終了時に stdout.log / stderr.log / exitcode.txt が揃う。exitcode.txt は数値 1 行で runner の終了コードと一致する<br/>• ジョブスケジューラへの応答は foreground slot の Runner Result のみ。background と速報の結果は反映しない | 低 | 仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。RAPID_CROSSCHECK_MODE=off では parallel_run を作成せず成果物ファイルだけで動作するため、root の永続化有無はモードに依存する |
| AG-002 | BC-002 | E-016 | E-015, E-017, E-018 | • blue と green の両方が成功(exitcode 0)したときに限り速報比較依頼を作成する<br/>• 1 つの run_id に対する速報比較依頼は完了順にかかわらず 1 件だけ(run_id 主キー)<br/>• claim 中(lease 有効)の依頼は他 worker が取得できない。lease 失効かつ未開始なら REQUESTED に戻す<br/>• 依頼状態は比較ツールの exitcode に従う(0=SUCCEEDED / 非 0・実行エラー=FAILED) | 低 | 仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。rapid_run と rapid_crosscheck_request を同一集約に置くか(両系成功→依頼作成の原子性)、依頼を別集約にするか(worker の claim 競合)は実装時に再判断する |
| AG-003 | BC-003 | E-019 | E-020 | • 確報比較依頼は business_date と対象カタログの版を持って REQUESTED で登録する<br/>• ジョブスケジューラへ返すのは保存済みの stdout / stderr / exitcode だけ。状態名や差分件数・レポート URI は返さない<br/>• rapid_run / rapid_crosscheck_request を作成・変更しない | 低 | 仮説。最終確定は dist-spec または ddd-tactical-implementation で行う |
| AG-004 | BC-004 | E-021 | E-022 | • 監視は monitor_status / hang_suspected_at / alerted_at を記録し通知するだけ。RUNNING を ABORTED にせず、プロセスを停止せず、新しい実行依頼を作成しない<br/>• hang_detect_limit_minutes が 0 の role と foreground role は検知対象外<br/>• ハング疑いは warning、background 実行エラーと速報クロスチェック異常は error | 低 | 仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。リラン指示・中止指示は状態更新の指示であり、集約というより並行稼働実行 / 依頼に対するコマンドとして扱う可能性が高い |
| AG-005 | BC-005 | E-003 | E-004 | • JOB_ID の行がジョブマップに存在するときのみ実行先を解決できる。未定義なら runner は非 0 の exitcode.txt と原因を含む stderr.log を出力する<br/>• 固定引数は JSON 配列で引数の数と空白・カンマを維持し、その後ろに PARAM を順序を変えずに連結する。空の固定引数は []<br/>• hang_detect_limit_minutes の変更は次回以降の run の execution-spec.json にのみ反映される | 低 | 仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。設定はファイルとして版管理されるため、集約というより不変の設定スナップショットとして扱う |

## システムアーキテクチャ

### システム構成図

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

### ティア構成

| ID | ティア名 | 説明 | テクノロジー候補 |
|-----|---------|------|----------------|
| tier-facade | facade / slot runner ティア | ジョブスケジューラの業務ジョブから JOB_ID [PARAM...] で同期起動される CLI。facade.sh が feature flag で slot と mode を選択し、blue / green slot runner を起動して foreground の Runner Result だけを中継する。slot runner はジョブマップで実行先を解決し、SSH で実装スクリプトを実行して Runner Result を出力し、速報有効時に完了通知を送る | シェルスクリプト CLI(bash), SSH クライアント(リモート実行ホストへの実装スクリプト起動), ローカル / 共有ファイルシステム(成果物ディレクトリ facade/<run_id>/), RDB クライアント CLI(速報有効時のみ parallel_run を作成) |
| tier-rapid-crosscheck | 速報クロスチェックティア | rapid-crosscheck-runner(dispatcher。runner から完了通知を受ける一回ごとの起動スクリプト)と rapid-crosscheck-worker(管理 DB のジョブキューを継続的に poll / claim し、比較ツールでジョブ単位比較を実行して結果を登録する worker)で構成する | シェルスクリプト CLI(bash。dispatcher は都度起動、worker は常駐ループまたは定期起動), RDB クライアント CLI(ジョブキュー: rapid_run / rapid_crosscheck_request / comparison_result), 比較ツール起動アダプタ(job_id ごとの比較定義に従うコマンド実行) |
| tier-final-crosscheck | 確報クロスチェックティア | ジョブスケジューラの別ジョブ定義から起動される final-crosscheck-runner(依頼登録 → 終端状態まで同期 polling → 保存済み結果の中継)と、DB セグメントで依頼を poll / claim して全テーブル・全ファイルの日次全量比較を実行する final-crosscheck-worker で構成する | シェルスクリプト CLI(bash。runner は都度起動、worker は DB セグメント上の常駐ループまたは定期起動), RDB クライアント CLI(ジョブキュー: final_crosscheck_request / 対象カタログ), 比較ツール起動アダプタ(対象カタログに基づく全量比較) |
| tier-ops | 実行監視・復旧ティア | hang-detector(ジョブスケジューラの定期ジョブ)、background-rerun(専用ジョブ)、abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck(運用者が配置ディレクトリから直接起動する対話 CLI)で構成する。監視は通知のみ、中止は状態更新のみ、リランは execution-spec.json からの復元で行う | シェルスクリプト CLI(bash。定期ジョブ / 専用ジョブ / 対話 CLI), OS 標準のメール送信コマンド(warning / error 通知), RDB クライアント CLI(監視記録・状態更新・parallel_run 作成), ファイルシステム走査(started-at.txt / exitcode.txt / execution-spec.json) |
| tier-datastore | データストアティア | 管理 DB(RDB。ジョブキュー兼管理 DB)、成果物ディレクトリ(facade/<run_id>/ 配下の Runner Result と execution-spec.json)、設定ファイル(feature flag / ジョブマップ / クロスチェックジョブマップ / 対象カタログ / 適用文書)、実行ログファイルで構成する | RDB(単一インスタンス。速報側と確報側のテーブルを分離), ローカル / 共有ファイルシステム(成果物ディレクトリ・設定ファイル・実行ログ) |

### facade / slot runner ティア (tier-facade) の方針・ルール

#### 方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SP-001 | facade の責務限定と slot 選択 | facade は JOB_ID [PARAM...] だけを受け取り、feature flag 設定を起動のたびに読み込んで blue / green slot ごとに foreground / background / off を選択する。比較対象や実装固有の起動方式は判断せず、設定された runner を起動するだけとする。off の slot は起動しない | 条件「facade の責務限定」「slot 起動可否判定」により、ジョブスケジューラ側の定義を実装非依存に保ち runner の差し替えだけで世代交代を可能にするため | 外部システム: ジョブスケジューラ, 情報: ジョブ起動要求, feature flag 設定, 条件: facade の責務限定, slot 起動可否判定, 実装固有事項の runner への閉じ込め, BUC: 実装切替ジョブ実行フロー | 高 |
| SP-002 | foreground slot 排他の入力検証 | blue と green の両方が foreground に設定された構成は入力検証で検出し、どの slot も起動せずエラー終了する。foreground は同時に 1 slot だけ許可する | 条件「foreground slot 排他」。ジョブスケジューラへ返す結果は 1 系統でなければならないため | 条件: foreground slot 排他, バリエーション: slot 実行モード, 運用モード | 高 |
| SP-003 | slot 起動順序と foreground 待機 | background の slot をすべて起動して PID と成果物ディレクトリを確定してから foreground slot を起動し、すべての slot 起動後に foreground の PID だけを待機する。並行稼働実行は STARTED から RUNNING へ遷移する | 条件「slot 起動順序」。foreground が長時間実行中でも background slot を同時に実行させるため | 条件: slot 起動順序, 状態: 並行稼働実行, slot 実行 | 高 |
| SP-004 | ジョブスケジューラ応答の無加工中継 | foreground slot の stdout.log / stderr.log / exitcode.txt をそのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ中継し、中継完了で並行稼働実行を COMPLETED にする。background slot と速報クロスチェックの結果は応答に含めず待機もしない | 条件「ジョブスケジューラ応答の決定」「速報結果の位置付け」。並行稼働中も単独本番中も運用者が同じ見え方で結果を判定できるようにするため | 条件: ジョブスケジューラ応答の決定, 速報結果の位置付け, 情報: ジョブスケジューラ応答, アクター: 運用者, NFR B.2.1.1 | 高 |
| SP-005 | 確報クロスチェックの非起動 | 確報クロスチェックの制御は feature flag に含めず、facade は確報クロスチェックを起動しない。確報はジョブスケジューラの別ジョブ定義から final-crosscheck-runner を直接起動する | 条件「確報クロスチェック非起動」。確報は日次処理後の別タイミングで全量比較を行うため | 条件: 確報クロスチェック非起動, バリエーション: ジョブスケジューラ起動ジョブ種別 | 高 |
| SP-006 | ジョブマップによる実行先解決と引数連結 | slot runner は自 slot のジョブマップに JOB_ID の行が存在するときのみ実行先(ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes)を解決する。固定引数(JSON 配列)の後ろに PARAM を順序を変えずに連結し、引数の数と空白・カンマを維持する。JOB_ID 未定義なら非 0 の exitcode.txt と原因を含む stderr.log を出力して終了する | 条件「ジョブマップ解決条件」「引数連結規則」。ジョブスケジューラ側の定義に実行先を持たせないため | 条件: ジョブマップ解決条件, 引数連結規則, 情報: ジョブマップ, slot runner 割当, 外部システム: リモート実行ホスト(SSH), 現行実装(blue), 新実装(green) | 高 |
| SP-007 | execution-spec の一度きりの確定保存 | run 開始時(並行稼働実行の STARTED 遷移時)に解決済みの実行設定・追加引数・マップ版・実装版・role ごとの hang_detect_limit_minutes を facade/<run_id>/execution-spec.json として一時ファイル経由で一度だけ保存する。以後ジョブマップを変更しても上書きしない。認証情報は値を保存せず参照名だけを保存する | 条件「実行設定の確定条件」「認証情報の非保存」。ハング検知の判定基準・リランの再現性・障害調査の根拠とするため | 条件: 実行設定の確定条件, 認証情報の非保存, 情報: 実行設定(execution-spec), NFR E.5.1.1, NFR E.6.1.1 | 高 |
| SP-008 | 速報クロスチェック有効判定と完了通知の系統独立 | RAPID_CROSSCHECK_MODE=on のときのみ facade が run_id を発行して parallel_run を作成し、runner は完了時に自系統の公開 function(blue-completed / green-completed)で run_id・job_id・結果を通知する。off のときは完了通知を送らず、速報管理 DB へ接続も書き込みもせず parallel_run も作成しない。runner は相手側の状態や比較依頼の要否を判断しない | 条件「速報クロスチェック有効判定」「完了通知の系統独立」。速報 DB 接続設定なしで slot 実行できるようにし、比較規約を rapid-crosscheck 側に閉じ込めるため | 条件: 速報クロスチェック有効判定, 完了通知の系統独立, 情報: 完了通知, 並行稼働実行(parallel_run), バリエーション: 速報クロスチェックモード | 高 |

#### ルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SR-001 | Runner Result 完備 | slot 実行が終了したとき成果物ディレクトリに stdout.log / stderr.log / exitcode.txt を揃える。exitcode.txt は数値 1 行で runner の終了コードと一致させる。起動失敗・ジョブマップ未定義・SSH 失敗でも可能な限り 3 ファイルを出力する。started-at.txt は起動時に出力する。exitcode.txt が 0 なら slot 実行を SUCCEEDED、非 0 なら FAILED とする | 条件「Runner Result 完備条件」。ジョブスケジューラ応答・完了通知・ハング検知・障害調査が同じ 3 ファイルを共通利用するため | 条件: Runner Result 完備条件, 情報: Runner Result, 状態: slot 実行, バリエーション: Runner Result 成果物種別 | 高 |
| SR-002 | 実装固有事項の runner への閉じ込め | 実装固有の起動方式・ホスト・OS・プロトコル・SSH 接続方法は slot の runner 実体スクリプトに閉じ込める。facade と速報 / 確報の比較規約、ハング検知、リラン、中止の各スクリプトは runner を差し替えても変更しない | 条件「実装固有事項の runner への閉じ込め」と NFR F.1.1.1(実装側の OS 差異は runner に閉じ込める)への対応 | 条件: 実装固有事項の runner への閉じ込め, 情報: slot runner 割当, 適用構成文書, NFR F.1.1.1, NFR D.2.1.1 | 高 |

### 速報クロスチェックティア (tier-rapid-crosscheck) の方針・ルール

#### 方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SP-009 | 両系成功判定と比較依頼の一意作成 | dispatcher は完了通知を受けて rapid_run の blue_status / green_status を更新し、blue と green の両方が成功(exitcode 0)で完了したときに限り、完了順にかかわらず run_id を主キーとする速報比較依頼を 1 件だけ REQUESTED で作成する。いずれかが失敗した場合は作成しない | 条件「両系成功判定」「比較依頼の一意性」。失敗結果同士や片方失敗の比較と重複作成を防ぐため | 条件: 両系成功判定, 比較依頼の一意性, 状態: 速報実行の完了状況, 情報: 速報実行(rapid_run), 速報比較依頼(rapid_crosscheck_request), BUC: 速報クロスチェックフロー | 高 |
| SP-010 | worker の poll / claim / lease による多重実行防止 | worker は管理 DB を poll し、REQUESTED の依頼を worker_id と lease_until 付きで CLAIMED にする。lease 有効中は他の worker が同じ依頼を取得できない。lease が失効しかつ比較が未開始なら REQUESTED に戻し、別の worker が再取得できるようにする。worker はサーバ追加で水平に増やせる | 条件「claim 排他」「lease 失効判定」と NFR B.3.1.1(スケールアウト)への対応 | 条件: claim 排他, lease 失効判定, 状態: クロスチェック依頼, NFR B.3.1.1, NFR B.1.2.1 | 高 |
| SP-011 | 比較定義に従うジョブ単位比較と結果登録 | claim した worker は依頼を RUNNING にし、クロスチェックジョブマップの job_id ごとの比較定義に従って比較ツールでジョブ単位比較を実行する。比較ツールの stdout / stderr / exitcode を依頼に保存し、exitcode 0 で SUCCEEDED、非 0(3=比較 NG / 6=実行エラー)または実行エラーで FAILED とし、comparison_result を登録する | 条件「比較定義の選択」「依頼状態遷移規則」「比較ツール終了コードの対応」。比較実装は外部ツールに委譲し、規約だけを worker に閉じ込めるため | 条件: 比較定義の選択, 依頼状態遷移規則, 比較ツール終了コードの対応, 外部システム: 比較ツール, 情報: 比較定義, 比較結果(comparison_result), 比較ツール実行結果 | 高 |
| SP-012 | 速報結果の位置付け(原因調査用) | 速報クロスチェックの exitcode や失敗は通常業務ジョブの結果としてジョブスケジューラへ返さない。比較結果(comparison_result)と依頼の stdout / stderr / exitcode は運用者が run_id で参照し、両実装の差分の原因調査に使う。リリース判断の正本には用いない | 条件「速報結果の位置付け」。速報は非同期の background 処理であり本番結果に影響させないため | 条件: 速報結果の位置付け, アクター: 運用者, バリエーション: 比較結果ステータス, クロスチェック種別 | 高 |

#### ルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SR-003 | 速報側データモデルの所有 | rapid_run / rapid_crosscheck_request / comparison_result は速報クロスチェックティアだけが作成・更新する。確報側および facade は参照・作成しない(facade は parallel_run のみ作成する) | 方針資料「速報と確報の比較規約はそれぞれ別ドメインが所有する」への対応 | 条件: 速報と確報のモデル分離, 外部システム: 管理 DB(RDB) | 高 |

### 確報クロスチェックティア (tier-final-crosscheck) の方針・ルール

#### 方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SP-013 | 確報比較依頼の登録と同期 polling | runner はジョブスケジューラから起動されたとき business_date と対象カタログの版を持つ確報比較依頼を REQUESTED で登録し、SUCCEEDED / FAILED / ABORTED の終端状態になるまで同期 polling する。日次確報は夜間バッチウィンドウ内(8 時間以内)に完了させる | 条件「確報依頼の登録条件」と NFR B.2.2.1(バッチ処理時間)への対応 | 条件: 確報依頼の登録条件, 情報: 確報比較依頼(final_crosscheck_request), 対象カタログ, 外部システム: ジョブスケジューラ, BUC: 確報クロスチェックフロー, NFR B.2.2.1 | 高 |
| SP-014 | 確報結果の無加工中継 | runner は依頼に保存された stdout / stderr / exitcode だけをそのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ返す。チェック結果・差分件数・レポート URI などの追加連携データや依頼の状態名は返さない。比較 OK=0 / 比較 NG=3(警告終了) / 実行エラー=6(エラー終了)の終了コードをそのまま中継する | 条件「確報結果の中継制約」「比較ツール終了コードの対応」。ジョブスケジューラ側の判定を比較ツールの終了コード契約に委ねるため | 条件: 確報結果の中継制約, 比較ツール終了コードの対応, 外部システム: 比較ツール, バリエーション: 比較ツール終了コード, アクター: 運用者 | 高 |
| SP-015 | 確報 worker の DB セグメント実行と claim / lease | worker は DB セグメントで管理 DB を poll し、REQUESTED の確報比較依頼を worker_id と lease_until 付きで CLAIMED にし、RUNNING で対象カタログに従う全量比較を実行して stdout / stderr / exitcode を保存する。lease 失効かつ未開始なら REQUESTED に戻す規則は速報と同一とする | 条件「依頼状態遷移規則」「claim 排他」「lease 失効判定」。DB セグメント経由の配置制約を worker 側に閉じ込めるため | 条件: 依頼状態遷移規則, claim 排他, lease 失効判定, 状態: クロスチェック依頼, 情報: 比較ツール実行結果, 適用構成文書 | 高 |

#### ルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SR-004 | 速報と確報のモデル分離 | 確報クロスチェックは final_crosscheck_request と対象カタログだけを用い、rapid_run / rapid_crosscheck_request を作成・変更しない。確報の再実行はジョブスケジューラの正規ジョブを直接再実行し、background-rerun を使わない | 条件「速報と確報のモデル分離」「復旧手段の選択」への対応 | 条件: 速報と確報のモデル分離, 復旧手段の選択, バリエーション: 再実行経路 | 高 |

### 実行監視・復旧ティア (tier-ops) の方針・ルール

#### 方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SP-016 | ハング検知判定と対象除外 | 定期ジョブ(5 分ごとなど)として未完了の background role を走査し、started-at.txt と execution-spec.json の hang_detect_limit_minutes から経過時間を判定する。exitcode.txt があり 0 なら対象外、非 0 なら background 実行エラーとして通知、無く上限以内なら継続監視、上限超過ならハング疑いとして通知する。hang_detect_limit_minutes が 0 の role と foreground role は検知対象から除外する。RAPID_CROSSCHECK_MODE=off でも管理 DB なしで slot 成果物ファイルだけを走査する | 条件「ハング検知判定」「ハング検知対象の除外」と NFR C.1.3.1(アプリケーション監視)・C.3.1.1(自動検知+自動通知+自動記録)への対応 | 条件: ハング検知判定, ハング検知対象の除外, 状態: 監視状態, 情報: 監視記録, BUC: background 実行監視フロー, NFR C.1.3.1, NFR C.3.1.1, NFR C.1.1.1 | 高 |
| SP-017 | 速報比較依頼の異常判定 | 速報比較依頼が FAILED または比較 NG のとき速報クロスチェック異常として通知し、RUNNING のときは状態を変更せずハング疑いとして通知する | 条件「速報比較依頼の異常判定」。ジョブスケジューラ応答に現れない速報異常を見落とさないため | 条件: 速報比較依頼の異常判定, バリエーション: 速報クロスチェック監視判定 | 高 |
| SP-018 | 監視は通知のみ・通知レベル・警告傾向の記録 | 監視は monitor_status / hang_suspected_at / alerted_at を記録して運用者へメール通知するだけとし、RUNNING を ABORTED にせず、プロセスを停止せず、新しい実行依頼を作成しない。ハング疑いは warning、background 実行エラーと速報クロスチェック異常は error で送る。通知後に正常終了した実行についても警告時の経過時間を記録し、hang_detect_limit_minutes の調整根拠にする | 条件「監視は通知のみ」「通知レベルの判定」「警告傾向の記録」。静観か対処かの判断を運用者に委ねるため | 条件: 監視は通知のみ, 通知レベルの判定, 警告傾向の記録, 外部システム: メール通知, 情報: 通知メール, アクター: 運用者, NFR C.5.1.1 | 高 |
| SP-019 | ハング検知上限の調整基準 | hang_detect_limit_minutes は導入時に全ジョブ 60 分とし、正常終了パターンの警告が出そろった時点で運用者がジョブごとに最後の警告の経過時間を基準に調整する。変更は次回以降の run の execution-spec.json にのみ反映される | 条件「ハング検知上限の調整基準」への対応 | 条件: ハング検知上限の調整基準, 情報: ハング検知上限設定, バリエーション: ハング検知上限設定 | 高 |
| SP-020 | background 側リランの事前検証と復元 | background-rerun は --source-run-id と --role を受け、元の execution-spec.json と管理 DB の状態を事前検証する。--role blue / green は元の slot mode が background のときだけ新しい run_id で再実行し、foreground または off ならエラー終了する。--role rapid-crosscheck は業務ジョブを再実行せず速報比較依頼だけを新規作成する。未対応の role、元の実行が見つからない、元の実行が RUNNING または中止未確認ならエラー終了する。最新のジョブマップは再解決せず、元の execution-spec.json から実行パラメータ・ホスト・実行ユーザー・スクリプト・作業ディレクトリを復元する。新しい parallel_run の parent_run_id には直前のリラン元 run_id を設定する | 条件「リラン事前検証」「リランの実行設定復元」「リラン系譜の追跡」と NFR A.4.1.1 / A.4.1.2(execution-spec と Runner Result からの復旧)への対応 | 条件: リラン事前検証, リランの実行設定復元, リラン系譜の追跡, 情報: リラン指示, BUC: background 側リランフロー, NFR A.4.1.1, NFR A.4.1.2 | 高 |
| SP-021 | 復旧手段の選択 | background slot 実行と速報比較依頼は専用ジョブの background-rerun で再実行し、foreground slot 実行と確報クロスチェックはジョブスケジューラの正規ジョブを直接再実行する。RUNNING の background 実行は運用者が明示中止してからリランする | 条件「復旧手段の選択」への対応 | 条件: 復旧手段の選択, バリエーション: 再実行経路, リラン対象 role | 高 |
| SP-022 | 中止スクリプトの可否判定と停止確認応答 | abort-blue / abort-green は対象 slot が background かつ RUNNING のときだけ、abort-rapid-crosscheck / abort-final-crosscheck は対象の比較依頼が RUNNING のときだけ ABORTED へ遷移できる。それ以外は状態を変更せずエラー終了する。現在状態を表示後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と対話確認し、yes のときだけ状態を更新し、並行稼働実行も ABORTED にする。スクリプト自身はプロセス・Pod・SSH 接続先の処理を停止しない。指示者と応答は実行ログに残す | 条件「slot 中止可否判定」「依頼中止可否判定」「停止確認応答」と NFR E.7.1.1(運用操作の記録)への対応 | 条件: slot 中止可否判定, 依頼中止可否判定, 停止確認応答, 情報: 中止指示, BUC: 実行中止フロー, 状態: slot 実行, 並行稼働実行, クロスチェック依頼, NFR E.7.1.1 | 高 |

#### ルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SR-005 | 監視・復旧スクリプトの facade からの分離 | hang-detector / background-rerun / abort-* は通常起動の facade から分離し、ジョブスケジューラの別ジョブ定義または運用者の直接起動で動かす。facade の実行経路にこれらの処理を混ぜない | 方針資料「ハング監視と background 側の選択リランは通常起動の facade から分離する」への対応 | バリエーション: ジョブスケジューラ起動ジョブ種別, 外部システム: ジョブスケジューラ | 高 |

### データストアティア (tier-datastore) の方針・ルール

#### 方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SP-023 | 管理 DB をジョブキューとして使う | MQ を導入せず、管理 DB の依頼レコード(rapid_crosscheck_request / final_crosscheck_request)を worker が poll / claim するジョブキューとして使う。速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)のテーブルを分離し、監視記録もここに保持する | 外部システム「管理 DB(RDB)」がジョブキュー兼管理 DB と定義され、NFR B.2.1.2(〜10 TPS)の低頻度書き込みで十分なため。エアーギャップ環境で追加ミドルウェアを増やさない | 外部システム: 管理 DB(RDB), 条件: 速報と確報のモデル分離, claim 排他, NFR B.2.1.2, NFR B.1.1.1, NFR B.1.1.3 | 高 |
| SP-024 | 成果物ファイルを外部 IF の正本にする | Runner Result(started-at.txt / stdout.log / stderr.log / exitcode.txt)と execution-spec.json はファイルとして成果物ディレクトリに残し、ジョブスケジューラ応答・完了通知・ハング検知・リラン・障害調査が共通に参照する。RAPID_CROSSCHECK_MODE=off では管理 DB なしにファイルだけで slot 実行・監視・リランが成立する | Runner Result Contract と条件「実行履歴はジョブスケジューラの責務」への対応。DB 喪失時も execution-spec.json と Runner Result からリランできる(NFR A.3.1.1 / A.4.1.1) | 情報: Runner Result, 実行設定(execution-spec), 条件: 実行履歴はジョブスケジューラの責務, NFR A.3.1.1, NFR A.3.1.2, NFR A.4.1.1 | 高 |
| SP-025 | 設定所有区分に基づく設定ファイル配置 | 実装スロットと runner の割当は feature flag、実行先とハング検知上限は該当 slot のジョブマップ、比較対象と対象カタログはクロスチェックジョブマップ、外部 IF 方針・ネットワーク制約・ホスト配置は適用文書が所有する。各設定は版(設定版 / マップ版 / 実装版 / カタログ版 / 文書版)を持つファイルとして適用側が管理する | 条件「設定所有区分」「適用側で定義する事項」への対応。正本を一意に定め、relay-gate のスクリプトを変更せずに案件・世代を切り替えるため | 条件: 設定所有区分, 適用側で定義する事項, 情報: feature flag 設定, ジョブマップ, クロスチェックジョブマップ, 適用構成文書, アクター: 基盤適用設計者, BUC: 適用構成定義フロー | 高 |
| SP-026 | バックアップと復旧地点 | 管理 DB は日次のフル+差分バックアップを取り、数時間以内の復旧地点(RPO)と半日以内の復旧(RTO)を目標にする。成果物ディレクトリと管理 DB は最低限のミラーリング(RAID1 相当)に置く。遠隔地の災害対策は基盤単体では持たない | NFR C.1.2.1(フル+差分バックアップ日次)、A.4.1.1(RPO 数時間)、A.4.1.2(RTO 半日)、A.2.5.1(ストレージ冗長化)、A.3.1.1(災害対策なし)への対応 | NFR C.1.2.1, NFR A.4.1.1, NFR A.4.1.2, NFR A.2.5.1, NFR A.3.1.1, NFR A.2.1.1 | 中 |

#### ルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| SR-006 | 機密データ非保持 | 管理 DB と成果物には認証情報の値を保存しない(参照名のみ)。保管時暗号化は要求しない。成果物の stdout / stderr に業務データが含まれるかは適用側で確認し、必要ならファイルシステムの OS 権限で保護する | 条件「認証情報の非保存」と NFR E.6.1.1(保管時暗号化なし)・E.5.2.1(OS 権限によるアクセス制御)への対応 | 条件: 認証情報の非保存, NFR E.6.1.1, NFR E.5.2.1 | 高 |

### ティア共通の方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CTP-001 | CLI と定期ジョブとメールだけの提示(UI 画面なし) | すべてのスクリプトは CLI として起動され、結果を標準出力・標準エラー・終了コードで返す。運用者への通知はメールで行う。UI 画面・HTTP API・Web ブラウザ対応・WAF は対象外とする。起動口はジョブスケジューラのジョブ定義(業務ジョブ facade / 確報クロスチェックジョブ / ハング検知定期ジョブ / background リラン専用ジョブ)と運用者の直接起動(abort-*)に限る | 条件「CLI とメールによる提示」と NFR F.1.1.2(ブラウザ対象外)・E.10.1.1(WAF なし)・B.1.1.1 / B.1.1.3(少人数の CLI と定期ジョブのみ)への対応 | 条件: CLI とメールによる提示, 外部システム: ジョブスケジューラ, メール通知, アクター: 運用者, バリエーション: ジョブスケジューラ起動ジョブ種別, NFR F.1.1.2, NFR E.10.1.1, NFR B.1.1.1, NFR B.1.1.3 | 高 |
| CTP-002 | 認証・アクセス制御: SSH 鍵と OS 権限のみ | IdP / API Gateway / 認可サービスは導入しない。実行先ホストへは ジョブマップで解決した実行ユーザーで SSH 鍵認証により接続し、管理 DB 接続は閉域セグメント内で行う。認可はジョブマップの実行ユーザーとスクリプト・成果物ディレクトリの OS 権限で行う。認証情報は値ではなく参照名で扱う | NFR E.5.1.1(OS アカウントと SSH 鍵)、E.5.2.1(ユーザ単位の OS 権限)、E.6.1.2(SSH 経路のみ暗号化)への対応。アクターは社内 2 種のみでロール概念が無い | 外部システム: リモート実行ホスト(SSH), 管理 DB(RDB), アクター: 運用者, 基盤適用設計者, 条件: 認証情報の非保存, NFR E.5.1.1, NFR E.5.2.1, NFR E.6.1.2 | 高 |
| CTP-003 | run_id 相関と実行ログ方針 | 全スクリプトは run_id をキーにした実行ログ(スクリプト名 / run_id / 出力日時 / ログレベル / メッセージ)をファイルに残す。中止・リランの運用操作は指示者と応答を含めて記録し、状態遷移は管理レコードに残す。実行履歴・監査の正本はジョブスケジューラとし、relay-gate のログは障害調査と警告傾向の確認用として 3 ヶ月保管する。parent_run_id の数珠つなぎでリラン系譜を追跡できるようにする | 条件「実行履歴はジョブスケジューラの責務」「リラン系譜の追跡」と NFR C.6.1.1(ログ保管 3 ヶ月)・E.7.1.1(監査ログ)への対応 | 情報: 実行ログ, 条件: 実行履歴はジョブスケジューラの責務, リラン系譜の追跡, 外部システム: ジョブスケジューラ, NFR C.6.1.1, NFR E.7.1.1 | 高 |
| CTP-004 | 多重実行防止と再実行の再現性 | 速報比較依頼は run_id 主キーで 1 件だけ作成する。worker の claim は worker_id と lease_until で排他する。リランは常に新しい run_id を発行し、元の execution-spec.json から復元する(最新ジョブマップを再解決しない)。成果物は一時ファイルへ出力してから確定名へリネームし、書き込み途中の読み取りを防ぐ | 条件「比較依頼の一意性」「claim 排他」「実行設定の確定条件」「成果物公開判定」への対応。ピーク時に blue / green と速報が同時実行されても重複処理を起こさないため | 条件: 比較依頼の一意性, claim 排他, 実行設定の確定条件, 成果物公開判定, NFR B.1.2.1, NFR B.3.1.1 | 高 |
| CTP-005 | エアーギャップ環境のセキュリティ運用 | 実行時にインターネット接続・外部 SaaS を要求しない。組織のセキュリティポリシーに準拠し、セキュリティパッチとウイルス定義はオフラインで持ち込み随時適用する。外部公開面が無いためセキュリティ診断は行わず、簡易チェックリストでリスク確認する。ファイアウォールはパケットフィルタリング、インシデント対応は基本的な連絡体制とする。ネットワーク制約は適用文書が所有する | NFR E.1.1.1、E.2.1.1、E.3.1.1、E.8.1.1、E.9.1.1、E.11.1.1、C.2.1.2 への対応 | 情報: 適用構成文書, NFR E.1.1.1, NFR E.2.1.1, NFR E.3.1.1, NFR E.8.1.1, NFR E.9.1.1, NFR E.11.1.1, NFR C.2.1.2 | 中 |
| CTP-006 | 可用性と計画停止 | ほぼ終日稼働で 1 時間程度の停止のみ許容し、計画停止はジョブスケジューラの実行計画(夜間バッチ・日次確報)と調整して事前通知つきで不定期に行う。facade / runner はジョブスケジューラの実行ホスト上で動作し、管理 DB は単一 RDB 構成で電源・ディスクの部品冗長化に留める。ネットワーク機器・電源の冗長化は適用側の設置環境に従う。業務継続は業務実装側・ジョブスケジューラ側の計画に従い、基盤単体の継続要件は持たない | NFR A.1.1.1、A.1.1.3、A.2.1.1、A.2.3.1、A.2.6.2、A.3.1.2、C.1.1.1 への対応 | 外部システム: ジョブスケジューラ, NFR A.1.1.1, NFR A.1.1.3, NFR A.2.1.1, NFR A.2.3.1, NFR A.2.6.2, NFR A.3.1.2, NFR C.1.1.1 | 中 |
| CTP-007 | 性能方針: 基盤オーバーヘッドの限定 | facade の起動・中継、中止 / リラン CLI の応答は 10 秒以内を目標にし、業務ジョブ本体の処理時間は実装側の責務とする。管理 DB の書き込みはジョブ起動・完了通知・claim・監視記録の低頻度(〜10 TPS)に収める。性能テストは relay-gate のオーバーヘッド(起動・中継・poll)の単体確認に限定する | NFR B.2.1.1、B.2.1.2、B.4.1.1、B.1.2.1 への対応 | NFR B.2.1.1, NFR B.2.1.2, NFR B.4.1.1, NFR B.1.2.1, NFR B.2.2.1 | 中 |
| CTP-008 | 導入・切替方針 | relay-gate 自体はジョブスケジューラのジョブ定義を facade 呼び出しへ置き換えて一括導入する(移行データなし・リハーサルなし)。業務実装の切替は feature flag の運用モード(並行稼働 → 新実装の単独本番 → 次世代実装との並行稼働)の段階切替で行い、blue foreground / green off から始める。feature flag・ジョブマップ・比較定義の切替は本番縮小構成のテスト環境で事前検証する | NFR D.2.1.1、D.4.1.1、D.5.1.1、C.4.1.1 への対応。BUC「適用構成定義フロー」の切り替え後の運用 | BUC: 適用構成定義フロー, バリエーション: 運用モード, アクター: 基盤適用設計者, NFR D.2.1.1, NFR D.4.1.1, NFR D.5.1.1, NFR C.4.1.1 | 高 |
| CTP-009 | 運用体制 | 運用サポートは営業時間内(9 時〜17 時)を基本とし、夜間バッチの異常メールの受け手は運用体制で定める。ハング検知の定期ジョブが稼働中は常時監視する | NFR C.5.1.1、C.1.1.1 への対応。要確認項目として NFR 側で仮採用されている | アクター: 運用者, NFR C.5.1.1, NFR C.1.1.1 | 低 |
| CTP-010 | SLI/SLOベースのオブザーバビリティ方針 | 可用性・レイテンシ・エラー率・スループットの4指標をSLIとして定義し、月次エラーバジェットで運用する。facade起動・中継オーバーヘッドのp99レイテンシ、日次確報クロスチェックの夜間バッチウィンドウ8時間以内完了、月次エラー率5%未満をSLOとして持つ。ダッシュボードは新規構築せず組織既存監視への統合と運用者向け日次メールサマリーで代替する | インフラ設計(MCL product-design)の結果に基づく: product-observability.yamlのSLI/SLO定義をアーキテクチャレベルの方針として明示化する。CTP-007(性能方針)を補強するオブザーバビリティ観点 | infra: product-observability.yaml → sli, slo, alerting | 中 |
| CTP-011 | コスト最適化方針(既存ホスト相乗り) | 既存のジョブスケジューラ実行ホストと管理DBホストへ相乗りし、新規ホスト・商用ライセンス・監視基盤の追加投資を最小化する。オートスケール基盤は導入せず、水平スケールが必要な場合はホスト追加による手動対応とする | インフラ設計(MCL product-design)の結果に基づく: product-cost-hints.yamlのcost_posture: cost_optimizedとrightsizing/autoscaling方針をアーキテクチャレベルの方針として明示化する | infra: product-cost-hints.yaml → recommendations | 中 |

### ティア共通のルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CTR-001 | Runner Result Contract の厳守 | 成果物は <FACADE_RUN_DIR>/execution-spec.json と <FACADE_RUN_DIR>/<role>/{started-at.txt, stdout.log, stderr.log, exitcode.txt} の構成を守る。exitcode.txt は数値だけを 1 行で保持し runner の終了コードと一致させる。実行終了後に 3 ファイルを揃えて公開する。一時ファイルへ出力してから確定名へリネームし、確定名のファイルが存在するときのみ書き込み完了とみなす | 条件「Runner Result 完備条件」「成果物公開判定」。外部 IF の正本として全ティアが共通に参照するため | 条件: Runner Result 完備条件, 成果物公開判定, 情報: Runner Result, バリエーション: Runner Result 成果物種別, run role(成果物ディレクトリ区分) | 高 |
| CTR-002 | 終了コード規約 | 各スクリプトの終了コードは stdout / stderr と共に契約として扱う。業務ジョブは foreground slot の exitcode.txt をそのまま返す。比較ツールの終了コード(0=比較 OK / 3=比較 NG / 6=実行エラー)は依頼状態(0=SUCCEEDED / 非 0=FAILED)に対応させ、確報ではそのまま中継する。入力検証エラー・事前検証エラー・中止不可は非 0 で終了し、原因を stderr に出す | 条件「比較ツール終了コードの対応」「ジョブスケジューラ応答の決定」への対応 | 条件: 比較ツール終了コードの対応, ジョブスケジューラ応答の決定, 外部システム: 比較ツール, ジョブスケジューラ | 高 |
| CTR-003 | 外部システム連携は gateway 層のアダプタに閉じ込める | リモート実行ホスト(SSH)、比較ツール、メール通知、管理 DB(RDB)への接続・呼び出しは各ティアの gateway 層のアダプタスクリプトに閉じ込め、usecase / domain から直接コマンドを呼ばない。RDB 製品固有の SQL 方言・クライアント CLI の差異はアダプタで吸収する | 外部システムが 7 種あり、比較ツールや RDB 製品の差し替えに備えるため。一般的なベストプラクティスとして適用 | 外部システム: リモート実行ホスト(SSH), 比較ツール, メール通知, 管理 DB(RDB), 現行実装(blue), 新実装(green) | デフォルト |
| CTR-004 | 中立表現と案件固有事項の非記載 | スクリプト・設定サンプル・ドキュメントには特定案件の固有名(製品名・サーバ名・業務名)を記載しない。案件固有事項は適用文書・ジョブマップ・runner 実体に置く | MIT の OSS として公開するため。条件「適用側で定義する事項」への対応 | 条件: 適用側で定義する事項, 情報: 適用構成文書 | 高 |
| CTR-005 | 実装言語と実行環境 | 実装は bash シェルスクリプトとし、単一 OS(オンプレミス Linux)で動作させる。コードの識別子・エラーメッセージ・ログは英語、コメントは日本語とする。BDD の step 定義のみ JavaScript(CommonJS)を用いる | NFR F.1.1.1(単一 OS)とユーザー指定の実装規約への対応 | NFR F.1.1.1 | ユーザー指定 |
| CTR-006 | オンプレミス代替構成における手動運用への配慮 | 自動スケール・自動フェイルオーバー・オブジェクトストレージのライフサイクル管理はオンプレミス構成では持たない(OS標準機能による手動水平スケール、単一インスタンスDBの手動復旧、ファイル領域での手動ローテーション)。運用手順書にホスト追加・障害復旧・保持期間超過分削除の手動手順を明記し、自動化が無いことを前提にした運用体制を組む | インフラ設計(MCL product-design)の結果に基づく: product-mapping-onprem.yamlでfidelity=\"partial\"と評価された箇所(実行基盤・管理DB・成果物ストレージ・バックアップ監視)に共通する制約をクロスティアルールとして明示化する | infra: product-mapping-onprem.yaml → mappings[].fidelity=partial | 中 |

## アプリケーションアーキテクチャ

### tier-facade のレイヤー構成

#### レイヤー依存図

```mermaid
graph TD
P[presentation: facade.sh / runner CLI] --> U[usecase: slot 起動フロー]
U --> D[domain: 判定表・状態遷移]
U --> R[repository: parallel_run / execution-spec / Runner Result / 設定]
R --> D
R --> G[gateway: SSH / filesystem / RDB / completed 通知]
```

| ID | レイヤー名 | 責務 | 依存許可先 |
|-----|---------|------|----------|
| L-facade-presentation | プレゼンテーション層(CLI エントリ) | facade.sh / blue-runner / green-runner の CLI 入口。JOB_ID [PARAM...] と feature flag の入力検証(foreground slot 排他を含む)、終了コードの決定、foreground の Runner Result の標準出力・標準エラー・終了コードへの無加工中継 | L-facade-usecase |
| L-facade-usecase | ユースケース層 | slot 起動フロー(background 起動 → foreground 起動 → foreground 待機 → 中継)、run_id 発行と parallel_run 作成(速報有効時のみ)、実行先解決 → execution-spec 確定保存 → 実装実行 → Runner Result 公開 → 完了通知のフロー制御 | L-facade-domain, L-facade-repository |
| L-facade-domain | ドメイン層 | slot 実行モードの判定表(起動可否・foreground 排他)、並行稼働実行と slot 実行の状態遷移、引数連結規則、exitcode → SUCCEEDED / FAILED の判定など、副作用を持たない純粋関数 | - |
| L-facade-repository | リポジトリ層 | parallel_run(管理 DB)、execution-spec / Runner Result(成果物ディレクトリ)、feature flag / ジョブマップ(設定ファイル)の読み書きを集約単位で提供する | L-facade-domain, L-facade-gateway |
| L-facade-gateway | ゲートウェイ層 | SSH アダプタ(リモート実行ホストで実装スクリプトを作業ディレクトリ・引数付きで実行)、ファイルシステムアダプタ(一時ファイル書き込みとリネーム、started-at.txt / exitcode.txt 出力)、RDB クライアントアダプタ、rapid-crosscheck-runner 呼び出しアダプタ(blue-completed / green-completed) | - |

#### プレゼンテーション層(CLI エントリ) (L-facade-presentation) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-001 | 入力検証で拒否する構成 | 両 slot foreground、未知の実行モード、JOB_ID 欠落は入力検証でエラー終了し、どの slot も起動しない。原因は stderr に英語で出す | 条件「foreground slot 排他」への対応 | 条件: foreground slot 排他, 情報: ジョブ起動要求 | 高 |
| LP-002 | 応答の無加工中継 | presentation は foreground の stdout.log / stderr.log / exitcode.txt を加工せず中継する。background slot と速報の結果は応答に反映しない | 条件「ジョブスケジューラ応答の決定」への対応 | 条件: ジョブスケジューラ応答の決定, 情報: ジョブスケジューラ応答 | 高 |

#### ユースケース層 (L-facade-usecase) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-003 | 起動順序の固定 | usecase は background slot をすべて起動して PID と成果物ディレクトリを確定してから foreground slot を起動し、foreground の PID だけを待機する | 条件「slot 起動順序」への対応 | 条件: slot 起動順序, 状態: 並行稼働実行 | 高 |
| LP-004 | 速報有効時のみ管理 DB に触れる | RAPID_CROSSCHECK_MODE=off のとき usecase は parallel_run 作成・完了通知を行わず、管理 DB の repository を呼ばない | 条件「速報クロスチェック有効判定」への対応 | 条件: 速報クロスチェック有効判定, 完了通知の系統独立 | 高 |

#### ドメイン層 (L-facade-domain) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-005 | 状態遷移と判定表をドメインに集約 | STARTED → RUNNING → COMPLETED / ABORTED、RUNNING → SUCCEEDED / FAILED / ABORTED の遷移と、slot 起動可否・引数連結規則の判定はドメイン層の関数として実装し、テスト可能にする。ドメイン層は直接ログ出力を行わない | 条件「slot 起動可否判定」「引数連結規則」と状態モデル「並行稼働実行」「slot 実行」への対応 | 条件: slot 起動可否判定, 引数連結規則, 状態: 並行稼働実行, slot 実行 | 高 |

#### リポジトリ層 (L-facade-repository) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-006 | execution-spec の一度きり保存 | repository は execution-spec.json を一時ファイル → リネームで一度だけ作成し、既存ファイルがあれば上書きしない。認証情報は参照名のみを書く | 条件「実行設定の確定条件」「認証情報の非保存」「成果物公開判定」への対応 | 条件: 実行設定の確定条件, 認証情報の非保存, 成果物公開判定, 情報: 実行設定(execution-spec) | 高 |

#### ゲートウェイ層 (L-facade-gateway) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-007 | 異常時も 3 ファイルを揃える | SSH 失敗・起動失敗・ジョブマップ未定義でも gateway は可能な限り stdout.log / stderr.log / exitcode.txt を出力し、失敗理由を stderr.log に残す | 条件「Runner Result 完備条件」「ジョブマップ解決条件」への対応 | 条件: Runner Result 完備条件, ジョブマップ解決条件, 外部システム: リモート実行ホスト(SSH) | 高 |

#### レイヤー共通の方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLP-001 | IF なし(直接依存) | レイヤー間は bash の source による関数呼び出しで直接依存し、抽象 IF は置かない。RDB 製品や比較ツールの差し替えは gateway アダプタの差し替えで吸収する | シェルスクリプトであり抽象化の手段が限られるため。一般的なベストプラクティスとして適用 | なし | デフォルト |
| CLP-002 | 実行ログの出力方針 | usecase 層が run_id 付きの実行ログ(スクリプト名 / run_id / 日時 / レベル / メッセージ)をファイルへ出力する集約ポイントとする。gateway は外部呼び出し(SSH / RDB / 比較ツール / メール)の開始・終了・所要時間・成否を記録し、失敗は技術例外として非 0 で返す。domain 層はログを出さない。ログ出力先は stdout / stderr を汚さない専用ファイルとし、TZ は UTC に統一する | NFR C.6.1.1(ログ保管)・C.3.1.1(自動記録)・E.7.1.1(監査)への対応 | 情報: 実行ログ, NFR C.6.1.1, NFR C.3.1.1, NFR E.7.1.1 | 中 |

#### レイヤー共通のルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLR-001 | エラーハンドリングと終了コード | set -euo pipefail を基本とし、domain / repository / gateway のエラーは usecase で 1 回だけログ出力して presentation へ返し、presentation が終了コードを決める。catch の握り潰しと多重ログを禁止する | レイヤー責務の分離。一般的なベストプラクティスとして適用 | なし | デフォルト |

### tier-rapid-crosscheck のレイヤー構成

#### レイヤー依存図

```mermaid
graph TD
P[presentation: blue-completed / green-completed / worker 起動口] --> U[usecase: dispatcher / worker フロー]
U --> D[domain: 両系成功判定・依頼ライフサイクル]
U --> R[repository: rapid_run / request / comparison_result / 比較定義]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

| ID | レイヤー名 | 責務 | 依存許可先 |
|-----|---------|------|----------|
| L-rapid-presentation | プレゼンテーション層(CLI エントリ) | rapid-crosscheck-runner の公開 function(blue-completed / green-completed)の引数検証と、rapid-crosscheck-worker の起動口(poll ループ / 1 回実行)。終了コードの決定 | L-rapid-usecase |
| L-rapid-usecase | ユースケース層 | 完了通知の登録 → 両系成功判定 → 比較依頼の一意作成(dispatcher)、poll → claim → RUNNING → 比較実行 → 結果保存 → comparison_result 登録(worker)のフロー制御 | L-rapid-domain, L-rapid-repository |
| L-rapid-domain | ドメイン層 | 速報実行の完了状況(両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み)の遷移、クロスチェック依頼のライフサイクル、lease 失効判定、比較ツール終了コード → 依頼状態の対応表 | - |
| L-rapid-repository | リポジトリ層 | rapid_run / rapid_crosscheck_request / comparison_result の読み書き(管理 DB)、クロスチェックジョブマップの比較定義の読み取り(設定ファイル) | L-rapid-domain, L-rapid-gateway |
| L-rapid-gateway | ゲートウェイ層 | RDB クライアントアダプタ(poll / claim の条件付き UPDATE)、比較ツール起動アダプタ(比較定義のコマンドを実行し stdout / stderr / exitcode を取得) | - |

#### プレゼンテーション層(CLI エントリ) (L-rapid-presentation) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-008 | 系統ごとの公開 function | 完了通知の受け口は blue-completed / green-completed の 2 つに分け、run_id・job_id・終了コード・成果物ディレクトリ(artifact_uri)を受け取る | 条件「完了通知の系統独立」への対応 | 条件: 完了通知の系統独立, 情報: 完了通知 | 高 |

#### ユースケース層 (L-rapid-usecase) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-009 | 依頼作成と claim の原子性 | 両系成功 → 比較依頼作成、REQUESTED → CLAIMED の遷移は 1 トランザクション(条件付き UPDATE / INSERT)で行い、重複作成と二重 claim を防ぐ | 条件「比較依頼の一意性」「claim 排他」への対応 | 条件: 比較依頼の一意性, claim 排他, 状態: 速報実行の完了状況 | 高 |

#### ドメイン層 (L-rapid-domain) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-010 | 両系成功判定表 | blue の結果 × green の結果の表で成功 × 成功のみ両系成功とする。exitcode 0 = SUCCEEDED / 3・6・その他非 0 = FAILED の対応表もドメインに置く | 条件「両系成功判定」「比較ツール終了コードの対応」「依頼状態遷移規則」「lease 失効判定」への対応 | 条件: 両系成功判定, 比較ツール終了コードの対応, 依頼状態遷移規則, lease 失効判定, 状態: 速報実行の完了状況, クロスチェック依頼 | 高 |

#### ゲートウェイ層 (L-rapid-gateway) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-011 | 比較ツール呼び出しの分離 | 比較ツールの起動コマンド・オプションは job_id ごとの比較定義から受け取り、gateway は実行と結果取得だけを行う。ツール固有の終了コード解釈は domain の対応表に委ねる | 条件「比較定義の選択」への対応。比較ツールを差し替え可能にするため | 条件: 比較定義の選択, 外部システム: 比較ツール, 情報: 比較定義 | 高 |

#### レイヤー共通の方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLP-003 | IF なし(直接依存) | tier-facade と同じく直接依存とし、gateway アダプタの差し替えで製品差異を吸収する | 一般的なベストプラクティスとして適用 | なし | デフォルト |
| CLP-004 | 実行ログの出力方針 | tier-facade の CLP-002 と同一。worker は claim した依頼の run_id と worker_id をログに含める | NFR C.6.1.1・C.3.1.1 への対応 | 情報: 実行ログ, NFR C.6.1.1, NFR C.3.1.1 | 中 |

#### レイヤー共通のルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLR-002 | エラーハンドリングと終了コード | tier-facade の CLR-001 と同一。比較ツールの非 0 は例外ではなく結果として扱い FAILED を保存する | レイヤー責務の分離 | 条件: 比較ツール終了コードの対応 | デフォルト |

### tier-final-crosscheck のレイヤー構成

#### レイヤー依存図

```mermaid
graph TD
P[presentation: final runner / worker 起動口] --> U[usecase: 登録・polling・中継 / 比較実行]
U --> D[domain: 依頼ライフサイクル・終了コード対応]
U --> R[repository: final_crosscheck_request / 対象カタログ]
R --> D
R --> G[gateway: RDB / 比較ツール]
```

| ID | レイヤー名 | 責務 | 依存許可先 |
|-----|---------|------|----------|
| L-final-presentation | プレゼンテーション層(CLI エントリ) | final-crosscheck-runner の起動口(business_date・対象カタログ版の引数検証)と worker の起動口。保存済み stdout / stderr / exitcode の無加工中継と終了コードの決定 | L-final-usecase |
| L-final-usecase | ユースケース層 | 依頼登録 → 終端状態までの同期 polling → 結果中継(runner)、poll → claim → RUNNING → 全量比較 → 結果保存(worker)のフロー制御 | L-final-domain, L-final-repository |
| L-final-domain | ドメイン層 | クロスチェック依頼のライフサイクル(速報と共有する規則)、lease 失効判定、比較ツール終了コード → 依頼状態の対応表、終端状態の判定 | - |
| L-final-repository | リポジトリ層 | final_crosscheck_request と対象カタログの読み書き(管理 DB)。速報側のテーブルには触れない | L-final-domain, L-final-gateway |
| L-final-gateway | ゲートウェイ層 | RDB クライアントアダプタ(DB セグメントからの poll / claim)、比較ツール起動アダプタ(対象カタログに基づく全テーブル・全ファイル比較) | - |

#### プレゼンテーション層(CLI エントリ) (L-final-presentation) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-012 | 中継制約 | presentation は依頼に保存された stdout / stderr / exitcode だけを返し、状態名・差分件数・レポート URI を出力に追加しない | 条件「確報結果の中継制約」への対応 | 条件: 確報結果の中継制約, 情報: ジョブスケジューラ応答 | 高 |

#### ユースケース層 (L-final-usecase) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-013 | 同期 polling の間隔と上限 | runner は終端状態まで一定間隔で polling し、夜間ウィンドウ(8 時間)を超える場合の扱いは設定で指定できるようにする。polling 中は状態を変更しない | 条件「確報依頼の登録条件」と NFR B.2.2.1 への対応 | 条件: 確報依頼の登録条件, NFR B.2.2.1 | 中 |

#### ドメイン層 (L-final-domain) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-014 | 依頼ライフサイクル規則の共有 | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED の遷移規則と終了コード対応表は速報側と同一の規則として実装し、レコードは final_crosscheck_request に分離する | 条件「依頼状態遷移規則」「速報と確報のモデル分離」への対応 | 条件: 依頼状態遷移規則, 速報と確報のモデル分離, 状態: クロスチェック依頼 | 高 |

#### ゲートウェイ層 (L-final-gateway) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-015 | 対象カタログに基づく全量比較の起動 | gateway は対象カタログ(target_type / target_identifier / 比較条件 / business_date の扱い)を比較ツールの入力に変換して起動し、stdout / stderr / exitcode を取得する | 条件「適用側で定義する事項」への対応 | 条件: 適用側で定義する事項, 情報: 対象カタログ, 外部システム: 比較ツール | 高 |

#### レイヤー共通の方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLP-005 | IF なし(直接依存) | tier-facade と同じく直接依存とする | 一般的なベストプラクティスとして適用 | なし | デフォルト |
| CLP-006 | 実行ログの出力方針 | tier-facade の CLP-002 と同一。final_crosscheck_id と business_date をログに含める | NFR C.6.1.1・C.3.1.1 への対応 | 情報: 実行ログ, NFR C.6.1.1, NFR C.3.1.1 | 中 |

#### レイヤー共通のルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLR-003 | エラーハンドリングと終了コード | tier-facade の CLR-001 と同一。依頼登録失敗・polling 中の DB 障害は非 0 で終了し原因を stderr に出す | レイヤー責務の分離 | なし | デフォルト |

### tier-ops のレイヤー構成

#### レイヤー依存図

```mermaid
graph TD
P[presentation: hang-detector / background-rerun / abort-* CLI] --> U[usecase: 監視・リラン・中止フロー]
U --> D[domain: 判定表・監視状態遷移]
U --> R[repository: 監視記録 / 状態 / 成果物 / execution-spec]
R --> D
R --> G[gateway: メール / RDB / filesystem / runner 起動]
```

| ID | レイヤー名 | 責務 | 依存許可先 |
|-----|---------|------|----------|
| L-ops-presentation | プレゼンテーション層(CLI エントリ) | hang-detector / background-rerun(--source-run-id, --role) / abort-*(--run-id)の引数検証、現在状態の表示、停止確認の対話プロンプト、終了コードの決定 | L-ops-usecase |
| L-ops-usecase | ユースケース層 | 監視走査 → 判定 → 監視記録保存 → 通知(hang-detector)、事前検証 → execution-spec 復元 → 新 run 作成 → background slot / 比較依頼の起動(background-rerun)、可否判定 → 状態更新(abort-*)のフロー制御 | L-ops-domain, L-ops-repository |
| L-ops-domain | ドメイン層 | ハング検知判定表(exitcode.txt の有無・値 × 経過時間と上限)、速報比較依頼の異常判定表、通知レベル対応表、監視状態の遷移、リラン事前検証表(role × 元 mode × 元状態)、中止可否判定表(mode × 状態)、復旧手段の選択表 | - |
| L-ops-repository | リポジトリ層 | 監視記録(管理 DB)、slot 実行・parallel_run・比較依頼の状態(管理 DB)、Runner Result / execution-spec.json(成果物ディレクトリ)、ハング検知上限設定(execution-spec 経由)の読み書き | L-ops-domain, L-ops-gateway |
| L-ops-gateway | ゲートウェイ層 | メール送信アダプタ(OS 標準コマンド。warning / error)、RDB クライアントアダプタ(条件付き UPDATE による ABORTED 遷移)、ファイルシステム走査アダプタ、slot runner / rapid-crosscheck-runner 起動アダプタ(リラン) | - |

#### プレゼンテーション層(CLI エントリ) (L-ops-presentation) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-016 | 停止確認の対話 | abort-* は現在状態を表示後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と確認し、yes 以外は状態を変更せず終了する | 条件「停止確認応答」への対応 | 条件: 停止確認応答, 情報: 中止指示, バリエーション: 停止確認応答 | 高 |

#### ユースケース層 (L-ops-usecase) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-017 | 監視は通知のみ | hang-detector の usecase は状態更新・プロセス停止・依頼作成を呼ばない。監視記録の保存とメール送信だけを行う | 条件「監視は通知のみ」「警告傾向の記録」への対応 | 条件: 監視は通知のみ, 警告傾向の記録, 状態: 監視状態 | 高 |
| LP-018 | リランの復元元の固定 | background-rerun の usecase は最新ジョブマップの repository を呼ばず、元 run の execution-spec.json からのみ実行設定を復元し、新 run_id の parallel_run に parent_run_id を設定する | 条件「リランの実行設定復元」「リラン系譜の追跡」「リラン事前検証」への対応 | 条件: リランの実行設定復元, リラン系譜の追跡, リラン事前検証, 情報: リラン指示 | 高 |

#### ドメイン層 (L-ops-domain) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-019 | 判定表をドメインに集約 | ハング検知判定・対象除外・異常判定・通知レベル・リラン事前検証・中止可否・復旧手段の各判定表を純粋関数として実装し、テスト可能にする | 条件「ハング検知判定」「ハング検知対象の除外」「速報比較依頼の異常判定」「通知レベルの判定」「リラン事前検証」「slot 中止可否判定」「依頼中止可否判定」「復旧手段の選択」への対応 | 条件: ハング検知判定, ハング検知対象の除外, 速報比較依頼の異常判定, 通知レベルの判定, リラン事前検証, slot 中止可否判定, 依頼中止可否判定, 復旧手段の選択, 状態: 監視状態 | 高 |

#### リポジトリ層 (L-ops-repository) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-020 | 管理 DB なしでの監視 | RAPID_CROSSCHECK_MODE=off のとき repository は管理 DB に接続せず、成果物ディレクトリの走査だけで監視対象を列挙する | 条件「ハング検知判定」と方針資料「off の場合も slot 成果物だけで監視」への対応 | 条件: ハング検知判定, 速報クロスチェック有効判定, 情報: 監視記録, ハング検知上限設定 | 高 |

#### ゲートウェイ層 (L-ops-gateway) の方針・ルール

**方針**

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| LP-021 | 条件付き状態更新 | ABORTED への更新は WHERE 句で現在状態(RUNNING かつ background)を条件にし、競合時は更新件数 0 をエラーとして返す | 条件「slot 中止可否判定」「依頼中止可否判定」への対応。二重実行を防ぐため | 条件: slot 中止可否判定, 依頼中止可否判定, 外部システム: 管理 DB(RDB), メール通知 | 高 |

#### レイヤー共通の方針

| ID | 方針名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLP-007 | IF なし(直接依存) | tier-facade と同じく直接依存とする | 一般的なベストプラクティスとして適用 | なし | デフォルト |
| CLP-008 | 運用操作の記録 | 中止・リランの運用操作は指示者(実行ユーザー)・応答・対象 run_id・role を実行ログに残し、監視記録には monitor_status / hang_suspected_at / alerted_at / 警告時経過時間を残す | 条件「警告傾向の記録」と NFR E.7.1.1(監査ログ)・C.3.1.1(自動記録)への対応 | 条件: 警告傾向の記録, 情報: 実行ログ, 監視記録, NFR E.7.1.1, NFR C.3.1.1, NFR C.6.1.1 | 高 |

#### レイヤー共通のルール

| ID | ルール名 | 内容 | 根拠 | RDRA/NFR 要素 | 確信度 |
|-----|---------|------|------|--------------|:------:|
| CLR-004 | エラーハンドリングと終了コード | tier-facade の CLR-001 と同一。事前検証エラー・中止不可は状態を変更せず非 0 で終了し、原因を stderr に出す | レイヤー責務の分離 | なし | デフォルト |

## データアーキテクチャ

### ER 図

```mermaid
erDiagram
FEATURE_FLAG ||--o{ SLOT_RUNNER_ASSIGNMENT : owns
SLOT_RUNNER_ASSIGNMENT ||--|| JOB_MAP : refers
JOB_MAP ||--o{ HANG_DETECT_LIMIT : owns
JOB_MAP ||--o{ EXECUTION_SPEC : resolved_into
CROSSCHECK_JOB_MAP ||--o{ COMPARISON_DEFINITION : holds
CROSSCHECK_JOB_MAP ||--|| TARGET_CATALOG : refers
JOB_LAUNCH_REQUEST ||--|| PARALLEL_RUN : starts
PARALLEL_RUN ||--|| EXECUTION_SPEC : refers
PARALLEL_RUN ||--o{ SLOT_EXECUTION : has
PARALLEL_RUN o|--o| PARALLEL_RUN : parent_run_id
SLOT_EXECUTION ||--|| RUNNER_RESULT : outputs
RUNNER_RESULT ||--o| SCHEDULER_RESPONSE : relayed_as
SLOT_EXECUTION ||--o| COMPLETION_NOTICE : sends
COMPLETION_NOTICE }o--|| RAPID_RUN : aggregated_into
PARALLEL_RUN ||--o| RAPID_RUN : correlates
RAPID_RUN ||--o| RAPID_CROSSCHECK_REQUEST : requests
RAPID_CROSSCHECK_REQUEST }o--|| COMPARISON_DEFINITION : follows
RAPID_CROSSCHECK_REQUEST ||--o{ COMPARISON_RESULT : produces
RAPID_CROSSCHECK_REQUEST ||--o| TOOL_RESULT : stores
TARGET_CATALOG ||--o{ FINAL_CROSSCHECK_REQUEST : versioned_for
FINAL_CROSSCHECK_REQUEST ||--o| TOOL_RESULT : stores
FINAL_CROSSCHECK_REQUEST ||--o| SCHEDULER_RESPONSE : relayed_as
SLOT_EXECUTION ||--o{ MONITOR_RECORD : monitored_by
RAPID_CROSSCHECK_REQUEST ||--o{ MONITOR_RECORD : monitored_by
MONITOR_RECORD ||--o{ NOTIFICATION_MAIL : sends
EXECUTION_SPEC ||--o{ RERUN_INSTRUCTION : restored_from
RERUN_INSTRUCTION ||--|| PARALLEL_RUN : creates
ABORT_INSTRUCTION }o--o| SLOT_EXECUTION : aborts
ABORT_INSTRUCTION }o--o| RAPID_CROSSCHECK_REQUEST : aborts
ABORT_INSTRUCTION }o--o| FINAL_CROSSCHECK_REQUEST : aborts
EXECUTION_LOG }o--o| PARALLEL_RUN : traces
```

### エンティティ一覧

#### E-001: feature flag 設定

- **参照元**: 情報: feature flag 設定
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| config_version | string | 設定版 | No | Yes |
| blue_mode | string | blue slot 実行モード(foreground / background / off) | No |  |
| green_mode | string | green slot 実行モード(foreground / background / off) | No |  |
| blue_runner | string | blue runner 実体スクリプトパス | No |  |
| green_runner | string | green runner 実体スクリプトパス | No |  |
| rapid_crosscheck_mode | string | RAPID_CROSSCHECK_MODE(on / off) | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-002 | 1:N | feature flag が slot ごとの runner 割当を所有する |

#### E-002: slot runner 割当

- **参照元**: 情報: slot runner 割当
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| slot | string | slot(blue / green) | No | Yes |
| runner_script_path | string | runner 実体スクリプトパス | No |  |
| job_map_location | string | 対応するジョブマップの所在 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-003 | 1:1 | slot の runner が参照するジョブマップ |

#### E-003: ジョブマップ

- **参照元**: 情報: ジョブマップ
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| slot | string | slot(blue / green) | No | Yes |
| job_id | string | JOB_ID | No | Yes |
| host | string | 実行先ホスト | No |  |
| exec_user | string | 実行ユーザー | No |  |
| script_path | string | 実装スクリプトパス | No |  |
| work_dir | string | 作業ディレクトリ | No |  |
| fixed_args | text | 固定引数(JSON 配列。空は []) | No |  |
| credential_ref | string | 認証情報参照名(値は保持しない) | Yes |  |
| map_version | string | マップ版 | No |  |
| impl_version | string | 実装版 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-004 | 1:N | role ごとの hang_detect_limit_minutes を所有する |
| E-010 | 1:N | run 開始時に実行設定として確定保存される |

#### E-004: ハング検知上限設定

- **参照元**: 情報: ハング検知上限設定
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| job_id | string | JOB_ID | No | Yes |
| role | string | role(blue / green / rapid-crosscheck) | No | Yes |
| hang_detect_limit_minutes | integer | ハング疑いの判定上限(導入時 60。foreground role は 0 で対象外) | No |  |
| adjusted_at | datetime | 調整日時 | Yes |  |
| adjustment_basis | text | 調整根拠(最後の警告の経過時間) | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-021 | 1:N | 監視記録の警告時経過時間を調整根拠にする |

#### E-005: 適用構成文書

- **参照元**: 情報: 適用構成文書
- **モデル種別**: リソース

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| project_id | string | 案件識別 | No | Yes |
| document_version | string | 文書版 | No | Yes |
| external_if_policy | text | 外部 IF の送受信方針 | Yes |  |
| network_constraints | text | ネットワーク制約 | Yes |  |
| host_placement | text | ホスト配置・実行ユーザー方針・DB セグメント構成 | Yes |  |
| runner_location | text | runner 実体の所在 | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-003 | 1:N | 案件固有事項がジョブマップ定義の根拠となる |

#### E-006: 比較定義

- **参照元**: 情報: 比較定義
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| job_id | string | JOB_ID | No | Yes |
| definition_version | string | 定義版 | No | Yes |
| comparison_type | string | 比較種別 | No |  |
| targets | text | 比較対象(テーブル・ファイル) | No |  |
| tool_command | string | 比較ツール起動コマンド | No |  |
| tool_options | text | 比較オプション | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-007 | N:1 | クロスチェックジョブマップに属する |

#### E-007: クロスチェックジョブマップ

- **参照元**: 情報: クロスチェックジョブマップ
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| map_version | string | マップ版 | No | Yes |
| target_list | text | 比較対象一覧 | No |  |
| catalog_ref | string | 対象カタログ参照(版) | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-006 | 1:N | job_id ごとの比較定義を保持する |
| E-008 | 1:1 | 確報用の対象カタログを参照する |

#### E-008: 対象カタログ

- **参照元**: 情報: 対象カタログ
- **モデル種別**: リソース(SCD2)

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| catalog_version | string | カタログ版 | No | Yes |
| target_type | string | target_type(テーブル / ファイル) | No | Yes |
| target_identifier | string | target_identifier | No | Yes |
| comparison_condition | text | 比較条件 | Yes |  |
| business_date_handling | string | business_date の扱い | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-019 | 1:N | 確報比較依頼がカタログ版を紐付ける |

#### E-009: ジョブ起動要求

- **参照元**: 情報: ジョブ起動要求
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | 起動により発行された run_id(速報有効時) | No | Yes |
| job_id | string | JOB_ID | No |  |
| params | text | PARAM...(追加引数。順序保持) | No |  |
| source_job_definition | string | 起動元ジョブ定義 | Yes |  |
| occurred_at | datetime | 起動日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | 1:1 | 並行稼働実行を開始する |
| E-001 | N:1 | 起動時に読み込む feature flag |

#### E-010: 実行設定(execution-spec)

- **参照元**: 情報: 実行設定(execution-spec)
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| job_id | string | JOB_ID | No |  |
| slot | string | slot | No |  |
| role | string | role | No |  |
| host | string | ホスト | No |  |
| exec_user | string | 実行ユーザー | No |  |
| script_path | string | スクリプトパス | No |  |
| work_dir | string | 作業ディレクトリ | No |  |
| fixed_args | text | 固定引数 | No |  |
| params | text | 追加引数(PARAM) | No |  |
| map_version | string | マップ版 | No |  |
| impl_version | string | 実装版 | No |  |
| hang_detect_limits | text | role ごとの hang_detect_limit_minutes | No |  |
| credential_ref | string | 認証情報参照名(値は保存しない) | Yes |  |
| spec_uri | string | 保存先 URI(facade/<run_id>/execution-spec.json) | No |  |
| occurred_at | datetime | 確定保存日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | 1:1 | parallel_run.execution_spec_uri が参照する |
| E-003 | N:1 | 解決元のジョブマップ(版付き) |

#### E-011: Runner Result

- **参照元**: 情報: Runner Result
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| role | string | 成果物ディレクトリ区分(blue / green / rapid-crosscheck / final-crosscheck) | No | Yes |
| artifact_dir | string | 成果物ディレクトリ | No |  |
| started_at | datetime | started-at.txt(開始時刻) | No |  |
| stdout_path | string | stdout.log のパス | No |  |
| stderr_path | string | stderr.log のパス | No |  |
| exit_code | integer | exitcode.txt(数値 1 行) | No |  |
| finalized | boolean | 確定リネーム完了フラグ | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-014 | 1:1 | slot 実行の終了結果 |

#### E-012: ジョブスケジューラ応答

- **参照元**: 情報: ジョブスケジューラ応答
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id(または final_crosscheck_id) | No | Yes |
| stdout_source | string | 標準出力の中継元(foreground の stdout.log / 依頼の stdout) | No |  |
| stderr_source | string | 標準エラーの中継元 | No |  |
| exit_code | integer | 終了コード | No |  |
| occurred_at | datetime | 応答日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-011 | 1:1 | foreground の Runner Result を無加工で中継する |
| E-019 | N:1 | 確報では依頼に保存された結果を中継する |

#### E-013: 並行稼働実行(parallel_run)

- **参照元**: 情報: 並行稼働実行(parallel_run)
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| parent_run_id | string | リラン元 run_id(数珠つなぎ) | Yes |  |
| job_id | string | JOB_ID | No |  |
| parameters | text | parameters(JSON) | No |  |
| execution_spec_uri | string | execution-spec.json の URI | No |  |
| status | string | STARTED / RUNNING / COMPLETED / ABORTED | No |  |
| requested_at | datetime | requested_at | No |  |
| completed_at | datetime | completed_at | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-014 | 1:N | run に属する blue / green の slot 実行 |
| E-016 | 1:1 | 速報実行(rapid_run)と相関する |
| E-013 | N:1 | parent_run_id でリラン元を追跡する |

#### E-014: slot 実行

- **参照元**: 情報: slot 実行
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| slot | string | slot(blue / green) | No | Yes |
| mode | string | mode(foreground / background / off) | No |  |
| pid | integer | PID | Yes |  |
| artifact_dir | string | 成果物ディレクトリ | No |  |
| status | string | RUNNING / SUCCEEDED / FAILED / ABORTED | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | N:1 | 並行稼働実行に属する |
| E-011 | 1:1 | Runner Result を出力する |
| E-015 | 1:1 | 完了時に完了通知を送る(速報有効時) |

#### E-015: 完了通知

- **参照元**: 情報: 完了通知
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| slot | string | slot(blue / green) | No | Yes |
| job_id | string | JOB_ID | No |  |
| notification_type | string | 通知種別(blue-completed / green-completed) | No |  |
| exit_code | integer | 終了コード | No |  |
| artifact_uri | string | 成果物ディレクトリまたは artifact_uri | No |  |
| occurred_at | datetime | 完了日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-016 | N:1 | 速報実行に集約される |

#### E-016: 速報実行(rapid_run)

- **参照元**: 情報: 速報実行(rapid_run)
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id | No | Yes |
| blue_status | string | blue_status | Yes |  |
| green_status | string | green_status | Yes |  |
| blue_artifact_uri | string | blue_artifact_uri | Yes |  |
| green_artifact_uri | string | green_artifact_uri | Yes |  |
| completion_status | string | 完了状況(両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み) | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | 1:1 | 並行稼働実行と相関する |
| E-017 | 1:1 | 両系成功時に速報比較依頼を 1 件作成する |

#### E-017: 速報比較依頼(rapid_crosscheck_request)

- **参照元**: 情報: 速報比較依頼(rapid_crosscheck_request)
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | run_id(主キー) | No | Yes |
| job_id | string | JOB_ID | No |  |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | No |  |
| worker_id | string | worker_id | Yes |  |
| lease_until | datetime | lease_until | Yes |  |
| exit_code | integer | 比較ツールの exit_code | Yes |  |
| stdout | text | 比較ツールの stdout | Yes |  |
| stderr | text | 比較ツールの stderr | Yes |  |
| error_summary | string | error_summary | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-016 | 1:1 | 速報実行から作成される |
| E-018 | 1:N | 比較結果を生む |
| E-006 | N:1 | job_id ごとの比較定義に従う |

#### E-018: 比較結果(comparison_result)

- **参照元**: 情報: 比較結果(comparison_result)
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| comparison_result_id | string | comparison_result_id | No | Yes |
| run_id | string | run_id | No |  |
| comparison_type | string | comparison_type | No |  |
| status | string | 比較 OK / 比較 NG / FAILED | No |  |
| difference_count | integer | difference_count | Yes |  |
| report_uri | string | report_uri | Yes |  |
| occurred_at | datetime | compared_at | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-017 | N:1 | 速報比較依頼に属する |

#### E-019: 確報比較依頼(final_crosscheck_request)

- **参照元**: 情報: 確報比較依頼(final_crosscheck_request)
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| final_crosscheck_id | string | final_crosscheck_id | No | Yes |
| business_date | date | business_date | No |  |
| catalog_version | string | 対象カタログの版 | No |  |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | No |  |
| worker_id | string | worker_id | Yes |  |
| lease_until | datetime | lease_until | Yes |  |
| exit_code | integer | 比較ツールの exit_code | Yes |  |
| stdout | text | 比較ツールの stdout | Yes |  |
| stderr | text | 比較ツールの stderr | Yes |  |
| error_summary | string | error_summary | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-008 | N:1 | 対象カタログの版を紐付ける |
| E-020 | 1:1 | 比較ツール実行結果を保存する |

#### E-020: 比較ツール実行結果

- **参照元**: 情報: 比較ツール実行結果
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| request_id | string | 依頼 ID(run_id または final_crosscheck_id) | No | Yes |
| crosscheck_type | string | 比較種別(速報 / 確報) | No | Yes |
| stdout | text | stdout | No |  |
| stderr | text | stderr | No |  |
| exit_code | integer | exitcode(0=比較 OK / 3=比較 NG / 6=実行エラー) | No |  |
| started_at | datetime | 実行開始日時 | No |  |
| occurred_at | datetime | 実行終了日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-017 | 1:1 | 速報比較依頼に保存される |
| E-019 | 1:1 | 確報比較依頼に保存される |

#### E-021: 監視記録

- **参照元**: 情報: 監視記録
- **モデル種別**: イベント+スナップショット

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | 監視対象 run_id | No | Yes |
| role | string | 監視対象 role | No | Yes |
| target_type | string | 監視対象種別(background slot / 速報比較依頼) | No |  |
| monitor_status | string | 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了 | No |  |
| started_at | datetime | 開始時刻(started-at.txt) | No |  |
| elapsed_minutes | integer | 経過時間 | No |  |
| hang_detect_limit_minutes | integer | hang_detect_limit_minutes | No |  |
| hang_suspected_at | datetime | hang_suspected_at | Yes |  |
| alerted_at | datetime | alerted_at | Yes |  |
| elapsed_at_alert_minutes | integer | 警告時の経過時間 | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-014 | N:1 | background slot 実行を監視する |
| E-017 | N:1 | 速報比較依頼を監視する |
| E-022 | 1:N | 通知メールを送る |

#### E-022: 通知メール

- **参照元**: 情報: 通知メール
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| notification_id | string | 通知 ID | No | Yes |
| severity | string | 重要度(warning / error) | No |  |
| notification_type | string | 通知種別(ハング疑い / background 実行エラー / 速報クロスチェック異常) | No |  |
| run_id | string | run_id | No |  |
| job_id | string | JOB_ID | No |  |
| role | string | role | No |  |
| elapsed_minutes | integer | 経過時間 | Yes |  |
| recipient | string | 宛先(運用者) | No |  |
| body | text | 本文 | No |  |
| occurred_at | datetime | 送信日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-021 | N:1 | 監視記録から送られる |

#### E-023: リラン指示

- **参照元**: 情報: リラン指示
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| new_run_id | string | 新 run_id | No | Yes |
| source_run_id | string | --source-run-id | No |  |
| role | string | --role(blue / green / rapid-crosscheck) | No |  |
| parent_run_id | string | parent_run_id(直前のリラン元) | No |  |
| source_job_definition | string | 起動元専用ジョブ | Yes |  |
| precheck_result | text | 事前検証結果(元の mode / 元の状態 / role 妥当性) | No |  |
| occurred_at | datetime | 指示日時 | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | 1:1 | 新しい並行稼働実行を作成する |
| E-010 | N:1 | 元の execution-spec から復元する |

#### E-024: 中止指示

- **参照元**: 情報: 中止指示
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| run_id | string | --run-id | No | Yes |
| abort_target | string | 中止対象種別(abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck) | No | Yes |
| occurred_at | datetime | 指示日時 | No | Yes |
| displayed_status | string | 表示した現在状態 | No |  |
| confirmation | string | 停止確認応答(yes / no) | No |  |
| operator | string | 指示者(実行ユーザー) | No |  |
| resulting_status | string | 更新後状態(ABORTED。yes 以外なら変更なし) | Yes |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-014 | N:1 | background slot 実行を中止する |
| E-017 | N:1 | 速報比較依頼を中止する |
| E-019 | N:1 | 確報比較依頼を中止する |

#### E-025: 実行ログ

- **参照元**: 情報: 実行ログ
- **モデル種別**: イベント

| 属性名 | 型 | 説明 | NULL | PK |
|--------|-----|------|:----:|:--:|
| log_file_path | string | ログファイルパス | No | Yes |
| occurred_at | datetime | 出力日時 | No | Yes |
| script_name | string | スクリプト名(facade / runner / クロスチェック runner・worker / ハング検知 / background-rerun / 中止スクリプト) | No |  |
| run_id | string | run_id | Yes |  |
| level | string | ログレベル | No |  |
| message | text | メッセージ | No |  |

**リレーション**

| 対象エンティティ | カーディナリティ | 説明 |
|-----------------|:---------------:|------|
| E-013 | N:1 | run_id をキーに並行稼働実行を追跡する |

### ストレージマッピング

| エンティティID | ストレージ種別 | 根拠 | 確信度 |
|---------------|:------------:|------|:------:|
| E-001 | ファイル | feature flag は env 形式の設定ファイルとして基盤適用設計者が版管理し、facade が起動のたびに読み込む | 高 |
| E-002 | ファイル | runner 割当は feature flag 設定ファイル内の BLUE_RUNNER / GREEN_RUNNER として所有される | 高 |
| E-003 | ファイル | slot ジョブマップは適用側が版管理する設定ファイル。run 開始時に execution-spec.json へ確定保存される | 高 |
| E-004 | ファイル | ハング検知上限はジョブマップの一部として所有され、execution-spec.json に反映される | 高 |
| E-005 | ファイル | 適用文書は relay-gate の仕組みに含めない案件固有事項の文書。適用側が版管理する | 高 |
| E-006 | ファイル | 比較定義はクロスチェックジョブマップの一部として job_id ごとに差し替える設定ファイル | 高 |
| E-007 | ファイル | クロスチェックジョブマップは適用側が定義する設定ファイル | 高 |
| E-008 | ファイル | 対象カタログは適用側が版管理する定義ファイル。確報比較依頼は版だけを紐付ける(infra: product-mapping-onprem.yaml → config_storeのfidelity=exactで適合確認) | 高 |
| E-009 | ファイル | ジョブ起動要求は永続レコードを持たず、execution-spec.json(追加引数)と実行ログに取り込まれる | 低 |
| E-010 | ファイル | facade/<run_id>/execution-spec.json として成果物ディレクトリに一度だけ確定保存する(Runner Result Contract) | 高 |
| E-011 | ファイル | started-at.txt / stdout.log / stderr.log / exitcode.txt として成果物ディレクトリに残す外部 IF の正本 | 高 |
| E-012 | ファイル | 応答は標準出力・標準エラー・終了コードとして中継され、履歴はジョブスケジューラの責務。relay-gate 側は実行ログにのみ残す(infra: product-mapping-onprem.yaml → execution_log_storeのfidelity=exactで適合確認) | 高 |
| E-013 | RDB | run_id で成果物・rapid_run・比較依頼を相関付ける管理レコード。速報有効時のみ作成し、リラン系譜を parent_run_id で追跡する | 高 |
| E-014 | ファイル | slot 実行の状態は Runner Result(exitcode.txt の有無・値)から導出でき、RAPID_CROSSCHECK_MODE=off では成果物ファイルだけで動作する | 中 |
| E-014 | RDB | 速報有効時は mode / PID / 状態(ABORTED を含む)を管理 DB にも保持し、abort-blue / abort-green と background-rerun の対象特定に使う | 低 |
| E-015 | RDB | 完了通知は rapid_run の blue_status / green_status / artifact_uri / completed_at として管理 DB に反映される | 高 |
| E-016 | RDB | 両系成功判定と比較依頼の一意作成を行う管理 DB レコード(rapid_run) | 高 |
| E-017 | RDB | 管理 DB 上のジョブキュー。worker の poll / claim / lease による多重実行防止に RDB のトランザクションを使う | 高 |
| E-018 | RDB | 速報比較の結果を run_id で参照するための管理 DB レコード(comparison_result) | 高 |
| E-019 | RDB | 確報側のジョブキュー(final_crosscheck_request)。速報側と別テーブルに分離する | 高 |
| E-020 | RDB | 比較ツールの stdout / stderr / exitcode は依頼レコード(速報 / 確報)に保存される | 高 |
| E-021 | RDB | 監視記録は管理 DB に保持し、警告傾向の確認と hang_detect_limit_minutes の調整根拠にする。RAPID_CROSSCHECK_MODE=off ではファイルのみで監視し記録は実行ログに残す | 中 |
| E-022 | ファイル | メール本体は外部システム(メール通知)へ送信され、relay-gate 側は送信内容を実行ログに残し、alerted_at を監視記録に記録する | 低 |
| E-023 | RDB | リラン指示は新しい parallel_run(parent_run_id 付き)として管理 DB に記録され、事前検証結果は実行ログに残す | 中 |
| E-024 | RDB | 中止指示の結果は slot 実行 / 比較依頼 / parallel_run の ABORTED 更新として管理 DB に反映され、指示者と応答は実行ログに残す | 中 |
| E-025 | ファイル | 各スクリプトの実行ログはファイルとして残す。監査の正本はジョブスケジューラであり、3 ヶ月保管の障害調査資料とする | 高 |

## 凡例

### 確信度

| 確信度 | 意味 |
|:------:|------|
| 高 | RDRA/NFR モデルから明確に推論 |
| 中 | RDRA/NFR モデルから間接推論 |
| 低 | 弱い根拠での推論 |
| デフォルト | 一般的なベストプラクティスを適用 |
| ユーザー指定 | 対話でユーザーが指定 |
