# UX デザイン仕様

> design 無しモード(`design_available: false`、`interface_kind: cli`)。
> 本システムは UI 画面を持たない(arch CTP-001)。「画面」はすべて **コマンドの出力(stdout / stderr / 終了コード)** に読み替える。運用者への通知も hang-detector の終了コードと標準エラーで行い、ジョブスケジューラの既存のジョブ監視・障害通知で届ける。
> フローのノードはコマンド / ジョブであり、画面遷移は存在しない。
> 出力の具体的な規約(終了コード・フォーマット・状態文字列・hang-detector の alert 行)は `ui-design.md`(出力規約)を正本とする。

## ユーザーフロー

### 実装切替業務 × 実行監視業務 × 実行復旧業務: 業務ジョブ実行から background 異常の復旧まで

**アクター**: 運用者
**ゴール**: ジョブスケジューラの実行結果で foreground の成否を判定し、background 側の異常はハング検知ジョブの警告終了・失敗(ジョブスケジューラの障害通知)から中止・リラン・系譜追跡で復旧する

```mermaid
flowchart LR
  A["ジョブスケジューラ: 業務ジョブ定義\nfacade.sh JOB_ID PARAM..."] --> B["facade.sh\nslot 起動 (background → foreground)"]
  B --> C["ジョブスケジューラ応答\nstdout / stderr / 終了コードを確認"]
  B -.background slot.-> D["hang-detector.sh\n定期ジョブ 5 分ごと"]
  D --> E["ハング検知ジョブの終了結果\n警告終了 3 / 失敗 6 + alert 行\n(ジョブスケジューラの障害通知)"]
  E --> F["運用者: プロセス停止を確認"]
  F --> G["abort-blue.sh / abort-green.sh\n--run-id RUN_ID"]
  G --> H["ジョブスケジューラ: background リラン専用ジョブ\nbackground-rerun.sh --source-run-id --role"]
  H --> I["run-lineage.sh --run-id\nparent_run_id で系譜追跡"]
```

**タッチポイント**:

| ステップ | コマンドまたはジョブ | UC | 感情 | 改善機会 |
|---------|------|---|------|---------|
| 業務ジョブの起動 | ジョブスケジューラ → `facade.sh JOB_ID [PARAM...]` | slot 実行モードを選択して runner を起動する | ニュートラル | 両 slot foreground などの設定誤りは runner を 1 つも起動せずに終了コード 2 で止める。原因を stderr に具体値つきで出す |
| 実行結果の確認 | ジョブスケジューラ応答(foreground の 3 ファイル無加工中継) | 業務ジョブの実行結果を確認する / foreground slot の結果をジョブスケジューラへ中継する | ポジティブ | 並行稼働中も単独本番中も見え方が同じ。background や速報の結果が混ざらない |
| 異常の受信 | `hang-detector.sh` の終了コード(3 / 6)→ ジョブスケジューラの障害通知 | ハング検知ジョブの異常終了を確認する | ネガティブ | ジョブステータス(警告終了 / 失敗)で重要度が分かり、標準エラーの alert 行(1 件 1 行)で通知種別・run_id・role・経過時間が読める。推奨対処は通知種別ごとに `ui-design.md`「ハング検知の通知出力」に定める |
| 停止の確認と中止 | `abort-blue.sh --run-id` / `abort-green.sh --run-id` | 現在状態を確認して停止確認に応答する / 実行を ABORTED へ遷移させる | ネガティブ(慎重) | 現在状態(成果物ファイルから導出)を先に表示してから停止確認プロンプトを出す。yes 以外は状態を変えない。yes で `aborted.txt` を書き、RAPID_CROSSCHECK_MODE が off 以外なら管理 DB も ABORTED にする。off でも中止が成立する |
| リラン | 専用ジョブ → `background-rerun.sh --source-run-id --role` | リラン対象を検証する / 元の execution-spec.json から復元して新しい run_id で起動する | ニュートラル | 事前検証は常にファイル正本(`exitcode.txt` / `aborted.txt`)で行い、off でもリランできる。NG の理由(元の mode / 元の状態)を stderr に出し、新 run_id を stdout に出す |
| 系譜の追跡 | `run-lineage.sh --run-id` | リラン結果を parent_run_id で追跡する | ポジティブ | 最新から元の実行まで TSV 1 行 1 run で数珠つなぎに読める |

