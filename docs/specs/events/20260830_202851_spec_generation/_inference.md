# Spec 生成 分析根拠

design_available: false

## 分析日時

- 2026-08-30 20:28:51(event_id: `20260830_202851_spec_generation`)
- trigger_event: `rdra:20260830_181841_initial_build`, `arch:20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design`
- design 無しモード判定: 引数 `design_available=false` が渡された(最優先条件)。`docs/design/latest/` は存在しない。以降の全 subagent はこの値だけを見る

## システム名の使い分け

| 用途 | 値 | 参照元 |
|---|---|---|
| 仕様書の見出し・和名 | relay-gate 並行稼働実行基盤 | `docs/rdra/latest/システム概要.json` `system_name` |
| コード識別子・契約ファイルの title・英字名 | relay-gate | `system_name` の英字部分(design 無しモードの規則) |
| interface_kind | cli | `システム概要.json` |

## UC 一覧(業務 / BUC / UC ツリー)

BUC.tsv から抽出。UC 数 **32**、BUC 数 **7**、業務数 **5**。

```
実装切替業務
  └── 実装切替ジョブ実行フロー(6 UC)
        ├── 業務ジョブの実行結果を確認する                    [運用者]  画面: facade 実行結果出力
        ├── slot 実行モードを選択して runner を起動する        [運用者]  画面: facade slot 起動出力
        ├── ジョブマップで JOB_ID から実行先を解決する          [運用者]  画面: slot runner ジョブマップ解決出力
        ├── execution-spec.json を確定保存する                [運用者]  画面: slot runner 実行設定確定出力
        ├── 実装スクリプトを実行して Runner Result を出力する  [運用者]  画面: slot runner 実行出力
        └── foreground slot の結果をジョブスケジューラへ中継する [運用者] 画面: facade 応答出力
クロスチェック業務
  ├── 速報クロスチェックフロー(5 UC)
  │     ├── 速報比較結果を参照する                            [運用者]  画面: rapid-crosscheck 結果参照出力
  │     ├── 速報クロスチェック runner へ完了通知を送信する      [運用者]  画面: slot runner 完了通知出力
  │     ├── 両系成功時に速報比較依頼を作成する                [運用者]  画面: rapid-crosscheck runner 判定出力
  │     ├── 速報比較依頼を claim する                          [運用者]  画面: rapid-crosscheck worker claim 出力
  │     └── 比較ツールでジョブ単位比較を実行して結果を登録する  [運用者]  画面: rapid-crosscheck worker 比較実行出力
  └── 確報クロスチェックフロー(5 UC)
        ├── 確報クロスチェック結果を確認する                    [運用者]  画面: final-crosscheck 結果確認出力
        ├── 確報比較依頼を登録して終端状態まで待機する          [運用者]  画面: final-crosscheck runner 待機出力
        ├── 確報比較依頼を claim する                          [運用者]  画面: final-crosscheck worker claim 出力
        ├── 比較ツールで日次全量比較を実行して結果を保存する    [運用者]  画面: final-crosscheck worker 比較実行出力
        └── 保存済みの確報結果をジョブスケジューラへ返す        [運用者]  画面: final-crosscheck runner 応答出力
実行監視業務
  └── background 実行監視フロー(5 UC)
        ├── background 異常の通知メールを受け取る              [運用者]  画面: hang-detect 通知確認出力
        ├── background 実行の経過時間と終了状態を判定する      [運用者]  画面: hang-detect 判定出力
        ├── ハング疑い・実行エラー・比較異常を通知する          [運用者]  画面: hang-detect 異常通知出力
        ├── 監視記録を保存する                                [運用者]  画面: hang-detect 監視記録出力
        └── hang_detect_limit_minutes をジョブごとに調整する   [運用者]  画面: hang-detect 警告傾向出力
実行復旧業務
  ├── 実行中止フロー(2 UC)
  │     ├── 現在状態を確認して停止確認に応答する              [運用者]  画面: abort 現在状態確認出力
  │     └── 実行を ABORTED へ遷移させる                       [運用者]  画面: abort 状態更新出力
  └── background 側リランフロー(4 UC)
        ├── リラン結果を parent_run_id で追跡する             [運用者]  画面: background-rerun 系譜追跡出力
        ├── リラン対象を検証する                              [運用者]  画面: background-rerun 事前検証出力
        ├── 元の execution-spec.json から復元して新しい run_id で起動する [運用者] 画面: background-rerun 再実行出力
        └── 速報比較依頼だけを新規作成する                    [運用者]  画面: background-rerun 比較依頼再作成出力
適用構成業務
  └── 適用構成定義フロー(5 UC)
        ├── 切り替えた運用モードで業務ジョブを実行する        [運用者]        画面: facade 運用モード出力
        ├── feature flag を設定する                           [基盤適用設計者] 画面: feature flag 設定検証出力
        ├── slot runner の実体スクリプトを割り当てる          [基盤適用設計者] 画面: slot runner 割当検証出力
        ├── slot ごとのジョブマップを定義する                 [基盤適用設計者] 画面: slot ジョブマップ検証出力
        └── クロスチェックのジョブマップと比較定義を定義する  [基盤適用設計者] 画面: クロスチェックジョブマップ検証出力
```

