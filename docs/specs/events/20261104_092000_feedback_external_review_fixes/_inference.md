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

BUC.tsv から抽出。UC 数 **34**、BUC 数 **8**、業務数 **6**(2026-11-01 にハウスキープ業務を追加)。

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
        ├── ハング検知ジョブの異常終了を確認する              [運用者]  画面: hang-detect 通知確認出力
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
        └── クロスチェックのジョブマップと比較定義を定義する  [基盤適用設計者] 画面: 速報クロスチェック設定検証出力
ハウスキープ業務
  └── ハウスキープフロー(2 UC)
        ├── 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する [運用者] 画面: housekeep 判定出力
        └── 成果物と管理 DB の履歴を削除する                  [運用者]  画面: housekeep 削除結果出力
```

- RDRA の「画面」は UI 画面ではなく **CLI の出力(stdout / stderr / 終了コード)** を表す(`interface_kind: cli`、条件「CLI による提示」)
- ディレクトリ名: 業務名 / BUC 名 / UC 名にスラッシュは含まれないため置換不要。UC 名の空白・記号(`.` `_` `-` `()`)はそのまま使う

## ティア構成と種別判定

`system_architecture.tiers` は 5 ティア。`tier-datastore` はインフラ(データストア)ティアのため UC 単位 Spec では生成せず、`_cross-cutting/datastore/` の責務とする。

| tier_id | 名称 | 種別判定 | 根拠 | tier md のフォーマット |
|---|---|---|---|---|
| tier-facade | facade / slot runner ティア | **CLI 系** | technology_candidates「シェルスクリプト CLI(bash)」。ジョブスケジューラから同期起動される facade.sh / blue-runner / green-runner | CLI 系(コマンド契約 + 出力契約 + UC ロジック) |
| tier-rapid-crosscheck | 速報クロスチェックティア | **CLI 系 + 非同期処理系** | runner は公開 function(blue-completed / green-completed)の CLI、worker は管理 DB を poll するコンシューマ | dispatcher は CLI 系、worker は非同期処理系(イベント処理仕様 + エラーハンドリング)を同一ファイル内で節分け |
| tier-final-crosscheck | 確報クロスチェックティア | **CLI 系 + 非同期処理系** | runner は別ジョブ定義から起動される CLI(同期 polling)、worker は poll / claim コンシューマ | 同上 |
| tier-ops | 実行監視・復旧ティア | **CLI 系** | hang-detector(定期ジョブ)/ housekeep(定期ジョブ)/ background-rerun(専用ジョブ)/ abort-*(対話 CLI)。すべて CLI 起動 | CLI 系(hang-detector は定期ジョブとしてのトリガー・冪等性も記述) |
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
| 7 | 速報比較結果を参照する | tier-rapid-crosscheck | 依頼レコードの stdout / stderr / exit_code の参照 CLI |
| 8 | 速報クロスチェック runner へ完了通知を送信する | tier-facade, tier-rapid-crosscheck | 送信側は slot runner(gateway)、受信側は rapid runner の公開 function |
| 9 | 両系成功時に速報比較依頼を作成する | tier-rapid-crosscheck | dispatcher の両系成功判定 + 一意作成 |
| 10 | 速報比較依頼を claim する | tier-rapid-crosscheck | worker の poll / claim / lease |
| 11 | 比較ツールでジョブ単位比較を実行して結果を登録する | tier-rapid-crosscheck | worker の比較実行(起動コマンド置換)+ 依頼レコードへの stdout / stderr / exit_code 保存 |
| 12 | 確報クロスチェック結果を確認する | tier-final-crosscheck | 確報 runner 応答の契約を運用者が読む |
| 13 | 確報比較依頼を登録して終端状態まで待機する | tier-final-crosscheck | final runner の登録 + 同期 polling |
| 14 | 確報比較依頼を claim する | tier-final-crosscheck | final worker の poll / claim / lease |
| 15 | 比較ツールで日次全量比較を実行して結果を保存する | tier-final-crosscheck | final worker の全量比較 |
| 16 | 保存済みの確報結果をジョブスケジューラへ返す | tier-final-crosscheck | final runner presentation の無加工中継 |
| 17 | ハング検知ジョブの異常終了を確認する | tier-ops | hang-detector の終了コードと alert 行の確認(受け手は運用者) |
| 18 | background 実行の経過時間と終了状態を判定する | tier-ops | hang-detector の走査・判定表 |
| 19 | ハング疑い・実行エラー・比較異常を通知する | tier-ops | hang-detector の presentation(alert 行・終了コード)と通知済みの判定 |
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
| 32 | クロスチェックのジョブマップと比較定義を定義する | tier-facade | 速報の比較ツール起動コマンド 1 行(rapid-crosscheck.env の RAPID_COMPARE_COMMAND)の設定と validate-config.sh --rapid-crosscheck 検証(facade 単独。委譲なし) |
| 33 | 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | tier-ops, tier-facade | housekeep の走査・単位の組み立て・判定(ops)と validate-config.sh --housekeep(facade の設定検証) |
| 34 | 成果物と管理 DB の履歴を削除する | tier-ops | housekeep の置き場・削除順序・housekeep_del による行の削除 |

## Step3 の subagent グループ分割(4 グループ、単一メッセージで同時起動)

| グループ | 担当 UC | UC 数 |
|---|---|---|
| G1 実装切替 + 適用構成 | #1〜#6, #28〜#31 | 10 |
| G2 速報 + 起動コマンド設定 | #7〜#11, #32 | 6 |
| G3 確報 + 監視 | #12〜#16, #17〜#20 | 9 |
| G4 監視調整 + 復旧 | #21〜#27 | 7 |

## API エンドポイント推定

HTTP API は存在しない(arch `technology_context.constraints`「HTTP API は無い」、CTP-001)。代わりに **CLI コマンド契約**を推定する。

| コマンド | ティア | 起動元 | 引数 |
|---|---|---|---|
| `facade.sh JOB_ID [PARAM...]` | tier-facade | ジョブスケジューラ(業務ジョブ) | JOB_ID, PARAM... |
| `$BLUE_RUNNER` / `$GREEN_RUNNER`(runner IF) | tier-facade | facade.sh / background-rerun | run_id, job_id, role, PARAM... / `--execution-spec <path>` |
| `rapid-crosscheck-runner.sh blue-completed|green-completed` | tier-rapid-crosscheck | slot runner | run_id, job_id, exit_code |
| `rapid-crosscheck-worker.sh [--once]` | tier-rapid-crosscheck | ジョブスケジューラ / 常駐 | worker_id |
| `rapid-crosscheck-result.sh --run-id` | tier-rapid-crosscheck | 運用者 | run_id |
| `final-crosscheck-runner.sh` | tier-final-crosscheck | ジョブスケジューラ(確報ジョブ) | なし(引数なしで起動) |
| `final-crosscheck-worker.sh [--once]` | tier-final-crosscheck | ジョブスケジューラ / 常駐(DB セグメント) | worker_id |
| `hang-detector.sh` | tier-ops | ジョブスケジューラ(定期ジョブ 5 分ごと) | なし |
| `housekeep.sh` | tier-ops | ジョブスケジューラ(定期ジョブ 1 日 1 回) | なし |
| `background-rerun.sh --source-run-id --role` | tier-ops | ジョブスケジューラ(専用ジョブ) | source_run_id, role |
| `abort-blue.sh|abort-green.sh|abort-rapid-crosscheck.sh|abort-final-crosscheck.sh --run-id` | tier-ops | 運用者(直接起動) | run_id, 対話応答 yes/no |
| `run-lineage.sh --run-id` | tier-ops | 運用者 | run_id |
| `validate-config.sh`(feature flag / slot ジョブマップ / 速報・確報の比較ツール起動コマンド設定の検証) | tier-facade | 基盤適用設計者 | 設定ファイルパス |

## 非同期イベント

| チャネル | 方向 | 送信元 → 受信先 | 実体 |
|---|---|---|---|
| slot-completed(blue-completed / green-completed) | publish | slot runner → rapid-crosscheck-runner | 公開 function 呼び出し(同期プロセス起動。RAPID_CROSSCHECK_MODE=background のみ) |
| rapid-crosscheck-requests | publish / subscribe | rapid runner(dispatcher)/ background-rerun → rapid worker | 管理 DB の `rapid_crosscheck_requests` をジョブキューとして poll / claim / lease |
| final-crosscheck-requests | publish / subscribe | final runner → final worker | 管理 DB の `final_crosscheck_requests` をジョブキューとして poll / claim / lease |

- ハング検知の通知は hang-detector.sh の終了コードと標準エラーの alert 行(CLI の出力)で行い、非同期イベントには含めない(2026-11-01 の変更。decisions/spec-decision-020)

## 全体横断設計方針

### ユーザーフロー(業務フロー横断)

1. 運用者: 業務ジョブ実行 → ジョブスケジューラ応答確認 → (ハング検知ジョブの警告終了・失敗) → 中止 → リラン → 系譜追跡
4. 運用者: ハウスキープ定期ジョブの登録 → 保持日数を過ぎた履歴の自動削除(失敗はジョブスケジューラの障害通知で確認)
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
| C.6.1.1 ログ保管 3 ヶ月 / C.3.1.1 自動記録 / E.7.1.1 監査 | 実行ログ(スクリプト名 / run_id / ローカル日時(指示子なし) / レベル / メッセージ)を専用ファイルへ。監査の正本はジョブスケジューラ |
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

> 2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution): feature flag は元資料の 9 キー(`CONFIG_VERSION` 削除。`RAPID_CROSSCHECK_MODE` は foreground / background / off)、ジョブマップ・クロスチェックジョブマップ・対象カタログは **CSV**(`.csv`。ヘッダー名で列対応、`fixed_params` は二重引用符で囲んだ JSON 配列セル)に変更(D1 / D2)。env 形式の採用自体は維持

> 2026-10-10 利用者決定で簡素化(クロスチェックを元の方針資料の構成へ戻す)。クロスチェックの比較定義は、ジョブ ID ごとの行構造を持つ CSV(crosscheck-job-map.csv)と対象カタログ(target-catalog.csv)を廃止し、**速報・確報の比較ツール起動コマンド各 1 行**に縮退した。速報は `rapid-crosscheck.env` の `RAPID_COMPARE_COMMAND`(プレースホルダ `{job_id}` 必須、`{run_id}` / `{params}` / `{blue_exit_code}` / `{green_exit_code}` 任意)、確報は `final-crosscheck.env` の `FINAL_COMPARE_COMMAND`(プレースホルダ無し)。比較対象の定義は適用側(比較ツール側)が持つ(方針資料 `tmp/RelayGateのしくみ.md` 42 行)。worker は DB の依頼レコードと自身の設定ファイルだけで起動し、成果物ファイル保存・比較結果レコード(comparison_results)・成果物 URI の受け渡しをしない。検証は validate-config.sh が facade 単独で行い(ティア間委譲なし。arch CTR-007)、残す検証はコマンド部分が絶対パスで実行可能・速報は `{job_id}` を含むの 2 点だけ(2026-10-27 の CR-dcd8234d-008 で、起動コマンドを引数の並びとして解釈・起動する共通規則 shared_rules.compare_command_argv を追加し、`{params}` の位置検査を足した。起動は argv 配列で行い文字列をシェルに解釈させない。詳細は下記 20261027 の差分更新履歴)

### 6: lease 期間・poll 間隔・polling 上限の既定値
- **Option A** (⭐推奨): lease 10 分 / worker poll 30 秒 / final runner polling 60 秒 / polling 上限 8 時間(超過時は非 0 で終了し依頼は変更しない)。すべて設定で上書き可 — NFR B.2.2.1(8 時間)と B.2.1.2(〜10 TPS)に収まる保守値
- **Option B**: lease 5 分 / poll 10 秒 / polling 30 秒 — 検知は速いが DB 負荷と lease 失効の誤判定リスクが上がる
- **Option C**: lease 30 分 / poll 5 分 / polling 5 分 — 負荷は最小だが worker 障害時の再取得が遅い

**推奨理由**: low — RDRA / arch に具体値が無い(LP-013「polling の間隔と上限は設定で指定」)。todo 登録して実運用値で見直す

### 7: slot 実行の永続化(arch E-014 は file + rdb の二重で confidence low)
- **Option A** (⭐推奨): RAPID_CROSSCHECK_MODE=background のとき `slot_executions` テーブルにも mode / PID / status / artifact_dir を保持し、abort-blue / abort-green と background-rerun の対象特定に使う。off のときは成果物ファイル(started-at.txt / exitcode.txt)だけで状態を導出し、abort は管理 DB が無い旨を stderr に出して終了する(状態更新先が無い) — 方針資料「off の場合も成果物だけで動く」と abort の要件を両立する最小構成
- **Option B**: 常にファイルのみ(ABORTED は成果物ディレクトリの `aborted.txt` マーカー) — DB 不要だが RDRA に無いファイルを発明する
- **Option C**: 常に RDB — 一貫するが off 時に管理 DB 接続を要求し条件「速報クロスチェック有効判定」に反する

**推奨理由**: low — arch storage_mapping E-014(rdb 側 confidence: low)。off 時の abort 対象特定は RDRA に定義が無いため todo 登録

> 2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution): Runner Result に `aborted.txt` を追加し(Option B の要素を RDRA へ取り込み)、slot 実行の状態はファイル正本から導出する(条件「slot 実行の状態導出規則」)。off でも abort-blue / abort-green は `aborted.txt` で中止が成立し、リランもできる。off 以外では管理 DB `slot_executions.status` に同じ値を保持する二重マッピングで確定(arch E-014 rdb: confidence high)。DIST-009 / DIST-017 解消。管理 DB は relay-gate 内部のデータストア(DIST-001 解消。外部システムから削除)

### 8: 監視記録の永続化(arch E-021 confidence medium)
- **Option A** (⭐推奨): `monitor_records` テーブル(監視対象 ID = run_id + role を主キー)に保持し、RAPID_CROSSCHECK_MODE=off では実行ログにのみ残す — 警告傾向の確認(条件「警告傾向の記録」)を SQL で集計できる
- **Option B**: 常に実行ログのみ — 単純だが hang_detect_limit_minutes の調整根拠を grep で集める運用になる
- **Option C**: 成果物ディレクトリに `monitor.json` を残す — DB 不要だが走査コストが増え集計しにくい

**推奨理由**: medium — arch storage_mapping E-021 と LP-020「管理 DB なしでの監視」から導出

### 9: run_id の形式
- **Option A** (⭐推奨): `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}`(例: `20260830T113000-JOB001-3f9a1c2e`) — 成果物ディレクトリ名として時系列ソートでき、管理 DB なし(off)でも facade 単独で発行できる
- **Option B**: UUIDv4 — 衝突耐性は高いがディレクトリ一覧で時系列が読めない
- **Option C**: 管理 DB のシーケンス — 一意だが off 時に発行できない

**推奨理由**: low — RDRA / arch に形式の定義が無い(CLAUDE.md「ID 形式は契約に定義されるまで実装で確定しない」)。todo 登録

> 2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution): `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}`(時刻部はホストのローカルタイムゾーン、`Z` 無し)で確定。USDM SPEC-011-04 / RDRA 情報「並行稼働実行(parallel_run)」に定義あり。`final_crosscheck_id` も同形式。DIST-018 解消

### 10: 通知メールの送信手段と宛先の設定所有
- **Option A** (⭐推奨): OS 標準の `mail` / `sendmail` コマンドを gateway で呼び、宛先・件名プレフィックス・送信コマンドは hang-detector 用の env 設定ファイル(`hang-detector.env`: `ALERT_MAIL_TO` / `ALERT_MAIL_CMD`)で指定 — arch L-ops-gateway「OS 標準コマンド」と一致
- **Option B**: feature flag 設定ファイルに宛先を追加 — ファイルが 1 つで済むが feature flag の設定所有区分(実装スロットと runner)に反する
- **Option C**: 適用構成文書に宛先を書き、スクリプトは引数で受け取る — 所有は明確だが定期ジョブ定義に宛先が漏れる

**推奨理由**: low — RDRA の情報「通知メール」に宛先(運用者)はあるが設定の所有区分が無い。RDRA に無い設定エンティティのため todo 登録(RDRA 追加提案)

> 2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution): RDRA 情報「ハング検知定期ジョブ設定」(ALERT_MAIL_TO / ALERT_MAIL_CMD / ALERT_SUBJECT_PREFIX / HANG_DB_CONN_REF)が新設され、所有者は基盤適用設計者(設定所有区分「ハング検知定期ジョブ設定」)。件名プレフィックスは `ALERT_SUBJECT_PREFIX`(既定 `[relay-gate]`)。DIST-019 解消

### 11: 状態値の列挙(DIST-002 と関連)
- **Option A** (⭐推奨): 状態.tsv の値をそのまま enum にする — parallel_run: STARTED / RUNNING / COMPLETED / ABORTED、slot 実行: RUNNING / SUCCEEDED / FAILED / ABORTED、依頼: REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED、rapid_run 完了状況: 両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み(英字コード PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED)、monitor_status: 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了(英字コード NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED) — RDRA と 1:1 で追跡できる
- **Option B**: slot 実行にも REQUESTED / CLAIMED を加えて依頼と同じ 6 状態に統一 — 規則は 1 つになるが facade が直接起動する slot に claim 概念は無い
- **Option C**: parallel_run.status を slot 状態からの導出値にして列を持たない — 冗長は減るが off 時に parallel_run 自体が無く導出元が揃わない

**推奨理由**: medium — 状態.tsv の定義に従う。バリエーション「監視状態」(未検知 / ハング疑い / 通知済み / 通知後正常終了)は状態モデル「監視状態」の値と一致しないため rdra-feedback で報告する

> 2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution): バリエーション「監視状態」は状態モデルと同じ 6 値に統一(「通知後正常終了」は遷移 ハング疑い通知済み → 正常終了 の別名)。ハング検知判定結果も 6 値(NOT_TARGET / COMPLETED / MONITORING / HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR)。ハング疑い通知済み → 比較異常通知済み / 実行エラー通知済み / 正常終了、監視中 → 正常終了(中止済み終端を含む)、並行稼働実行 STARTED → ABORTED / RUNNING → COMPLETED(リラン由来 run)は RDRA の遷移として存在する(rdra-feedback #1〜#8、#10〜#12 解消。#9 の C2 図の破線は残る)

## 採用結果(auto_adopt)

| # | 項目 | 採用値 | confidence | 扱い |
|---|---|---|---|---|
| 1 | CLI 契約フォーマット | cli-command-contract.yaml + openapi.yaml スタブ | medium | 採用 |
| 2 | 終了コード体系 | 0 / 2 / 3 / 6(中継系は保存済み exitcode をそのまま) | medium | 採用 |
| 3 | RDB 正規化 | 3NF、履歴テーブルなし | high | 採用 |
| 4 | AsyncAPI 対象 | ジョブキュー 2 + 完了通知 + 通知メール | medium | 採用 |
| 5 | 設定ファイル形式 | env + TSV | low | 仮採用(todo)→ 2026-09-05 利用者決定で env(9 キー)+ CSV に変更(D1 / D2) |
| 6 | lease / poll / polling 上限 | 10 分 / 30 秒 / 60 秒 / 8 時間 | low | 仮採用(todo) |
| 7 | slot 実行の永続化 | on: RDB + file、off: file のみ(abort は不可) | low | 仮採用(todo)→ 2026-09-05 利用者決定で解消(aborted.txt + ファイル正本の状態導出、off 以外は二重マッピング。off でも abort 可) |
| 8 | 監視記録の永続化 | monitor_records(off 以外)/ 実行ログ(off) | medium | 採用 |
| 9 | run_id 形式 | ローカル時刻 + job_id + 8 hex | low | 仮採用(todo)→ 2026-09-05 利用者決定で解消(ローカルタイムゾーン、Z 無し) |
| 10 | 通知メールの送信手段・宛先設定 | OS mail コマンド + hang-detector.env | low | 仮採用(todo、RDRA 追加提案)→ 2026-09-05 利用者決定で解消(RDRA 情報「ハング検知定期ジョブ設定」新設、所有者 = 基盤適用設計者) |
| 11 | 状態値の列挙 | 状態.tsv の値 + 英字コード | medium | 採用(監視状態のバリエーション不一致は 2026-09-05 利用者決定で解消) |


## 差分更新履歴(event 20260907_131000_feedback_abort_consistency)

- 2026-09-07T13:10:00Z。前イベント 20260907_024000_feedback_todo_followup のコピーを起点に、feedback 20260907_abort_consistency(CR-c770d8f0-016 / 017 / 018。利用者決定 DIST-025 A / DIST-026 A / DIST-027 A)の差分だけを反映した
- trigger_event: rdra:20260907_114000_feedback_abort_consistency, arch:20260907_122000_feedback_abort_consistency(参照: nfr:20260907_120000、infra:20260907_124000)
- design_available: false(引数指定。変更なし)。UC ツリー・ティア構成・UC-ティアマッピングは変更なし(32 UC / 7 BUC / 5 業務)
- 変更の正本: `_review/change-brief.md`(D1〜D5)。影響 UC: 両系成功時に速報比較依頼を作成する / 速報クロスチェック runner へ完了通知を送信する / 比較ツールでジョブ単位比較を実行して結果を登録する / 速報比較依頼を claim する / 実行を ABORTED へ遷移させる / 現在状態を確認して停止確認に応答する / リラン対象を検証する / 速報比較依頼だけを新規作成する(hint 文言)と buc-spec(速報クロスチェックフロー / 実行中止フロー)
- 解消した仮採用: 前イベントの「仮採用: rdra-feedback #13」(判定キーの拡張)と注記 #14 / #15。RDRA に反映されたため確定規則として記載。新規の仮採用(confidence: low)は作らない
- `_inputs-digest.md` は arch 20260907_122000 / nfr 20260907_120000 から再生成

## 差分更新履歴(event 20260908_024000_feedback_slot_status_wording)

- 2026-09-08T02:40:00Z。前イベント 20260907_131000_feedback_abort_consistency のコピーを起点に、feedback 20260908_slot_status_wording(CR-c770d8f0-019。利用者決定 DIST-029 A)の文言追従だけを反映した
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording, arch:20260908_015000_feedback_slot_status_wording(参照: nfr:20260907_120000、infra:20260907_124000。本 run は no-change manifest のみ)
- design_available: false(引数指定。変更なし)。UC ツリー・ティア構成・UC-ティアマッピングは変更なし(32 UC / 7 BUC / 5 業務)
- 変更の正本: `_review/change-brief.md`(D1〜D3)。影響 UC: 実装スクリプトを実行して Runner Result を出力する / 両系成功時に速報比較依頼を作成する(BDD 1 件追加)/ 実行を ABORTED へ遷移させる と buc-spec(実装切替ジョブ実行フロー)、cross-cutting(rdb-schema / cli-command-contract / ui-design / 各マトリクス / rdra-feedback)
- 解消した仮採用: 前イベントの確認推奨項目 rdra-feedback #16(条件「slot 実行の状態導出規則」の管理 DB 側文言)。RDRA に反映されたため確定規則として記載。新規の仮採用(confidence: low)は作らない
- `_inputs-digest.md` は arch 20260908_015000 / nfr 20260907_120000 から再生成

## 差分更新履歴(event 20260908_062000_feedback_spec_machine_readable)

- 2026-09-08 06:20:00(event_id: `20260908_062000_feedback_spec_machine_readable`)。feedback request `20260908_spec_machine_readable`(CR-c770d8f0-020 / 021 / 022。direct = causal = 3 件)
- trigger_event: `rdra:20260908_011000_feedback_slot_status_wording`, `arch:20260908_015000_feedback_slot_status_wording`(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は存在しない
- 性質: 記述の機械可読化と正本の一本化のみ。実装挙動・状態遷移・値集合は不変
- 変更の正本: `_review/change-brief.md`(D1〜D4)

| # | 対象 | 変更 | 根拠 |
|---|---|---|---|
| D1 | `spec-event.yaml` `use_cases[].usdm`(32 UC / 133 行 / Scenario 参照 210 件) | 各 spec.md「関連 USDM」表と同内容を投入。scenarios は実 `Scenario:` 名(SPEC 接尾辞込みの完全名)と完全一致。表側は完全名 + 「※」注記の形に整えた | CR-c770d8f0-020。`schema-spec-event.json`(1.15.1)の `use_cases[].usdm`。`validateSpecEvent.js` の usdm warning 32 → 0 |
| D2 | `rdb-schema.yaml` 列挙列 14 列の `enum[]` | RDRA 状態.tsv の状態名 / バリエーション.tsv の値を英字コードで投入。description は意味の説明に整理(「値: …」の列挙を除去)。comparison_type は [job, full](利用者決定 D2 = A)、mode は off を含めない、role は 3 値 | CR-c770d8f0-021。`schema-rdb-schema.json`(1.15.1)の `columns[].enum`。`validateRdbSchema.js` の enum warning 14 → 0 |
| D3 | `cli-command-contract.yaml` `shared_rules.state_codes` | DB 対応 6 項目を `{derived_from: {table, column}, values: [...]}`(利用者決定 D1 = A。request_status は 2 列の配列)、DB 非対応 5 項目を `{source, values}` に改めた。遷移説明は不変。冒頭 note に「values は rdb-schema.yaml の enum の複製。不一致は rdb-schema を正」を明記 | CR-c770d8f0-022 |
| D4 | `usdm-acceptance-matrix.md` / `rdra-feedback.md` / `datastore-schema.md` | usdm[] から再集計(受け入れ条件 122 / 振る舞い SPEC 49 / 49 / 対応 UC 集合の差分 0)。SR-001 / SR-002 を解消済みへ移し「スキーマ更新までの暫定」注記を削除(残存 0 件)。datastore-schema.md を再生成し enum を type 列に追記 | CR-c770d8f0-020 / 021 / 022 の完了条件 |

- 確認推奨項目: 本イベントで新たに仮採用した値は無い。`generateDatastoreMd.js`(1.15.1)が enum を出力しないため、datastore-schema.md の enum 表記は生成後の後処理(type 列へ追記)で反映している(完了報告に記載)

## 差分更新履歴(event 20260917_050000_feedback_impl_feedback_fd678b04)

- 2026-09-16 20:00:00Z(event_id: `20260917_050000_feedback_impl_feedback_fd678b04`)。feedback request `20260917_014138_impl_feedback_fd678b04`(CR-fd678b04-001 / 002。direct = causal = 2 件。実装フェーズ UC fd678b04「feature flag を設定する」からの spec-gap)
- trigger_event: `rdra:20260908_011000_feedback_slot_status_wording`, `arch:20260908_015000_feedback_slot_status_wording`(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は読まない
- 性質: BDD Scenario の責務分離(CR-001)と runner --help 問い合わせ規則の契約への一元化(CR-002)。UC ツリー・ティア構成・UC-ティアマッピング・usdm[] の Scenario 集合は不変(32 UC / 7 BUC / 5 業務)
- 変更の正本: `_review/change-brief.md`(D1〜D3)。影響 UC: feature flag を設定する / slot 実行モードを選択して runner を起動する / slot ごとのジョブマップを定義する / slot runner の実体スクリプトを割り当てる と cross-cutting(cli-command-contract / uc-dependencies / usdm-acceptance-matrix)、decisions/spec-decision-009.yaml
- 解消した仮採用: UC「slot runner の実体スクリプトを割り当てる」tier-facade.md の「--help は 5 秒でタイムアウト(仮採用)」を削除し、契約 `runner_help_probe`(待機上限 4 秒。CR 本文の利用者希望値)に置き換えた。docs/todo.md に 5 秒の登録は無かった。新規の仮採用(confidence: low)は作らない
- `_inputs-digest.md` は前イベントのまま(arch 20260908_015000 / nfr 20260907_120000 に変更なし。event_id ヘッダーのみ本イベントに更新)

## 差分更新履歴(event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2)

- 2026-09-17 01:00:00Z(event_id: `20260917_100000_feedback_impl_feedback_fd678b04_cycle2`)。2026-09-17 の実装フィードバック cycle 2(CR-fd678b04-001。direct = causal = 1 件。実装フェーズ UC fd678b04「feature flag を設定する」からの spec-gap)
- trigger_event: `rdra:20260908_011000_feedback_slot_status_wording`, `arch:20260908_015000_feedback_slot_status_wording`(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は読まない
- 性質: feature-flag.env で拒否する「確報の制御キー」の範囲の一意化(接頭辞 `FINAL_`。CR 本文の利用者希望値で承認済み)と、境界を判定する BDD Scenario の追加。UC ツリー・ティア構成・UC-ティアマッピングは不変(32 UC / 7 BUC / 5 業務)。usdm[] は UC「feature flag を設定する」の SPEC-001-01 に Scenario 1 件追加(Scenario 参照 210 → 211 件)
- 変更の正本: `_review/change-brief.md`(D1〜D3)。影響 UC: feature flag を設定する(spec.md / tier-facade.md / _api-summary.yaml)と cross-cutting(cli-command-contract / usdm-acceptance-matrix / traceability-matrix)、decisions/spec-decision-010.yaml
- 解消した仮採用: なし。新規の仮採用(confidence: low)は作らない(接頭辞は利用者指定。判定順序(FINAL_ は未知キー warn より先)と facade.sh の起動時検証への同範囲の明記は既存記述「同じ検証を共有」の帰結として採用。完了報告の確認推奨項目に記載)
- `_inputs-digest.md` は前イベントのまま(arch 20260908_015000 / nfr 20260907_120000 に変更なし。event_id ヘッダーのみ本イベントに更新)

## 差分更新履歴(event 20260921_100000_feedback_impl_feedback_eff24f55)

- 2026-09-21 10:00:00Z(event_id: `20260921_100000_feedback_impl_feedback_eff24f55`)。2026-09-19 の実装フィードバック(CR-eff24f55-001〜005。direct 4 件 / causal 6 件。実装フェーズ UC eff24f55「slot ごとのジョブマップを定義する」からの blocker 1 / spec-gap 3 / improvement 1)
- trigger_event: `rdra:20260921_084000_feedback_impl_feedback_eff24f55`(no-change), `arch:20260921_092000_feedback_impl_feedback_eff24f55`(no-change)。related: usdm 20260921_084000(SPEC-008-05 の受け入れ基準分割)/ nfr 20260921_090000(B.1.1.2 / B.2.1.1 に CSV 設定ファイルの共通前提)/ infra 20260921_094000(no-change)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は読まない
- dialogue_policy: interactive。第 1 段階で方針レベルの質問 4 問(守備範囲の原則 / 実装済み判断の確定 / error 行の作り方 / パス形式)を提示し、利用者が 2026-09-22 に A / A / A / A、一覧表への異議なしで確定。問 4 の根拠「ジョブマップでの定義なら Windows / Linux 両対応のフルパス / 相対パス指定を受け取れる必要がある」を契約・tier・判断記録に明記
- 性質: 設定ファイル共通の「入力の守備範囲」(CLI 契約 `config_input_rules`)、制御文字の可視表記(ui-design.md)、実装の前提(bash 5.0。契約 `conventions.runtime_prerequisites`)の追加と、work_dir / script のパス形式検査の撤回。UC ツリー・ティア構成・UC-ティアマッピング・RDRA 要素は不変(32 UC / 7 BUC / 5 業務)。usdm[] は UC「slot ごとのジョブマップを定義する」の SPEC-004-04 に Scenario 3 件追加(Scenario 参照 211 → 214 件)
- 変更の正本: `_review/change-brief.md`(D1〜D6)。影響: cross-cutting(cli-command-contract / ui-design / usdm-acceptance-matrix / traceability-matrix)、UC 12 件の tier md(うち本文を変えた UC: slot ごとのジョブマップを定義する / ジョブマップで JOB_ID から実行先を解決する / feature flag を設定する / クロスチェックのジョブマップと比較定義を定義する / hang_detect_limit_minutes をジョブごとに調整する。参照行のみ 7 UC)、decisions/spec-decision-011〜013.yaml
- 方針資料との照合: 設定ファイルの文字コード・バイト異常・差し替え・一時ファイル・制御文字の表記・bash の版は方針資料に記載が無く新規の決定(利用者が確定)。方針資料のジョブマップ CSV 例(督促AP / G:\scripts / ./beam-batches / 空白とカンマを含む固定引数)は第 1 段階で現行の検証コマンドに通し、`is not absolute` で拒否されることを実測 → 検査を撤回し Scenario で受理を固定
- 解消した仮採用: なし。新規の仮採用(confidence: low)は作らない(全決定が利用者確定。docs/todo.md への登録なし)
- `_inputs-digest.md` は nfr latest(20260921_090000)の変更を取り込むため extractSections.js で再生成(arch は 20260908_015000 のまま)

## 差分更新履歴(event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2)

- 2026-09-23 11:20:00Z(event_id: `20260923_112000_feedback_impl_feedback_eff24f55_cycle2`)。2026-09-22 の実装フィードバック cycle 2(CR-eff24f55-006 / 007。direct 2 件 / causal 2 件。実装フェーズ UC eff24f55「slot ごとのジョブマップを定義する」からの spec-gap 2 件)
- trigger_event: `rdra:20260921_084000_feedback_impl_feedback_eff24f55`, `arch:20260921_092000_feedback_impl_feedback_eff24f55`(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は読まない
- dialogue_policy: recommended_auto。確認推奨項目は下記のとおり作成し、利用者の事前指定(CR-007 案 A)と ⭐推奨(CR-006)を採用して続行
- 性質: 仕様内の矛盾の解消(lines= の規則)と未指定の境界の確定(credential_ref の形式違反の扱い・値の非出力)。UC ツリー・ティア構成・UC-ティアマッピング・RDRA 要素は不変(32 UC / 7 BUC / 5 業務)。usdm[] は UC「slot ごとのジョブマップを定義する」の SPEC-004-03 に Scenario 1 件追加(Scenario 参照 214 → 215 件)
- 処理方式: 影響 UC が少数(本文を変えた UC: slot ごとのジョブマップを定義する / クロスチェックのジョブマップと比較定義を定義する / ジョブマップで JOB_ID から実行先を解決する / execution-spec.json を確定保存する)のため、UC 単位の並列 subagent は起動せず順次処理
- 変更の正本: `_review/change-brief.md`(D1〜D3)。判断記録は decisions/spec-decision-014.yaml / spec-decision-015.yaml
- 方針資料との照合: 方針資料は「1 行 1 job_id」「認証情報そのものは保存せず、認証情報の参照名だけを保存する」を定めるだけで、重複の報告形式と参照名の形式の扱いの記載は無い。本イベントの決定はどちらとも矛盾しない
- 解消した仮採用: UC「slot ごとのジョブマップを定義する」の credential_ref の扱いの「仮採用」注記(spec.md の処理フロー図と分岐条件一覧)を確定内容へ置換。docs/todo.md に該当の登録は無かった。新規の仮採用(confidence: low)は作らない(docs/todo.md への登録なし)
- `_inputs-digest.md` は前イベントのまま(arch / nfr latest に変更なし。event_id ヘッダーのみ本イベントに更新)

### 確認推奨項目(dialogue-format 準拠。recommended_auto により採用して続行)

#### 1: 重複報告の lines= に並べる行番号(CR-eff24f55-006)
- **Option A** (⭐推奨): 初出行を含む全行番号を出現順に(`lines=2,5`)— 1 行の error で重複の全体が分かる。BDD・現行実装と一致し実装変更なし
- **Option B**: 2 回目以降の行番号だけ(`lines=5`)— 初出行は利用者が探す。BDD と現行実装の変更が要る
- **Option C**: 初出行を別キーで出す(`first_line=2 lines=5`)— 書式が増え、共通形式 `lines=<n1,n2,...>` から外れる

**推奨理由**: confidence high。要求本文が A を推奨し、controller の事前指定も A。方針資料には報告形式の記載が無く、どれを選んでも矛盾しない。検証種別(slot ジョブマップ / クロスチェックジョブマップ / 対象カタログ)を問わず同じ規則にする

#### 2: 参照名の形式に合わない credential_ref の扱い(CR-eff24f55-007)
- **Option A** (⭐推奨・利用者選択済み): 理由を問わず同じ warn を 1 行出して受理 — 認証情報ストアの運用差を吸収。解決できない値は実行時に初めて失敗する
- **Option B**: `error: credential_ref is invalid line=N job_id=<v>` で拒否(終了コード 2)— 誤りを早く検出。正当な参照名の形式が使えない適用先が出る
- **Option C**: 理由ごとに別の warn 文言(パス / 秘密 / 形式違反)— 文言は正確になるが、対処は同じで文言の数が増える

**推奨理由**: confidence high(利用者が 2026-09-22 のレビューで A を選択。事前指定値として採用)。どの案でも credential_ref の値は診断行(範囲は契約 conventions.credentials: validate-config.sh の stdout / stderr と slot runner の stderr / 実行ログ)に出さない

#### 3: warn して受理した credential_ref の値の保存(第三者レビュー R-001 の帰結)
- **Option A** (⭐推奨): execution-spec.json へそのまま転記する(現行の転記規則のまま)— 利用者決定「拒否しない」と実装に一致。秘密を置かないのは適用側の責任
- **Option B**: 形式違反の値は転記せず null にし、実行ログに WARN — 秘密の保存を防ぐ。参照名として正当な値も失われ実行時の認証に使えない
- **Option C**: 実行時(runner)は拒否する — 保存も実行も防ぐ。検証では受理・実行では拒否となり扱いが二重になる

**推奨理由**: confidence medium。利用者が選んだ案 A(受理)の帰結で、転記規則は既存の契約どおり。方針資料の「認証情報そのものは保存しない」は、参照名の欄に認証情報を置かない運用を前提に成り立つ。契約・tier・spec-decision-015 に帰結として明記し、完了報告の確認推奨項目で利用者に返す(要求の再解釈は伴わない)

### 採用一覧(本イベント)

| # | 項目 | 採用値 | 根拠 |
|---|---|---|---|
| 1 | lines= の規則 | 初出行を含む全行番号を出現順に(Option A) | 利用者の事前指定 = 要求本文の ⭐推奨 |
| 2 | credential_ref の形式違反 | 同じ warn で受理(Option A) | 利用者の事前指定(2026-09-22 のレビューで承認) |
| 3 | credential_ref の値の出力 | 診断行に一切出さない(value= を付けない) | 利用者の事前指定 |
| 4 | 実行ログ `WARN duplicate job_id in job map ... lines=` | 同じ規則を適用 | 同じキー名の表記を 1 つの意味にそろえる(本イベントの帰結。確認推奨) |
| 5 | warn して受理した credential_ref の保存 | execution-spec.json へそのまま転記(Option A) | 利用者決定「拒否しない」の帰結(確認推奨。第三者レビュー R-001) |

## 差分更新履歴(event 20261027_055000_feedback_impl_feedback_dcd8234d)

- 2026-10-27 05:50:00Z(event_id: `20261027_055000_feedback_impl_feedback_dcd8234d`)。2026-10-27 の実装フィードバック(CR-dcd8234d-008。direct 1 件 / causal 1 件。spec 直接所有の spec-gap。前イベント `20261010_204000_feedback_impl_feedback_dcd8234d` の続き)
- direct_stage: spec。上流(RDRA / USDM / arch / nfr / infra)の変更は無く、SPEC-005-03 / SPEC-006-02 と RDRA は「設定 1 行の起動コマンドを依頼レコードの値で起動する」を定めるだけで引数の分け方・起動方式を持たないため文脈参照とする(trigger_event なし)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`docs/design/latest/` は読まない
- dialogue_policy: auto_adopt。利用者が 2026-10-27 のレビューで案 A(比較ツールの起動コマンドを引数ごとに分けて起動する決まりを仕様に書く)を選択済み。確認推奨項目は下記のとおり(FAILED 時の文言・{params} 違反文言の決定)で ⭐推奨を採用して続行
- 性質: 比較ツール起動コマンド(RAPID_COMPARE_COMMAND / FINAL_COMPARE_COMMAND)を引数の並び(argv)として解釈・起動する共通規則を CLI 契約 `shared_rules.compare_command_argv` に 1 か所新設し、速報/確報 worker と validate-config.sh から参照させた。設定読込時に空白区切りで引数に分割(シェル記法は非解釈)、置換は引数 1 つの中だけ、`{params}` は引数全体のときだけ JSON 配列を 1 項目 1 引数へ展開、起動は argv 配列(eval / bash -c / sh -c / 引用符なし展開を禁止)、速報は置換前に job_id / run_id / parameters を形式検査。UC ツリー・ティア構成・UC-ティアマッピング・RDRA 要素は不変(32 UC / 7 BUC / 5 業務)
- usdm[] の Scenario 追加: 速報 worker UC「比較ツールでジョブ単位比較を実行して結果を登録する」SPEC-005-03 に 3 件(記号・空白・$(...) を含む値も 1 引数 / job_id 形式違反で FAILED / parameters 非 JSON で FAILED)、確報 worker UC「比較ツールで日次全量比較を実行して結果を保存する」SPEC-006-02 に 2 件(依頼レコードと設定以外を読まない(既存 spec.md の取り込み)/ argv 分割でシェル非解釈)、設定 UC「クロスチェックのジョブマップと比較定義を定義する」SPEC-004-04 に 2 件({params} 位置違反 / {params} 引数全体で valid)。あわせて速報・確報 UC の古い Scenario 名のドリフト(「… と OK を登録する」等)を現行 spec.md の名称へ是正
- 決定した文言: 置換値の形式検査 NG = 依頼 FAILED / exit_code=6 / error_summary=`invalid request value: <field>`、stderr `error: compare request value is invalid run_id=... field=<job_id|run_id|parameters>`(既存の launch failed と同じ依頼状態・終了コードで文言だけ分ける)。`{params}` の位置違反 = validate-config.sh --rapid-crosscheck の `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=...`(終了コード 2)
- 変更の正本: decisions/spec-decision-018.yaml。影響: cross-cutting(cli-command-contract.yaml の shared_rules / 速報・確報 worker の note / external_interfaces 2 件 / config_files 2 件 / validate-config.sh の stdout・violation・exit_code・option 説明、traceability-matrix.md)、UC 3 件(速報 worker spec.md + tier-rapid-crosscheck.md、確報 worker spec.md + tier-final-crosscheck.md、設定 UC spec.md + tier-facade.md)、各 UC の _api-summary.yaml、spec-event.yaml
- 「置換後の文字列をコマンドとして起動する」という書き方を仕様から除去(grep 0 件を確認)
- 方針資料との照合: `tmp/RelayGateのしくみ.md` は「設定 1 行の起動コマンドを依頼レコードの値で起動する」を定めるだけで、引数の分け方・起動方式(シェル解釈の可否)の記載は無い。本イベントの決定(argv 分割・シェル非解釈・置換前検査)は方針資料と矛盾せず、設定 1 行 + プレースホルダの形・プレースホルダ集合・既存検証 2 点を保つ
- 解消した仮採用: なし。新規の仮採用(confidence: low)は作らない(docs/todo.md への登録なし)
- `_inputs-digest.md` は前イベントのまま(arch / nfr latest に変更なし)

## 差分更新履歴(event 20261101_105000_feedback_impl_feedback_dcd8234d)

- 2026-11-01 10:50:00Z(event_id: `20261101_105000_feedback_impl_feedback_dcd8234d`)。2026-11-01 の実装フィードバック(direct 1 件 = CR-dcd8234d-010#1 / causal 2 件 = CR-dcd8234d-009#1・010#1。前イベント `20261027_055000_feedback_impl_feedback_dcd8234d` の続き)
- trigger_event: usdm `20261101_101000_feedback_impl_feedback_dcd8234d`(SPEC-004-04 の検証 3 点化・受け入れ基準 10 の絞り込み・基準 12 追加)、arch `20261101_103000_feedback_impl_feedback_dcd8234d`(CTR-007 の括弧書きを 3 点へ。arch-decision-021)、infra `20261101_104000_feedback_impl_feedback_dcd8234d`。rdra / nfr は no-change
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`_inputs-digest.md` は arch latest の更新に合わせて再生成した
- dialogue_policy: interactive。確認推奨項目は完了報告で返す(値の前後の空白の扱い)
- 変更 1(CR-010、spec 直接所有): CLI 契約 `shared_rules.compare_command_argv.split` と `config_input_rules.env_files` に、引用符の外し方を同じ文で書いた。先頭の 1 文字が `"` か `'` なら外し、それとは別に(先頭を外した後の)末尾の 1 文字が `"` か `'` なら外す。種類の一致・対は求めない(例 4 件)。env_files の委譲をやめ、UC「feature flag を設定する」の tier-facade.md を契約参照へ改め「仮採用」を外した。実装(facade の 2 つの unquote 関数)と同じ規則で、実装は変えない
- 変更 2(CR-009、上流追従): 速報の起動コマンドの検証を 3 点(コマンド部分 / `{job_id}` / `{params}` は引数 1 つ全体)として、CLI 契約の config_files RAPID_COMPARE_COMMAND の説明、UC「クロスチェックのジョブマップと比較定義を定義する」の spec.md(概要・データフロー表・分岐条件・関連 USDM)/ tier-facade.md / _api-summary.yaml(stderr・終了コード 2 の理由・終了コード 6)を揃えた
- BDD: 受け入れ基準 10 = 新規「引数部分の内容は検査しない(SPEC-004-04)」(引数部分に存在しないパスと未知の語。`{params}` を一部に含まず `{job_id}` を含む)、基準 11 = 新規「クロスチェックジョブマップと対象カタログの検証種別は無い(SPEC-004-04)」(従来は usdm-acceptance-matrix が UC-32 の spec.md に実在しない Scenario 名を挙げていた)、基準 12 = 既存「{params} が引数全体でない位置にある」。tier-facade.md の tier BDD にも引数部分の任意文字列のシナリオを追加
- トレーサビリティ: このリポジトリに traceability-index.json は無い。基準と UC のひもづけは spec-event.yaml `use_cases[].usdm`、spec.md「関連 USDM」表、`_cross-cutting/usdm-acceptance-matrix.md`(受け入れ条件 142 → 143)で行う
- 判断の正本: decisions/spec-decision-019.yaml(spec-decision-017 の「2 点」、spec-decision-018 の「1 組除去」はこれで読み替える。旧決定記録の本文は当時の記録として変更しない)
- 方針資料との照合: `tmp/RelayGateのしくみ.md` は設定値の引用符の扱いと起動コマンドの検証項目の数を定めていない。今回の変更は実装済みの振る舞いを明記するもので、方針資料と矛盾しない
- UC ツリー・ティア構成・UC-ティアマッピング・RDRA 要素は不変(32 UC / 7 BUC / 5 業務)。新規の仮採用は作らない。feature flag の引用符の「仮採用」は解消した