### クロスチェック業務: 速報比較結果の原因調査から確報結果によるリリース判断まで

**アクター**: 運用者
**ゴール**: 速報比較結果で差分の原因を調査し、確報(日次全量比較)の結果をリリース判断の正本として用いる

```mermaid
flowchart LR
  A["slot runner\nblue-completed / green-completed"] --> B["rapid-crosscheck-runner.sh\n両系成功判定 → 依頼 REQUESTED"]
  B --> C["rapid-crosscheck-worker.sh\nclaim → 比較ツール起動 → 依頼レコードへ結果保存"]
  C --> D["rapid-crosscheck-result.sh --run-id\n速報比較結果を参照 (原因調査)"]
  D --> E["ジョブスケジューラ: 確報ジョブ定義\nfinal-crosscheck-runner.sh (引数なし)"]
  E --> F["final-crosscheck-worker.sh\nclaim → 日次全量比較 → 結果保存"]
  F --> G["ジョブスケジューラ応答\n保存済み stdout / stderr / exitcode を無加工中継"]
  G --> H["運用者: リリース判断"]
```

**タッチポイント**:

| ステップ | コマンドまたはジョブ | UC | 感情 | 改善機会 |
|---------|------|---|------|---------|
| 完了通知 | slot runner → `$RAPID_CROSSCHECK_RUNNER blue-completed / green-completed` | 速報クロスチェック runner へ完了通知を送信する | ニュートラル(自動) | 運用者の操作なし。RAPID_CROSSCHECK_MODE が off 以外(foreground / background)で送信し、off では送信しない。送信失敗は自動検知せず、runner の実行ログに `WARN completion notice failed ...` を残す(条件「完了通知失敗の扱い」)。復旧は運用者が速報クロスチェック runner を同一引数で再実行する(冪等・先勝ち) |
| 比較依頼の作成 | `rapid-crosscheck-runner.sh` | 両系成功時に速報比較依頼を作成する | ニュートラル(自動) | 完了順にかかわらず 1 run_id に 1 件。重複作成しない |
| 比較の実行 | `rapid-crosscheck-worker.sh [--once]` | 速報比較依頼を claim する / 比較ツールでジョブ単位比較を実行して結果を登録する | ニュートラル(自動) | 比較ツールの stdout / stderr / exit_code を依頼レコードの列へ保存する。比較 NG / FAILED は hang-detector の失敗終了(alert 行 kind=rapid-crosscheck-error)で運用者に届く |
| 速報結果の参照 | `rapid-crosscheck-result.sh --run-id` | 速報比較結果を参照する | ネガティブ(差分あり)〜ポジティブ | 依頼状態・両系の完了結果・exit_code を 1 行 1 事実で出し、比較ツールの本文は `--show-output` で末尾に出す。速報は原因調査用であり、リリース判断に使わないことを stderr の info で明示 |
| 確報の起動 | ジョブスケジューラ → `final-crosscheck-runner.sh`(引数なし) | 確報比較依頼を登録して終端状態まで待機する | ニュートラル | polling 上限(既定 8 時間)超過は終了コード 6 で終了し、依頼は変更しない |
| 確報結果の確認 | ジョブスケジューラ応答(保存済み 3 値の無加工中継) | 確報クロスチェック結果を確認する / 保存済みの確報結果をジョブスケジューラへ返す | ポジティブ | 比較ツールの終了コード 0 / 3 / 6 がそのままジョブスケジューラの判定に使える。依頼の状態名は返さない |

### 適用構成業務: 適用構成の定義から切り替え後の運用まで