- RDRA の「画面」は UI 画面ではなく **CLI の出力(stdout / stderr / 終了コード)** を表す(`interface_kind: cli`、条件「CLI とメールによる提示」)
- ディレクトリ名: 業務名 / BUC 名 / UC 名にスラッシュは含まれないため置換不要。UC 名の空白・記号(`.` `_` `-` `()`)はそのまま使う

## ティア構成と種別判定

`system_architecture.tiers` は 5 ティア。`tier-datastore` はインフラ(データストア)ティアのため UC 単位 Spec では生成せず、`_cross-cutting/datastore/` の責務とする。

| tier_id | 名称 | 種別判定 | 根拠 | tier md のフォーマット |
|---|---|---|---|---|
| tier-facade | facade / slot runner ティア | **CLI 系** | technology_candidates「シェルスクリプト CLI(bash)」。ジョブスケジューラから同期起動される facade.sh / blue-runner / green-runner | CLI 系(コマンド契約 + 出力契約 + UC ロジック) |
| tier-rapid-crosscheck | 速報クロスチェックティア | **CLI 系 + 非同期処理系** | runner は公開 function(blue-completed / green-completed)の CLI、worker は管理 DB を poll するコンシューマ | dispatcher は CLI 系、worker は非同期処理系(イベント処理仕様 + エラーハンドリング)を同一ファイル内で節分け |
| tier-final-crosscheck | 確報クロスチェックティア | **CLI 系 + 非同期処理系** | runner は別ジョブ定義から起動される CLI(同期 polling)、worker は poll / claim コンシューマ | 同上 |
| tier-ops | 実行監視・復旧ティア | **CLI 系** | hang-detector(定期ジョブ)/ background-rerun(専用ジョブ)/ abort-*(対話 CLI)。すべて CLI 起動 | CLI 系(hang-detector は定期ジョブとしてのトリガー・冪等性も記述) |
| tier-datastore | データストアティア | インフラ | 管理 DB / 成果物 / 設定ファイル / 実行ログ | 生成しない(`_cross-cutting/datastore/`) |

- Presentation 系ティア(frontend / ui)は存在しない。画面仕様・コンポーネント設計・デザイントークン参照・`screens` は **どの tier md にも生成しない**
- API 系ティア(HTTP)は存在しない。`_api-summary.yaml` は `paths: []`(HTTP API なし)とし、CLI コマンド契約と非同期イベント(RDB ジョブキュー・完了通知)を `x_cli_commands` / `async_events` に記録する(後述の確認推奨項目 1・4)

## UC-ティアマッピング(UC パターン別ティア選定)