## 差分更新履歴(event 20261101_125000_feedback_mail_removal_housekeeping)

- 2026-11-01 12:50:00Z(event_id: `20261101_125000_feedback_mail_removal_housekeeping`)。2026-11-01 の変更要望(direct 1 件 = CR-e4ea8aaa-003#1 / causal 3 件 = CR-e4ea8aaa-001#1・002#1・003#1)
- trigger_event: usdm / rdra `20261101_121000_feedback_mail_removal_housekeeping`、nfr `20261101_122000_…`、arch `20261101_123000_…`、infra `20261101_124000_…`
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`_inputs-digest.md` は arch / nfr latest の更新に合わせて再生成した(転記元の arch 本文に「メール通知の廃止」などの経緯の語が残る)
- dialogue_policy: interactive。確認推奨項目は完了報告で返す(終了コードの値、off での管理 DB 接続の要否、保持日数の桁数上限)
- 変更 1(CR-003、spec 直接所有): CLI 契約 `config_input_rules.env_files` に、env 値の取り出し方を順序つき規則(最初の = で分割 → キーの前後の空白 → 値の前後の空白 → 引用符を独立に外す。空白は半角空白とタブ)で書き、例 4 件を添えた。`shared_rules.compare_command_argv.split` の再掲にも反映。実装は変えず、VT / FF の扱いの差分を記録(decisions/spec-decision-022)
- 変更 2(CR-001、上流追従): メール通知を廃止し、hang-detector.sh の終了コード(0 / 3 / 6)と標準エラーの alert 行で知らせる形にした。通知済みの判定は監視記録(off は `$RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/<run_id>.<role>`)。UC 17 を「ハング検知ジョブの異常終了を確認する」へ改名。CLI 契約(hang-detector.sh / hang-detector.env / shared_rules.hang_alert / artifact_root_entries)、ui-design.md「ハング検知の通知出力」、ux-design.md、data-visualization.md、asyncapi.yaml(通知メールのチャネル削除)、rdb-schema.yaml(alerted_at の意味)を追従(decisions/spec-decision-020)
- 変更 3(CR-002、上流追従): ハウスキープ業務 / ハウスキープフローの 2 UC(#33 / #34)を新設。CLI 契約に housekeep.sh / housekeep.env / validate-config.sh --housekeep / shared_rules.housekeep_rules、rdb-schema.yaml に db_roles(housekeep_del)と各テーブルの used_by を追加(decisions/spec-decision-021)
- UC ツリー: 34 UC / 8 BUC / 6 業務。ティア構成は不変(housekeep は tier-ops、validate-config.sh --housekeep は tier-facade)
- トレーサビリティ: このリポジトリに traceability-index.json は無い。基準と UC のひもづけは spec-event.yaml `use_cases[].usdm`、spec.md「関連 USDM」表、`_cross-cutting/usdm-acceptance-matrix.md`、`_cross-cutting/traceability-matrix.md` で行う
- 方針資料との照合: `tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md`(2026-11-01 に同方向へ更新済み)の「hang-detector.sh のジョブの終了結果で通知(異常なし = 正常終了、ハング疑い = 警告終了、background 実行エラーと速報クロスチェック異常 = 異常終了)、標準エラーに 1 件 1 行」「通知済みの異常は再び通知しない。off は成果物ルート配下の通知済みの印」「housekeep.sh は 1 日 1 回、保持日数(既定 90 日)、未完了は削除しない、削除待ちの置き場へ移してから削除、専用 DB ロール」と一致する
- 本ファイルの上の過去の判断(#4 / #10 の通知メールなど)は当時の記録で、2026-11-01 以降は decisions/spec-decision-020 / 021 に読み替える

## 差分更新履歴(event 20261103_085000_feedback_housekeeping_followups)

- 2026-11-03 08:50:00Z(event_id: `20261103_085000_feedback_housekeeping_followups`)。2026-11-03 の変更要望(direct 1 件 = CR-f3b8a1d0-002#1 / causal 3 件 = CR-f3b8a1d0-001#1・002#1・003#1)
- trigger_event: usdm / rdra `20261103_081000_feedback_housekeeping_followups`、nfr `20261103_082000_…`、arch `20261103_083000_…`、infra `20261103_084000_…`
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`_inputs-digest.md` は arch / nfr latest の更新に合わせて再生成した
- dialogue_policy: interactive。確認推奨項目は完了報告で返す
- 変更 1(CR-002、spec 直接所有): CLI 契約 `config_input_rules.env_files` の順序つき規則の手順 (2) に、キーの前後の空白を除いた結果キーが空になる行を `error: invalid line line=N path: ...`(2)とする規則と例を加えた。全 env 設定ファイル共通。`compare_command_argv.split` の再掲、空白だけの行の項、ui-design.md、UC「feature flag を設定する」と判定 UC の tier-facade.md を揃えた。feature flag 設定の読み込みとの差分を記録(decisions/spec-decision-023)。docs/todo.md DIST-031 を closed
- 変更 2(CR-001、上流追従): 要求 SPEC-014-08 の新設と SPEC-014-03 / 04 の受け入れ基準の条件の追加を、判定 UC(#33)の BDD・分岐 B-08・成果物だけの判定表・warn の表、削除 UC(#34)の tier BDD、USDM 対応(spec-event.yaml / usdm-acceptance-matrix.md)へ反映。CLI 契約の housekeep.sh の振る舞いは不変(decisions/spec-decision-024)
- 変更 3(CR-003、上流追従): CLI 契約と ui-design.md の実行ログの整理を「relay-gate は整理しない(設置環境の logrotate に任せる。arch CTR-006)」趣旨に改めた(decisions/spec-decision-025)
- UC ツリー: 34 UC / 8 BUC / 6 業務で不変。ティア構成も不変
- トレーサビリティ: traceability-index.json は無い(前イベントと同じ)。spec-event.yaml `use_cases[].usdm`、spec.md「関連 USDM」表、usdm-acceptance-matrix.md、traceability-matrix.md で行う
- 方針資料との照合: `tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md` は housekeep.sh を「1 日 1 回、保持日数(既定 90 日)、未完了は削除しない」と書くだけで、管理 DB に接続しない構成・env の行の形式・実行ログの整理方法を書いていない。今回の変更はいずれも方針資料と矛盾しない(未完了かもしれない実行を残す方向)

## 差分更新履歴(event 20261103_135000_feedback_housekeeping_db_required)

- 2026-11-03 13:50:00Z(event_id: `20261103_135000_feedback_housekeeping_db_required`)。2026-11-03 の変更要望(direct 1 件 = CR-9d2e6c41-002#1 / causal 2 件 = CR-9d2e6c41-001#1・002#1)
- trigger_event: usdm / rdra `20261103_131000_feedback_housekeeping_db_required`、nfr `20261103_132000_…`、arch `20261103_133000_…`、infra `20261103_134000_…`
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`_inputs-digest.md` は arch / nfr latest の更新に合わせて再生成した
- dialogue_policy: interactive。確認推奨項目は完了報告で返す
- 変更 1(CR-002、spec 直接所有): CLI 契約 `config_input_rules.env_files` のコメント行の定義を「行の前後の空白(半角空白とタブ)を除いた結果が `#` で始まる行」に改め、`=` での分割より先に判定すると書いた。例(`# x` / `  # x` / タブ + `# x` / `  # A=B`)を添え、全 env 設定ファイル共通とした。空白だけの行・キーが空の行・`=` の無い行は invalid line のまま、`KEY=#abc` は値 `#abc`。CSV のコメントは行頭 `#` のまま。`compare_command_argv.split`、feature-flag.env の format、ui-design.md、UC「feature flag を設定する」の tier-facade.md(形式と BDD)、UC「クロスチェックのジョブマップと比較定義を定義する」の tier-facade.md(BDD)、確報の比較ツール UC の tier-final-crosscheck.md を揃えた。速報クロスチェック設定の読み込み(rapid_crosscheck_env.sh)との差分を記録(decisions/spec-decision-026)
- 変更 2(CR-001、上流追従): ハウスキープ設定の管理 DB 接続参照名を「RAPID_CROSSCHECK_MODE が off 以外」または「確報クロスチェックを使う設置」で必須とした。確報クロスチェックを使う設置 = `final-crosscheck.env` があり `FINAL_DB_CONN_REF` が欠落していない(キーがあり値が空でない)。abort-final-crosscheck.sh の管理 DB なしの判定(不在または欠落)の裏返しで、`欠落 = キーが無い、または値が空` を同コマンドにも明記した。正本は契約 `shared_rules.housekeep_rules.db_requirement`(新設)。欠落・空は既存の `error: option required option=HOUSEKEEP_DB_CONN_REF path: ...`(2)。final-crosscheck.env は off で接続参照名が無い・空のときだけ読む。設定の検査を `processing_order` の手順 0 として、削除待ちの置き場の残りの削除(手順 1)より先に置いた(既存の手順番号は不変)。判定 UC(#33)に分岐 B-09・要否の表・BDD(SPEC-014-04 に 1 件、SPEC-014-07 に 2 件、tier に 3 件)、削除 UC(#34)に手順 1 の前提と tier BDD 1 件を加え、SPEC-014-08 のシナリオの Given に「確報クロスチェック worker の設定が無い設置」を書いた(decisions/spec-decision-027)
- UC ツリー: 34 UC / 8 BUC / 6 業務で不変。ティア構成も不変
- トレーサビリティ: RDRA は要素の追加・削除なし(説明の追補のみ)。網羅率は不変(100%)。usdm-acceptance-matrix.md は REQ 14 / SPEC 59 / 受け入れ条件 190
- 方針資料との照合: `tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md` は housekeep.sh を「1 日 1 回、保持日数(既定 90 日)を過ぎた終了済みの成果物と実行管理データを削除、未完了は削除しない、削除には専用 DB ロール」と書く。管理 DB を使う設置で接続参照名を必須にし実行管理データ(確報比較依頼を含む)を確実に消す変更は方針資料に沿う。env の行の形式は方針資料に記載が無く、矛盾しない

## 差分更新履歴(event 20261103_151000_feedback_env_duplicate_key)

- 2026-11-03 15:10:00Z(event_id: `20261103_151000_feedback_env_duplicate_key`)。2026-11-03 の変更要望(direct 1 件 = causal 1 件 = CR-b7c40e19-001#1)
- trigger_event: specs `20261103_135000_feedback_housekeeping_db_required`(上流 latest は変更なし。spec だけを実行)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。上流 latest が変わらないため `_inputs-digest.md` は前イベントのものを引き継いだ
- dialogue_policy: interactive。確認推奨項目は完了報告で返す
- 変更(CR-b7c40e19-001、spec 直接所有): CLI 契約 `config_input_rules.env_files` に同じキーの重複の規則(`error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...`、終了コード 2、そのファイルの値を使わない)と、1 つの env ファイルの検査の段・報告の順(バイト・改行 → invalid line → duplicate key → キーごとの検査)、validate-config.sh の stdout を加えた。判断は spec-decision-028
- UC ツリー: 34 UC / 8 BUC / 6 業務で不変。ティア構成も不変。追加した BDD は tier だけで、E2E の受け入れ条件の数(usdm-acceptance-matrix.md)は不変
- トレーサビリティ: RDRA は要素の追加・削除なし。網羅率は不変(100%)。rdra-feedback.md への追記は不要(RDRA は行の形式を持たない)
- 方針資料との照合: `tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md` に env の同じキーの重複の扱いの記載は無く、矛盾しない

## 差分更新履歴(event 20261104_092000_feedback_external_review_fixes)

- 2026-11-04 09:20:00Z(event_id: `20261104_092000_feedback_external_review_fixes`)。2026-11-04 の外部レビューの指摘(direct 3 件 = CR-c5e19a72-001#1 / 003#1 / 004#1、causal 4 件 = 001#1 / 002#1 / 003#1 / 004#1)
- trigger_event: infra `20261104_091000_feedback_external_review_fixes`(他の上流 latest は変更なし)
- design 無しモード判定: 引数 `design_available=false`(最優先条件)。`_inputs-digest.md` は extractSections.js で本イベントの event_id で作り直した(arch / nfr の内容は前イベントと同じ)
- dialogue_policy: interactive。確認推奨項目は完了報告で返す
- 変更(CR-c5e19a72-001、spec 直接所有): ハング検知は off 以外で管理 DB に接続・SELECT できない回に alert 行を出さず error 1 行と終了コード 6 で終える(走査しない)。off の通知済みの印が規定の値でない・読めない対象は `error: notified mark invalid ...` を出して MONITORING として判定し、alert 行を出した対象と判定が COMPLETED の対象は印を書き直す。対象ごとの行の順と、横断規約の「error は 1 回だけ」の例外を揃えた
- 変更(CR-c5e19a72-002、infra 直接所有の追従): 構築手順の配置時の検査がファイルの存在確認だけになったため、hang-detector.env の値(RAPID_HANG_DETECT_LIMIT_MINUTES / HANG_SCAN_WINDOW_HOURS)の検査と未知キーの warn、走査前の検査の順を契約に足した
- 変更(CR-c5e19a72-003、spec 直接所有): member_source の判定の順 (1)〜(3) を成果物だけで判定する実行に限定し、parallel_runs 行がある実行は管理 DB の行で判定する。ハウスキープの処理の順(置き場の残り・孤立した印は名前の昇順(バイト順)など)を processing_sequence に定めた
- 変更(CR-c5e19a72-004、spec 直接所有): config_input_rules.byte_checks を加え、NUL / UTF-8 / BOM / CR の違反の報告(全件・行番号の昇順・同じ行は NUL → UTF-8 → BOM → CR・hint の位置・第 1 段で止める・violations の数え方)を CSV・env 共通で決めた
- 反証レビューで追加で決めた規則: off で印の置き場 hang-detector-notified/ があるのに読めない回は `error: notified mark dir is not readable path: ...` の 1 行だけで走査せず終了コード 6(走査前の設定の検査のあと、facade/ を列挙する前に検査)。判定しない対象(warn を出した run / role)の印は読まない。印の確定名がディレクトリなど通常のファイルでないときは中へ移さず(mv -T 相当)`error: notified mark save failed ...`(6)。ハウスキープの単位内の手順 3 は失敗しても残りのエントリの削除を続け、失敗したエントリごとに `error: artifact delete failed` を 1 行出し、1 つでも失敗したら管理 DB の行を消さない。
- 判断は spec-decision-029。spec-decision-020 の 3 の「管理 DB に接続できない回は全対象を MONITORING とみなして alert 行を出す」は本判断で置き換えた(020 は同判断の 7 にならい経緯として残し、書き換えない)
- UC ツリー: 34 UC / 8 BUC / 6 業務で不変。ティア構成も不変。E2E BDD は UC「ハング疑い・実行エラー・比較異常を通知する」に SPEC-008-07 の Scenario 3 件、UC「background 実行の経過時間と終了状態を判定する」に Scenario 2 件(SPEC 接尾なし)を追加・1 件を改めた。usdm[] と spec.md「関連 USDM」表、usdm-acceptance-matrix.md を揃えた(受け入れ条件の数は不変)
- トレーサビリティ: RDRA は要素の追加・削除なし。網羅率は不変(100%)。rdra-feedback.md への追記は不要(RDRA 条件「通知レベルの判定」「ハウスキープの削除順序と回復」と矛盾せず、行の形式・処理の順は RDRA の粒度に無い)
- 方針資料との照合: `tmp/RelayGateのしくみ.md` の「通知済みの異常は、次回以降の監視で再び通知しません」に、管理 DB に接続できない回に alert 行を出さない変更で揃えた。他の変更(印の不正、ハウスキープの処理の順、バイト・改行の違反の報告の順、ハング検知設定の値の検査)は方針資料に記載が無く、矛盾しない