**アクター**: 基盤適用設計者(定義)、運用者(切り替え後の運用)
**ゴール**: relay-gate のスクリプトを変更せずに、設定ファイルだけで並行稼働・単独本番・次世代並行稼働を切り替える

```mermaid
flowchart LR
  A["feature flag 設定 (9 キー)\nBLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE\nBLUE_IMPL / GREEN_IMPL"] --> B["runner 割当\nBLUE_RUNNER / GREEN_RUNNER\nRAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER"]
  B --> C["slot ジョブマップ定義 (CSV)\njob_id → 実行先 + fixed_params + hang_detect_limit_minutes"]
  C --> D["比較ツール起動コマンド設定 (env)\n速報 rapid-crosscheck.env (RAPID_COMPARE_COMMAND)\n確報 final-crosscheck.env (FINAL_COMPARE_COMMAND)"]
  D --> E["validate-config.sh\n設定検証 (終了コード 0 / 2)"]
  E --> F["ジョブスケジューラ: 業務ジョブ定義\nfacade.sh JOB_ID PARAM..."]
  F --> G["運用者: 切り替えた運用モードで実行結果を確認"]
```

**タッチポイント**:

| ステップ | コマンドまたはジョブ | UC | 感情 | 改善機会 |
|---------|------|---|------|---------|
| feature flag 設定 | `feature-flag.env` 編集(9 キー。設定版は持たない) → `validate-config.sh` | feature flag を設定する | ニュートラル | foreground × foreground の組合せを検証で拒否し、どの slot も起動しない。元資料の 9 キーで書けば未知キー警告は出ない。モードは 3 値(foreground / background / off)、実装版は BLUE_IMPL / GREEN_IMPL |
| runner 割当 | `feature-flag.env` 編集 → `validate-config.sh` | slot runner の実体スクリプトを割り当てる | ニュートラル | BLUE_RUNNER / GREEN_RUNNER(と off 以外のときの RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)の絶対パス・存在・実行権限を検証で確認する |
| slot ジョブマップ定義 | `blue-job-map.csv` / `green-job-map.csv` 編集 → `validate-config.sh` | slot ごとのジョブマップを定義する | ニュートラル | CSV(1 行目ヘッダー、列はヘッダー名で対応付け)。`fixed_params` の JSON 配列セル(二重引用符で囲む)と hang_detect_limit_minutes(0 以上の整数)、host / user の両方あり・両方なしを検証で確認する |
| 比較ツール起動コマンド定義 | `rapid-crosscheck.env`(`RAPID_COMPARE_COMMAND`)/ `final-crosscheck.env`(`FINAL_COMPARE_COMMAND`)編集 → `validate-config.sh` | クロスチェックのジョブマップと比較定義を定義する | ニュートラル | 起動コマンドのコマンド部分(先頭の語)が絶対パスで存在・実行可能であること(速報は加えて `{job_id}` を含むこと)を検証で確認する |
| 切り替え後の運用 | ジョブスケジューラ → `facade.sh` | 切り替えた運用モードで業務ジョブを実行する | ポジティブ | ジョブ定義を変えずに運用モードが切り替わる。ジョブスケジューラの見え方は変わらない |

### 実行監視業務: 定期ハング検知から hang_detect_limit_minutes の調整まで

**アクター**: ジョブスケジューラ(定期起動・障害通知)、運用者(異常終了の確認と調整)
**ゴール**: background 実行の異常を通知だけで運用者に伝え、警告傾向からジョブごとの上限を調整する