全 UC が「コマンド UC(CLI プロダクト)」パターン(関連モデルに「画面」があるが arch に Presentation 系ティアが無く、CLI 系ティアがある)。UC が属する処理主体(facade / runner / rapid / final / ops)に応じて対象ティアを絞る。

| # | UC | 対象ティア | 根拠 |
|---|---|---|---|
| 1 | 業務ジョブの実行結果を確認する | tier-facade | facade 応答(ジョブスケジューラ応答)の契約を運用者が読む |
| 2 | slot 実行モードを選択して runner を起動する | tier-facade | facade.sh の入力検証・slot 起動順序・parallel_run 作成 |
| 3 | ジョブマップで JOB_ID から実行先を解決する | tier-facade | slot runner のジョブマップ解決 |
| 4 | execution-spec.json を確定保存する | tier-facade | slot runner の repository(一度きり保存) |
| 5 | 実装スクリプトを実行して Runner Result を出力する | tier-facade | slot runner の SSH gateway + Runner Result 公開 |
| 6 | foreground slot の結果をジョブスケジューラへ中継する | tier-facade | facade presentation の無加工中継 |
| 7 | 速報比較結果を参照する | tier-rapid-crosscheck | comparison_result / 依頼レコードの参照 CLI |
| 8 | 速報クロスチェック runner へ完了通知を送信する | tier-facade, tier-rapid-crosscheck | 送信側は slot runner(gateway)、受信側は rapid runner の公開 function |
| 9 | 両系成功時に速報比較依頼を作成する | tier-rapid-crosscheck | dispatcher の両系成功判定 + 一意作成 |
| 10 | 速報比較依頼を claim する | tier-rapid-crosscheck | worker の poll / claim / lease |
| 11 | 比較ツールでジョブ単位比較を実行して結果を登録する | tier-rapid-crosscheck | worker の比較実行 + comparison_result 登録 |
| 12 | 確報クロスチェック結果を確認する | tier-final-crosscheck | 確報 runner 応答の契約を運用者が読む |
| 13 | 確報比較依頼を登録して終端状態まで待機する | tier-final-crosscheck | final runner の登録 + 同期 polling |
| 14 | 確報比較依頼を claim する | tier-final-crosscheck | final worker の poll / claim / lease |
| 15 | 比較ツールで日次全量比較を実行して結果を保存する | tier-final-crosscheck | final worker の全量比較 |
| 16 | 保存済みの確報結果をジョブスケジューラへ返す | tier-final-crosscheck | final runner presentation の無加工中継 |
| 17 | background 異常の通知メールを受け取る | tier-ops | 通知メールの本文契約(受け手は運用者) |
| 18 | background 実行の経過時間と終了状態を判定する | tier-ops | hang-detector の走査・判定表 |
| 19 | ハング疑い・実行エラー・比較異常を通知する | tier-ops | hang-detector のメール送信 gateway |
| 20 | 監視記録を保存する | tier-ops | hang-detector の監視記録 repository |
| 21 | hang_detect_limit_minutes をジョブごとに調整する | tier-ops, tier-facade | 監視記録の警告傾向参照(ops)と slot ジョブマップの hang_detect_limit_minutes 定義(facade の設定契約) |
| 22 | 現在状態を確認して停止確認に応答する | tier-ops | abort-* の現在状態表示と対話プロンプト |
| 23 | 実行を ABORTED へ遷移させる | tier-ops | abort-* の条件付き UPDATE |
| 24 | リラン結果を parent_run_id で追跡する | tier-ops | parent_run_id 系譜の参照 CLI |
| 25 | リラン対象を検証する | tier-ops | background-rerun の事前検証表 |
| 26 | 元の execution-spec.json から復元して新しい run_id で起動する | tier-ops, tier-facade | rerun が復元した設定で slot runner を起動(runner 側は execution-spec 入力モード) |
| 27 | 速報比較依頼だけを新規作成する | tier-ops, tier-rapid-crosscheck | rerun が rapid 側の依頼テーブルへ REQUESTED を作成 |
| 28 | 切り替えた運用モードで業務ジョブを実行する | tier-facade | 運用モード(feature flag の組合せ)ごとの facade 挙動 |
| 29 | feature flag を設定する | tier-facade | feature flag 設定ファイルの契約と検証 |
| 30 | slot runner の実体スクリプトを割り当てる | tier-facade | BLUE_RUNNER / GREEN_RUNNER の契約と runner IF |
| 31 | slot ごとのジョブマップを定義する | tier-facade | slot ジョブマップファイルの契約と検証 |
| 32 | クロスチェックのジョブマップと比較定義を定義する | tier-rapid-crosscheck, tier-final-crosscheck | 比較定義(速報)と対象カタログ(確報)の設定契約 |