```mermaid
flowchart LR
  A["ジョブスケジューラ: 定期ジョブ 5 分ごと\nhang-detector.sh"] --> B["判定\nexitcode.txt / aborted.txt の有無・値 × 経過時間と上限"]
  B --> C["ハング検知ジョブの終了結果\nハング疑いだけ=警告終了 3 / 実行エラー・比較異常=失敗 6\nalert 行 1 件 1 行(通知済み・中止済みは出さない)"]
  B --> D["監視記録\nmonitor_status (6 値) / hang_suspected_at / alerted_at"]
  C --> E["運用者: 静観 or 対処"]
  D --> F["hang-detect-trend.sh\n警告傾向を参照"]
  F --> G["slot ジョブマップ編集\nhang_detect_limit_minutes 調整"]
  G --> H["次回以降の run の execution-spec.json に反映"]
```

**タッチポイント**:

| ステップ | コマンドまたはジョブ | UC | 感情 | 改善機会 |
|---------|------|---|------|---------|
| 定期走査 | `hang-detector.sh` | background 実行の経過時間と終了状態を判定する | ニュートラル(自動) | 状態を変更せず通知のみ。通知済みの異常は次の見回りで再び知らせない(2 回目は終了コード 0) |
| 通知 | `hang-detector.sh` の終了コードと alert 行 → ジョブスケジューラの障害通知 | ハング疑い・実行エラー・比較異常を通知する / ハング検知ジョブの異常終了を確認する | ネガティブ | 警告終了(3)は静観候補、失敗(6)は対処必須とジョブステータスで判別できる |
| 監視記録 | 管理 DB `monitor_records`(RAPID_CROSSCHECK_MODE が off 以外)/ 実行ログと通知済みの印(off) | 監視記録を保存する | ニュートラル(自動) | 通知後に正常終了した実行(HANG_SUSPECTED_NOTIFIED → COMPLETED)の警告時経過時間を残す。中止済み(`aborted.txt`)の対象は COMPLETED で終端する |
| 上限の調整 | `hang-detect-trend.sh` → slot ジョブマップ編集 | hang_detect_limit_minutes をジョブごとに調整する | ポジティブ | job_id × role ごとの最後の警告時経過時間を TSV で出し、調整値の根拠にする |

### ハウスキープ業務: 保持日数を過ぎた履歴の自動削除

**アクター**: ジョブスケジューラ(1 日 1 回の定期起動・障害通知)、運用者(定期ジョブの登録と失敗の確認)、基盤適用設計者(保持日数の設定)
**ゴール**: 終了済みの実行の成果物と管理 DB の履歴を、保持日数(既定 90 日)を過ぎたら運用者の判断なしで消し、終わっていない実行とリランの親子は残す

```mermaid
flowchart LR
  A["ジョブスケジューラ: 定期ジョブ 1 日 1 回\nhousekeep.sh"] --> B["削除待ちの置き場の残りを削除"]
  B --> C["成果物ルートと管理 DB を走査\nリランの親子を 1 単位にまとめる"]
  C --> D{"全構成要素が終端し\n最も遅い終了日時から保持日数を過ぎた?"}
  D -->|はい| E["成果物を置き場へ移して削除\n→ 管理 DB の行を 1 トランザクションで削除"]
  D -->|いいえ| F["単位ごと残す"]
  E --> G["stdout に削除件数\n失敗は stderr + 終了コード 6"]
  F --> G
  G --> H["運用者: 失敗時はジョブスケジューラの障害通知で確認"]
```

**タッチポイント**:

| ステップ | コマンドまたはジョブ | UC | 感情 | 改善機会 |
|---------|------|---|------|---------|
| 保持日数の設定 | `housekeep.env` 編集 → `validate-config.sh --housekeep` | 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ニュートラル | 保持日数は既定 90 日で、正の整数でなければ検証で拒否する。削除したくない場合は定期ジョブを登録しない |
| 削除対象の判定 | ジョブスケジューラ → `housekeep.sh` | 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ニュートラル(自動) | リランの親子をまとめて判定し、1 つでも終わっていない構成要素があれば残す。判定できない成果物ディレクトリは残して `warn:` で知らせる |
| 削除 | `housekeep.sh` | 成果物と管理 DB の履歴を削除する | ニュートラル(自動) | 削除件数を stdout に出す。途中で失敗しても次回の実行で残りを消す(何度実行しても結果が同じ) |

## 情報アーキテクチャ(IA)

### コマンド体系

```mermaid
graph LR
  Root["relay-gate 配置ディレクトリ (RELAY_GATE_HOME)"]
  Root --> F["tier-facade"]
  Root --> R["tier-rapid-crosscheck"]
  Root --> FC["tier-final-crosscheck"]
  Root --> O["tier-ops"]
  F --> F1["facade.sh JOB_ID [PARAM...]"]
  F --> F2["$BLUE_RUNNER / $GREEN_RUNNER (runner IF)"]
  F --> F3["validate-config.sh"]
  R --> R1["rapid-crosscheck-runner.sh blue-completed | green-completed"]
  R --> R2["rapid-crosscheck-worker.sh [--once]"]
  R --> R3["rapid-crosscheck-result.sh --run-id"]
  FC --> FC1["final-crosscheck-runner.sh (引数なし)"]
  FC --> FC2["final-crosscheck-worker.sh [--once]"]
  O --> O1["hang-detector.sh"]
  O --> O2["hang-detect-trend.sh [--job-id]"]
  O --> O3["background-rerun.sh --source-run-id --role"]
  O --> O4["abort-blue.sh / abort-green.sh --run-id"]
  O --> O5["abort-rapid-crosscheck.sh / abort-final-crosscheck.sh --run-id"]
  O --> O6["run-lineage.sh --run-id"]
  O --> O7["housekeep.sh"]
```