## Step3 の subagent グループ分割(4 グループ、単一メッセージで同時起動)

| グループ | 担当 UC | UC 数 |
|---|---|---|
| G1 実装切替 + 適用構成 | #1〜#6, #28〜#31 | 10 |
| G2 速報 + 比較定義 | #7〜#11, #32 | 6 |
| G3 確報 + 監視 | #12〜#16, #17〜#20 | 9 |
| G4 監視調整 + 復旧 | #21〜#27 | 7 |

## API エンドポイント推定

HTTP API は存在しない(arch `technology_context.constraints`「HTTP API は無い」、CTP-001)。代わりに **CLI コマンド契約**を推定する。

| コマンド | ティア | 起動元 | 引数 |
|---|---|---|---|
| `facade.sh JOB_ID [PARAM...]` | tier-facade | ジョブスケジューラ(業務ジョブ) | JOB_ID, PARAM... |
| `$BLUE_RUNNER` / `$GREEN_RUNNER`(runner IF) | tier-facade | facade.sh / background-rerun | run_id, job_id, role, PARAM... / `--execution-spec <path>` |
| `rapid-crosscheck-runner.sh blue-completed|green-completed` | tier-rapid-crosscheck | slot runner | run_id, job_id, exit_code, artifact_uri |
| `rapid-crosscheck-worker.sh [--once]` | tier-rapid-crosscheck | ジョブスケジューラ / 常駐 | worker_id |
| `rapid-crosscheck-result.sh --run-id` | tier-rapid-crosscheck | 運用者 | run_id |
| `final-crosscheck-runner.sh --business-date --catalog-version` | tier-final-crosscheck | ジョブスケジューラ(確報ジョブ) | business_date, catalog_version |
| `final-crosscheck-worker.sh [--once]` | tier-final-crosscheck | ジョブスケジューラ / 常駐(DB セグメント) | worker_id |
| `hang-detector.sh` | tier-ops | ジョブスケジューラ(定期ジョブ 5 分ごと) | なし |
| `background-rerun.sh --source-run-id --role` | tier-ops | ジョブスケジューラ(専用ジョブ) | source_run_id, role |
| `abort-blue.sh|abort-green.sh|abort-rapid-crosscheck.sh|abort-final-crosscheck.sh --run-id` | tier-ops | 運用者(直接起動) | run_id, 対話応答 yes/no |
| `run-lineage.sh --run-id` | tier-ops | 運用者 | run_id |
| `validate-config.sh`(feature flag / ジョブマップ / クロスチェックジョブマップの検証) | tier-facade / rapid / final | 基盤適用設計者 | 設定ファイルパス |

## 非同期イベント

| チャネル | 方向 | 送信元 → 受信先 | 実体 |
|---|---|---|---|
| slot-completed(blue-completed / green-completed) | publish | slot runner → rapid-crosscheck-runner | 公開 function 呼び出し(同期プロセス起動。RAPID_CROSSCHECK_MODE=on のみ) |
| rapid-crosscheck-requests | publish / subscribe | rapid runner(dispatcher)/ background-rerun → rapid worker | 管理 DB の `rapid_crosscheck_requests` をジョブキューとして poll / claim / lease |
| final-crosscheck-requests | publish / subscribe | final runner → final worker | 管理 DB の `final_crosscheck_requests` をジョブキューとして poll / claim / lease |
| hang-alert-mail | publish | hang-detector → メール通知(運用者) | OS メール送信コマンド。warning / error |