- コマンド名は kebab-case のスクリプト名、オプションは `--kebab-option`(_inference.md 採用値 #1)
- `hang-detect-trend.sh` は UC「hang_detect_limit_minutes をジョブごとに調整する」の警告傾向参照(RDRA 画面「hang-detect 警告傾向出力」)を担う参照系コマンド。Step3 の tier-ops.md と `cli-command-contract.yaml` で `hang-detect-trend.sh`(独立コマンド)として確定済み(`hang-detector.sh` へのオプション統合は採用しない)

### エントリポイント

| 起動元 | コマンド | ティア | 起動の性質 |
|---|---|---|---|
| ジョブスケジューラ: 業務ジョブ定義 | `facade.sh JOB_ID [PARAM...]` | tier-facade | 同期。foreground の終了を待って応答する |
| ジョブスケジューラ: 確報クロスチェックジョブ定義 | `final-crosscheck-runner.sh`(引数なし) | tier-final-crosscheck | 同期。終端状態まで polling して応答する |
| ジョブスケジューラ: ハング検知定期ジョブ(5 分ごと) | `hang-detector.sh` | tier-ops | 定期。通知のみで状態を変えない。終了コード 3 / 6 をジョブスケジューラの障害通知の対象にする |
| ジョブスケジューラ: ハウスキープ定期ジョブ(1 日 1 回) | `housekeep.sh` | tier-ops | 定期。保持日数を過ぎた終了済みの履歴だけを削除する。終了コード 6 を障害通知の対象にする |
| ジョブスケジューラ: background リラン専用ジョブ | `background-rerun.sh --source-run-id --role` | tier-ops | 同期。事前検証後に新 run_id で起動して戻る |
| ジョブスケジューラ / 常駐: worker | `rapid-crosscheck-worker.sh [--once]` / `final-crosscheck-worker.sh [--once]` | tier-rapid-crosscheck / tier-final-crosscheck | `--once` で 1 回の poll / claim / 実行。常駐時は poll 間隔で繰り返す |
| 運用者の直接起動 | `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh --run-id` | tier-ops | 対話。現在状態表示 → 停止確認プロンプト |
| 運用者の直接起動 | `rapid-crosscheck-result.sh --run-id` / `run-lineage.sh --run-id` / `hang-detect-trend.sh` | tier-rapid-crosscheck / tier-ops | 参照のみ。状態を変えない |
| 基盤適用設計者の直接起動 | `validate-config.sh` | tier-facade(rapid / final / housekeep の設定も検証) | 参照のみ。終了コードで妥当性を返す |
| 内部呼び出し | `$BLUE_RUNNER` / `$GREEN_RUNNER` | tier-facade | facade.sh と background-rerun.sh が起動する。運用者は直接起動しない |
| 内部呼び出し | `$RAPID_CROSSCHECK_RUNNER blue-completed / green-completed`(実体は feature flag の `RAPID_CROSSCHECK_RUNNER`。既定の配置名は `rapid-crosscheck-runner.sh`) | tier-rapid-crosscheck | slot runner が完了時に起動する(RAPID_CROSSCHECK_MODE が off 以外。foreground / background で同じ挙動) |

### 外部システムとの接点(5 種)

| 外部システム | 接点 | 方向 |
|---|---|---|
| ジョブスケジューラ | `facade.sh` / `final-crosscheck-runner.sh` / 定期ジョブ(hang-detector / housekeep)/ リラン専用ジョブ / worker ジョブ定義の起動と応答(stdout / stderr / 終了コード)。hang-detector の警告終了・失敗は既存のジョブ監視・障害通知で運用者へ届く | 双方向 |
| 現行実装(blue) | slot runner が `BLUE_RUNNER` 経由で実装スクリプトを起動し、Runner Result を受け取る | relay-gate → 実装 |
| 新実装(green) | 同上(`GREEN_RUNNER`) | relay-gate → 実装 |
| 比較ツール | 速報 / 確報 worker が起動し、終了コード(0 / 3 / 6)と stdout / stderr を受け取る | relay-gate → 比較ツール |
| リモート実行ホスト(SSH) | ジョブマップの `host` / `user` が空でないとき slot runner が SSH で実装スクリプトを実行する(両方空はローカル実行) | relay-gate → ホスト |

- 管理 DB(RDB)は relay-gate 内部のデータストア(ジョブキュー兼管理 DB)であり、外部システムには数えない(RDRA 外部システム.tsv から削除済み)

### コマンド間の受け渡しルール

- **run_id の相関**: `facade.sh` が run 開始時に run_id を発行し、以降のすべてのコマンド(runner / 完了通知 / 比較依頼 / 監視記録 / abort / rerun / lineage)は同じ run_id で相関付ける。run_id は成果物ディレクトリ名(`facade/<run_id>/`)と管理 DB の主キーに共通で使う(arch CTP-003)。形式は `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex}`(`ui-design.md`)で、RAPID_CROSSCHECK_MODE=off でも facade 単独で発行する
- **Runner Result の 3 ファイル**: slot runner → facade / hang-detector / rapid-crosscheck-runner の受け渡しは `stdout.log` / `stderr.log` / `exitcode.txt` の 3 ファイル(+ `started-at.txt` / `execution-spec.json`。中止時は abort-blue / abort-green が書く `aborted.txt`)で行う。一時ファイルへ出力してから確定名へリネームし、確定名が存在するときだけ完了とみなす(arch CTR-001)。slot 実行の状態はこれらのファイルから導出する(`exitcode.txt` → SUCCEEDED / FAILED、`aborted.txt` → ABORTED、どちらも無し → RUNNING)
- **終了コードの引き継ぎ**: `facade.sh` は foreground の `exitcode.txt` を、`final-crosscheck-runner.sh` は依頼に保存された `exit_code` を、**そのまま**プロセス終了コードとしてジョブスケジューラへ返す。relay-gate 自身の終了コード体系(0 / 2 / 3 / 6)はこの中継経路には適用しない(arch CTR-002)
- **完了通知の受け渡し**: slot runner → `$RAPID_CROSSCHECK_RUNNER`(送信先は facade / background-rerun が環境変数で渡す)は `run_id` / `job_id` / `exit_code` を引数で渡す(成果物 URI は渡さない)。runner は自系統の通知だけを送り、相手側の状態を判断しない(条件「完了通知の系統独立」)。送信失敗は自動検知せず、実行ログの `WARN completion notice failed ...` を手がかりに運用者が同一引数で再実行する(条件「完了通知失敗の扱い」。冪等・先勝ちで完了結果は一度だけ登録される)
- **ジョブキューの受け渡し**: runner(dispatcher)→ worker は管理 DB の依頼レコード(`rapid_crosscheck_requests` / `final_crosscheck_requests`)で受け渡す。claim は `worker_id` + `lease_until` で排他する(arch CTP-004)
- **リランの受け渡し**: `background-rerun.sh` → slot runner は元の `execution-spec.json` を `--execution-spec <path>` で渡し、最新ジョブマップを再解決しない。新 run_id の `parent_run_id` に元 run_id を設定する。事前検証はファイル正本で行うため off でもリランできる。off 以外では、リラン由来の parallel_run は background slot の終端(exitcode.txt 公開)時に slot runner が、速報比較依頼だけを作り直した run は依頼の終端時に速報クロスチェック worker が COMPLETED にする
- **異常の受け渡し**: `hang-detector.sh` → 運用者は、終了コード(3 = 警告終了 / 6 = 失敗)をジョブスケジューラの障害通知で届け、標準エラーの alert 行に通知種別・run_id・role・job_id・経過時間を 1 件 1 行で載せる。運用者は alert 行の run_id と role をそのまま `abort-*` / `background-rerun.sh` / `rapid-crosscheck-result.sh` の引数に使える
- **成果物ルートの共有**: `facade/<run_id>/`(Runner Result)、`hang-detector-notified/`(通知済みの印。off のとき hang-detector が書き、housekeep が消す)、`housekeep-pending/`(削除待ちの置き場。housekeep だけが使う)は同じ成果物ルート直下に置く。run ディレクトリとして列挙するのは `facade/` 直下の run_id 形式のディレクトリだけ(`cli-command-contract.yaml` `shared_rules.artifact_root_entries`)

## UX 心理学に基づくインタラクション設計原則

### 適用する原則

| 原則 | 適用場面 | 具体的な設計 |
|------|---------|-----------|
| **意図的な壁 (Intentional Friction)** | `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh` の状態更新 | 現在状態(`cli-command-contract.yaml` の `stdout` 固定行。abort-blue / abort-green は run_id / job_id / role / mode / status / pid / started_at / artifact_dir の 8 行、abort-rapid-crosscheck / abort-final-crosscheck は run_id / job_id / role / status / worker_id / lease_until / started_at の 7 行)を表示した後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と対話確認する。`yes` 以外は状態を変えず終了コード 3 で終了する。非対話起動は `--yes` を明示したときだけ許可する |
| **認知負荷 (Cognitive Load)** | すべてのコマンドの stdout、hang-detector の alert 行 | 1 行 1 事実(`key=value`)で出す。1 コマンドの既定出力は 5〜8 行程度に収め、詳細(stdout / stderr 本文)は成果物ディレクトリのパスやレポート URI への参照に留める |
| **視覚的階層 (Visual Hierarchy)** | hang-detector の alert 行、stderr のメッセージ | alert 行は `alert: level=... kind=... run_id=... role=... job_id=... elapsed_minutes=...` の固定順で、重要度 → 種別 → 識別子 → 判断材料の順に読める。stderr は `error:` / `warn:` / `info:` の接頭辞で重要度を先頭に置く |
| **フレーミング効果 (Framing)** | 通知レベルの表現 | ハング疑いは「warning(静観可。正常終了することがある)」、実行エラー・比較異常は「error(対処要)」として、終了コード(警告終了 / 失敗)と `ui-design.md` の通知種別ごとの推奨対処で静観・対処の判断材料を渡す。同じ「異常」でも運用者の行動が変わるように表現を分ける |
| **デフォルト効果 (Default Bias)** | `hang_detect_limit_minutes` の導入時既定値、worker の `--once`、lease / poll の既定値 | 導入時は全ジョブ 60 分をジョブマップの既定にし、警告傾向が出そろってからジョブごとに調整する。lease 10 分 / poll 30 秒 / polling 60 秒 / 上限 8 時間は設定で上書きできるが、未指定でも安全側で動く |
| **ピーク・エンドの法則 (Peak-End Rule)** | 異常終了時の stderr、`background-rerun.sh` の成功時 stdout | 異常終了の最後の行を `error: {原因}` + 次の行に `hint: {次にやること}` で終え、運用者が次の一手を迷わない。リラン成功時は最後の行に `run_id={新 run_id}` と `parent_run_id={元 run_id}` を出し、追跡の起点を渡す |
| **段階的開示 (Progressive Disclosure)** | `rapid-crosscheck-result.sh`(`--show-output`)/ `hang-detect-trend.sh`(`--all`)/ `run-lineage.sh`(`--verbose`) | 既定は要約(依頼状態・両系の完了結果・exit_code)だけを出す。`rapid-crosscheck-result.sh` は比較ツールの stdout / stderr 本文を `--show-output` 指定時だけ末尾に出す。`hang-detect-trend.sh` は既定で `hang_suspected_count > 0` の行だけを出し `--all` で全行、`run-lineage.sh` は `--verbose` で各 run の成果物ディレクトリを stderr の `info:` に出す |
| **系列位置効果 (Serial Position Effect)** | alert 行、TSV 出力の列順 | alert 行の先頭に重要度と通知種別、続けて識別子、末尾に経過時間を置く。TSV は左端に識別子(run_id / job_id)、右端に判断材料(status / 警告回数 / 警告時経過時間)を置く |

- 選定基準: BtoB の社内運用系 CLI で、アクターは運用者と基盤適用設計者の 2 種。動機づけ系(ゲーミフィケーション・希少性・社会的証明)は適用しない
- 「ドハティの閾値」は CLI の応答 10 秒以内(NFR B.2.1.1)で代替し、進捗表示は行わない(非 TTY 起動が主のため)

## アクセシビリティ方針

- **非 TTY 前提**: すべてのコマンドはジョブスケジューラからの非 TTY 起動を主経路とする。TTY 判定・色・カーソル制御・進捗バーは使わない。対話プロンプト(abort-*)は stdin が TTY でないとき `--yes` が無ければ `error: interactive confirmation required (use --yes for non-interactive)` を stderr に出して終了コード 2 で終了する
- **色に依存しない出力**: 状態・重要度は文字列(`status=RUNNING`、`error:`、`level=warning`)だけで伝える。ANSI エスケープシーケンスは出力しない(NO_COLOR の考慮は不要)
- **スクリーンリーダー**: 1 行 1 事実、`key=value` の固定順で読み上げ順が意味順になる。表形式(TSV)はヘッダー行を必ず付け、列数を 8 列以内に収める。罫線文字・アスキーアートは使わない
- **言語**: stdout / stderr / ログのキー名とメッセージは英語(arch CTR-005)。運用者向けの対話プロンプト文言のみ方針資料どおり日本語(「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」)
- **日時**: stdout / stderr / ログ / 管理 DB の `*_at` 列の日時は、run_id / final_crosscheck_id の時刻部と同じホストのローカルタイムゾーン(ISO 8601 秒精度、タイムゾーン指示子なし。`2026-08-30T11:30:00`)に統一し、UTC や `Z` 付き・オフセット表記を混在させない(利用者決定 2026-09-07。arch CLP-002)。例外は `started-at.txt` / `aborted.txt` の中身(UTC `Z` 付き。表示・DB 転記時はローカルへ変換)と `RELAY_GATE_NOW` の入力(UTC `Z` 付き)だけ(`ui-design.md`「出力フォーマット」)
- **機械可読性**: すべての stdout は `grep` / `cut` / `awk` で処理できる(`key=value` または TSV)。JSON 出力は採用しない(jq 非依存)