## 全体横断設計方針

### ユーザーフロー(業務フロー横断)

1. 運用者: 業務ジョブ実行 → ジョブスケジューラ応答確認 → (background 異常メール) → 中止 → リラン → 系譜追跡
2. 運用者: 速報比較結果参照(原因調査)→ 確報結果確認(リリース判断)
3. 基盤適用設計者: feature flag 設定 → runner 割当 → slot ジョブマップ定義 → クロスチェック定義 → 切り替え後の運用
4. 自動: 定期ハング検知 → 判定 → 通知 → 監視記録 → hang_detect_limit_minutes 調整

### 情報アーキテクチャ(コマンド体系)

```
relay-gate/
  facade.sh                      業務ジョブ起動口(JOB_ID [PARAM...])
  runners/ $BLUE_RUNNER, $GREEN_RUNNER
  rapid-crosscheck-runner.sh     blue-completed / green-completed
  rapid-crosscheck-worker.sh
  rapid-crosscheck-result.sh     比較結果参照
  final-crosscheck-runner.sh     確報ジョブ起動口
  final-crosscheck-worker.sh
  hang-detector.sh               定期ジョブ
  background-rerun.sh            専用ジョブ
  abort-blue.sh / abort-green.sh / abort-rapid-crosscheck.sh / abort-final-crosscheck.sh
  run-lineage.sh                 parent_run_id 追跡
  validate-config.sh             設定検証
```

### データ可視化対象

UI 画面が無いため可視化は「出力の集計・表形式」に限る。対象: 速報比較結果参照(run_id 単位の表)、監視記録の警告傾向(job_id × role × 警告時経過時間の表)、リラン系譜(run_id の連鎖リスト)。チャートは対象なし。

## NFR 反映事項

| NFR | 反映先 |
|---|---|
| B.2.1.1 レスポンスタイム 10 秒以内(facade オーバーヘッド・中止/リラン CLI) | tier-facade / tier-ops の非機能節。DB 接続タイムアウトは 10 秒以内に収める |
| B.2.1.2 スループット 〜10 TPS | 管理 DB 書き込みは低頻度。インデックスは status / lease_until の poll 用に限定 |
| B.2.2.1 バッチ 8 時間以内 | final runner の polling 上限(既定 8 時間)を設定可能に |
| A.1.1.1 / A.1.1.3 計画停止 | worker は `--once` で定期ジョブ運転可能にし、常駐前提にしない |
| C.6.1.1 ログ保管 3 ヶ月 / C.3.1.1 自動記録 / E.7.1.1 監査 | 実行ログ(スクリプト名 / run_id / UTC 日時 / レベル / メッセージ)を専用ファイルへ。監査の正本はジョブスケジューラ |
| E.5.1.1 / E.5.2.1 / E.6.1.2 SSH 鍵と OS 権限 | 認証情報は参照名のみ。execution-spec.json に値を保存しない |
| model1 + 一部 model2 相当 | foreground 経路の異常は非 0 終了で確実にジョブスケジューラへ伝える |

## 確認推奨項目(dialogue-format 準拠。dialogue_policy: auto_adopt により ⭐推奨を採用して続行)

### 1: CLI コマンド契約の正本フォーマット(API 命名規則に相当)
- **Option A** (⭐推奨): `_cross-cutting/api/cli-command-contract.yaml`(独自 YAML: commands[] / args / options / stdout / stderr / exit_codes)+ `openapi.yaml` はバリデータ互換スタブ(`paths: {}`、`x-cli-contract` で正本を指す) — CLI の引数・出力・終了コードを機械可読で契約化でき、後工程(distillery-impl の contracts 生成)が読める。OpenAPI 側の意味は失う
- **Option B**: OpenAPI 3.1 に `x-cli-*` 拡張で全コマンドを疑似エンドポイント化 — 既存 lint が使えるが HTTP 前提の構造に無理があり実装者を誤導する
- **Option C**: Markdown(tier md)のみで契約を記述し YAML を作らない — 生成コストは最小だが契約型の生成・ドリフト検査ができない

**推奨理由**: medium — arch CTP-001「HTTP API は無い」、システム概要 `interface_kind: cli`。`validateSpecEvent.js` が `openapi.yaml` を必須にするためスタブが必要。命名は kebab-case のスクリプト名 + `--kebab-option`(方針資料の `abort-blue.sh --run-id` に倣う)

### 2: エラーハンドリング戦略・終了コード体系
- **Option A** (⭐推奨): 共通 4 分類 — `0` 成功 / `2` 入力・引数・設定検証エラー / `3` 業務エラー(事前検証 NG・中止不可・比較 NG に相当)/ `6` 実行エラー(SSH・DB・比較ツール実行失敗・内部エラー)。facade の foreground 中継と確報中継は保存済み exitcode をそのまま返す(4 分類を適用しない) — 比較ツール終了コード契約(0 / 3 / 6)と揃うため運用者が一貫して読める
- **Option B**: `0` / `1` の 2 値のみ — 単純だが入力誤りと実行障害を区別できず、ジョブスケジューラ側で再実行判断ができない
- **Option C**: sysexits(64 EX_USAGE / 65 EX_DATAERR / 70 EX_SOFTWARE / 75 EX_TEMPFAIL) — 標準規格だが比較ツール契約(3 / 6)と混在して読みにくい

**推奨理由**: medium — arch CTR-002「入力検証エラー・事前検証エラー・中止不可は非 0 で終了し原因を stderr に出す」は値を定めていない。条件「比較ツール終了コードの対応」の 0 / 3 / 6 に揃えるのが最小の学習コスト

### 3: RDB 正規化レベル
- **Option A** (⭐推奨): 第 3 正規形。依頼レコード(rapid / final)に stdout / stderr / exit_code を text 列で保持(RDRA の情報定義どおり)。状態履歴テーブルは持たず、`model_type: event_snapshot` は status 列 + `*_at` 列で表現 — 方針資料のデータモデルと一致し、bash + SQL で扱いやすい
- **Option B**: 状態遷移履歴テーブル(`*_status_events`)を分離して完全イベントソーシング — 監査に強いが実行履歴・監査はジョブスケジューラの責務(条件)であり過剰
- **Option C**: parallel_run に rapid_run / 依頼を非正規化して 1 テーブル化 — 読み取りは簡単だが速報と確報のモデル分離(条件)に反する

**推奨理由**: high — 条件「速報と確報のモデル分離」「実行履歴はジョブスケジューラの責務」、arch `data_architecture.entities`(model_type: event_snapshot)から直接導出

### 4: AsyncAPI の対象範囲(イベント駆動パターン)
- **Option A** (⭐推奨): RDB ジョブキュー 2 チャネル(rapid-crosscheck-requests / final-crosscheck-requests)+ 完了通知(slot-completed)+ 通知メール(hang-alert-mail)を AsyncAPI で契約化(protocol は `rdb-queue` / `process` / `mail` のカスタム値) — poll / claim / lease と payload を機械可読にでき実装の統合点が明確になる
- **Option B**: asyncapi.yaml を生成しない(非同期はすべて tier md の記述のみ) — 生成は簡単だが Step6.5 観点②(依存の宣言)で cross-UC 依存が暗黙になる
- **Option C**: 完了通知(slot-completed)のみ — 最小だがジョブキューの claim 契約が抜ける

**推奨理由**: medium — arch BC-002 / BC-003「管理 DB 上のジョブキュー」、条件「claim 排他」「lease 失効判定」。AsyncAPI の標準 protocol に RDB キューは無いためカスタム protocol 名を使う

### 5: 設定ファイルの形式(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 対象カタログ)
- **Option A** (⭐推奨): feature flag = env 形式(`BLUE_MODE` / `GREEN_MODE` / `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_MODE` / `CONFIG_VERSION`)、ジョブマップ = TSV(1 行 1 job_id、固定引数列は JSON 配列文字列)、クロスチェックジョブマップ・対象カタログ = TSV — bash 標準コマンドだけで読め、エアーギャップで外部パーサ不要
- **Option B**: すべて YAML — 可読性は高いが bash に YAML パーサが無く実行時依存が増える
- **Option C**: すべて JSON(jq 前提) — 構造は表現しやすいが jq の配備が前提になる

**推奨理由**: low — arch storage_mapping E-001「env 形式」は high だが、ジョブマップの形式は arch に「JOB_ID の行」以上の記述が無い。保守的に bash 単独で扱える TSV を仮採用(todo 登録)

### 6: lease 期間・poll 間隔・polling 上限の既定値
- **Option A** (⭐推奨): lease 10 分 / worker poll 30 秒 / final runner polling 60 秒 / polling 上限 8 時間(超過時は非 0 で終了し依頼は変更しない)。すべて設定で上書き可 — NFR B.2.2.1(8 時間)と B.2.1.2(〜10 TPS)に収まる保守値
- **Option B**: lease 5 分 / poll 10 秒 / polling 30 秒 — 検知は速いが DB 負荷と lease 失効の誤判定リスクが上がる
- **Option C**: lease 30 分 / poll 5 分 / polling 5 分 — 負荷は最小だが worker 障害時の再取得が遅い

**推奨理由**: low — RDRA / arch に具体値が無い(LP-013「polling の間隔と上限は設定で指定」)。todo 登録して実運用値で見直す

### 7: slot 実行の永続化(arch E-014 は file + rdb の二重で confidence low)
- **Option A** (⭐推奨): RAPID_CROSSCHECK_MODE=on のとき `slot_executions` テーブルにも mode / PID / status / artifact_dir を保持し、abort-blue / abort-green と background-rerun の対象特定に使う。off のときは成果物ファイル(started-at.txt / exitcode.txt)だけで状態を導出し、abort は管理 DB が無い旨を stderr に出して終了する(状態更新先が無い) — 方針資料「off の場合も成果物だけで動く」と abort の要件を両立する最小構成
- **Option B**: 常にファイルのみ(ABORTED は成果物ディレクトリの `aborted.txt` マーカー) — DB 不要だが RDRA に無いファイルを発明する
- **Option C**: 常に RDB — 一貫するが off 時に管理 DB 接続を要求し条件「速報クロスチェック有効判定」に反する

**推奨理由**: low — arch storage_mapping E-014(rdb 側 confidence: low)。off 時の abort 対象特定は RDRA に定義が無いため todo 登録

### 8: 監視記録の永続化(arch E-021 confidence medium)
- **Option A** (⭐推奨): `monitor_records` テーブル(監視対象 ID = run_id + role を主キー)に保持し、RAPID_CROSSCHECK_MODE=off では実行ログにのみ残す — 警告傾向の確認(条件「警告傾向の記録」)を SQL で集計できる
- **Option B**: 常に実行ログのみ — 単純だが hang_detect_limit_minutes の調整根拠を grep で集める運用になる
- **Option C**: 成果物ディレクトリに `monitor.json` を残す — DB 不要だが走査コストが増え集計しにくい

**推奨理由**: medium — arch storage_mapping E-021 と LP-020「管理 DB なしでの監視」から導出

### 9: run_id の形式
- **Option A** (⭐推奨): `{UTC yyyymmddThhmmssZ}-{job_id}-{8 桁 hex 乱数}`(例: `20260830T113000Z-JOB001-3f9a1c2e`) — 成果物ディレクトリ名として時系列ソートでき、管理 DB なし(off)でも facade 単独で発行できる
- **Option B**: UUIDv4 — 衝突耐性は高いがディレクトリ一覧で時系列が読めない
- **Option C**: 管理 DB のシーケンス — 一意だが off 時に発行できない

**推奨理由**: low — RDRA / arch に形式の定義が無い(CLAUDE.md「ID 形式は契約に定義されるまで実装で確定しない」)。todo 登録

### 10: 通知メールの送信手段と宛先の設定所有
- **Option A** (⭐推奨): OS 標準の `mail` / `sendmail` コマンドを gateway で呼び、宛先・件名プレフィックス・送信コマンドは hang-detector 用の env 設定ファイル(`hang-detector.env`: `ALERT_MAIL_TO` / `ALERT_MAIL_CMD`)で指定 — arch L-ops-gateway「OS 標準コマンド」と一致
- **Option B**: feature flag 設定ファイルに宛先を追加 — ファイルが 1 つで済むが feature flag の設定所有区分(実装スロットと runner)に反する
- **Option C**: 適用構成文書に宛先を書き、スクリプトは引数で受け取る — 所有は明確だが定期ジョブ定義に宛先が漏れる

**推奨理由**: low — RDRA の情報「通知メール」に宛先(運用者)はあるが設定の所有区分が無い。RDRA に無い設定エンティティのため todo 登録(RDRA 追加提案)

### 11: 状態値の列挙(DIST-002 と関連)
- **Option A** (⭐推奨): 状態.tsv の値をそのまま enum にする — parallel_run: STARTED / RUNNING / COMPLETED / ABORTED、slot 実行: RUNNING / SUCCEEDED / FAILED / ABORTED、依頼: REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED、rapid_run 完了状況: 両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み(英字コード PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED)、monitor_status: 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了(英字コード NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED) — RDRA と 1:1 で追跡できる
- **Option B**: slot 実行にも REQUESTED / CLAIMED を加えて依頼と同じ 6 状態に統一 — 規則は 1 つになるが facade が直接起動する slot に claim 概念は無い
- **Option C**: parallel_run.status を slot 状態からの導出値にして列を持たない — 冗長は減るが off 時に parallel_run 自体が無く導出元が揃わない

**推奨理由**: medium — 状態.tsv の定義に従う。バリエーション「監視状態」(未検知 / ハング疑い / 通知済み / 通知後正常終了)は状態モデル「監視状態」の値と一致しないため rdra-feedback で報告する

## 採用結果(auto_adopt)

| # | 項目 | 採用値 | confidence | 扱い |
|---|---|---|---|---|
| 1 | CLI 契約フォーマット | cli-command-contract.yaml + openapi.yaml スタブ | medium | 採用 |
| 2 | 終了コード体系 | 0 / 2 / 3 / 6(中継系は保存済み exitcode をそのまま) | medium | 採用 |
| 3 | RDB 正規化 | 3NF、履歴テーブルなし | high | 採用 |
| 4 | AsyncAPI 対象 | ジョブキュー 2 + 完了通知 + 通知メール | medium | 採用 |
| 5 | 設定ファイル形式 | env + TSV | low | 仮採用(todo) |
| 6 | lease / poll / polling 上限 | 10 分 / 30 秒 / 60 秒 / 8 時間 | low | 仮採用(todo) |
| 7 | slot 実行の永続化 | on: RDB + file、off: file のみ(abort は不可) | low | 仮採用(todo) |
| 8 | 監視記録の永続化 | monitor_records(on)/ 実行ログ(off) | medium | 採用 |
| 9 | run_id 形式 | UTC 時刻 + job_id + 8 hex | low | 仮採用(todo) |
| 10 | 通知メールの送信手段・宛先設定 | OS mail コマンド + hang-detector.env | low | 仮採用(todo、RDRA 追加提案) |
| 11 | 状態値の列挙 | 状態.tsv の値 + 英字コード | medium | 採用 |
