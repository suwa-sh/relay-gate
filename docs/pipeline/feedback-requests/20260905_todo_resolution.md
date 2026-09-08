---
schema_version: distillery.feedback-request/v1
feedback_id: 20260905_todo_resolution
created_at: 2026-09-05T14:30:00+09:00
source: distillery-impl
uc_id: c770d8f0
---

## CR-c770d8f0-001: feature flag のキーと値を元の方針資料の設定契約に戻す

- severity: blocker
- related_ids: [REQ-001, REQ-005]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/バリエーション.tsv, docs/rdra/latest/情報.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

元の方針資料「設定契約」は feature flag を次の 9 キーで定義している: `BLUE_MODE` / `GREEN_MODE` / `RAPID_CROSSCHECK_MODE`(値は `foreground` / `background` / `off`)/ `BLUE_IMPL` / `GREEN_IMPL` / `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER`。`RAPID_CROSSCHECK_MODE` は `foreground` と `background` のどちらでも「runner が完了通知を送信し速報管理 DB へ書き込む」、`off` で「完了通知を送信せず接続も書込みもしない」と表で定めている。execution-spec.json には「マップ版、実装版」を保存する。USDM SPEC-001-01 も同じ 9 キーを列挙している。

一方、現在の RDRA バリエーション「速報クロスチェックモード」は `on、off` の 2 値、情報「feature flag 設定」の属性は `RAPID_CROSSCHECK_MODE(on / off)、設定版` になっている。spec の CLI 契約 `config_files[feature-flag.env]` は 6 キー(`BLUE_MODE` / `GREEN_MODE` / `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_MODE(on|off)` / `CONFIG_VERSION`)だけを定義し、`BLUE_IMPL` / `GREEN_IMPL` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER` を「未知キー(warn)」と扱い、実装版をジョブマップの `impl_version` 列から取る構造にしている。rdra-feedback #10 は USDM 本文を契約側に合わせて書き換える提案をしている。

### 現在の仕様と問題

RDRA と spec が元の方針資料の設定契約から乖離している。元資料が定めるキーが「未知キー」として警告され、元資料どおりに書いた feature-flag.env が契約上は不完全になる。`BLUE_IMPL` / `GREEN_IMPL`(実装版の出所)と `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER`(完了通知先と worker 実体の割当)が失われ、代わりに元資料に無い `CONFIG_VERSION` とジョブマップ列 `impl_version` が発明されている。方針資料を第一の判断基準とする本プロジェクトのルールに反するため、rdra-feedback #10 の方向(USDM を契約へ寄せる)は採らない。

### 変更してほしいこと

- RDRA バリエーション「速報クロスチェックモード」の値を `foreground、background、off` の 3 値にし、説明を「foreground / background は runner が完了通知を送信し速報管理 DB へ書き込む。off は完了通知を送信せず速報管理 DB へ接続も書込みもしない」に改める。
- RDRA 情報「feature flag 設定」の属性を元資料の 9 キーに揃える(`BLUE_MODE` / `GREEN_MODE` / `RAPID_CROSSCHECK_MODE` / `BLUE_IMPL` / `GREEN_IMPL` / `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER`)。`設定版` は削除する。
- `BLUE_IMPL` / `GREEN_IMPL` を execution-spec.json の「実装版」の出所として RDRA 情報「実行設定(execution-spec)」の説明に明記する。`RAPID_CROSSCHECK_RUNNER` は slot runner が完了通知(blue-completed / green-completed)を送る先、`RAPID_CROSSCHECK_WORKER` は速報クロスチェック worker の実体パスとして扱う。
- USDM SPEC-001-01 の本文は変更せず、受け入れ条件に「Given 元資料の 9 キーで feature flag 設定を書く When 設定を検証する Then 未知キーの警告は出ない」を追加する。`RAPID_CROSSCHECK_MODE=on` と書いている受け入れ条件は `RAPID_CROSSCHECK_MODE=background` に改める。
- 下流(arch storage_mapping E-001、spec の CLI 契約 `config_files[feature-flag.env]` のキー・enum・validation_rules、ジョブマップの `impl_version` 列の削除、`CONFIG_VERSION` の削除、実行ログの `config_version=` 出力の削除)を追従させる。マップ版の出所はジョブマップ側の版として据え置いてよい。

### 完了条件

- RDRA バリエーション「速報クロスチェックモード」が `foreground、background、off` になっている。
- RDRA 情報「feature flag 設定」の属性が元資料の 9 キーと一致し、`設定版` が無い。
- USDM に `RAPID_CROSSCHECK_MODE=on` という表現が残っていない。
- spec の CLI 契約 `config_files[feature-flag.env].keys` が元資料の 9 キーと一致し、validation_rules に「未知キー」として元資料のキー名が列挙されていない。`CONFIG_VERSION` と `impl_version` が契約から消えている。

## CR-c770d8f0-002: ジョブマップ・クロスチェックジョブマップ・対象カタログの形式を元資料どおり CSV と元の列名にする

- severity: spec-gap
- related_ids: [REQ-004, REQ-005, REQ-006]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/情報.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

元の方針資料「利用イメージ」は slot ジョブマップを CSV ファイル(`legacy-job-map.csv` / `beam-job-map.csv`)とし、列を `job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes` と明示している。`fixed_params` は「JSON 配列を格納する CSV セル」で、固定引数の数と各引数に含まれる空白・カンマを維持し、空は `[]` と定めている。ローカル実行の green 側は `job_id,work_dir,script,fixed_params,hang_detect_limit_minutes` で host / user を持たない例も示している。

現在の spec の CLI 契約は TSV(`<role>-job-map.tsv` / `crosscheck-job-map.tsv` / `target-catalog.tsv`)とし、列名を `exec_user` / `script_path` / `fixed_args_json` に改名し、`credential_ref` / `map_version` / `impl_version` を必須列として追加している。RDRA 情報「ジョブマップ」の属性はファイル形式を定めていない。

### 現在の仕様と問題

適用側が元資料どおりに CSV と元の列名でジョブマップを用意すると、契約上は読めない。列名も元資料と別名のため、適用文書の読み替えが必要になる。元資料を第一の判断基準とするルールに反する。

### 変更してほしいこと

- RDRA 情報「ジョブマップ」の説明に「形式は CSV(1 行目ヘッダー、1 行 1 job_id)。固定引数は JSON 配列文字列を格納する CSV セルで、二重引用符で囲みセル内の二重引用符は二重化する」を追加する。属性名は元資料の列名(`job_id` / `host` / `user` / `work_dir` / `script` / `fixed_params` / `hang_detect_limit_minutes`)に揃える。`host` と `user` はローカル実行の slot では省略可とする。
- USDM REQ-004 配下の該当 SPEC に、CSV 形式と列名、`fixed_params` の JSON 配列セル規則を受け入れ条件として追加する。
- クロスチェックジョブマップと対象カタログも CSV に揃える(方針資料はクロスチェックの job map の形式を明示していないが、slot ジョブマップと同じ形式に統一する)。
- 認証情報の参照名(`credential_ref`)とマップ版(`map_version`)は元資料に無いため、末尾の任意列として許容する(必須にしない)。
- 下流(spec の CLI 契約 `config_files` のファイル名 `.csv`、列定義、`validate-config.sh` の検証規則、bash 単独で CSV のクォートを解析する規則の明記)を追従させる。

### 完了条件

- RDRA 情報「ジョブマップ」の属性名が元資料の列名と一致し、説明に CSV 形式と `fixed_params` セル規則が書かれている。
- spec の CLI 契約でジョブマップ・クロスチェックジョブマップ・対象カタログのファイル名が `.csv`、列名が元資料と一致している。`credential_ref` / `map_version` は任意列、`impl_version` は無い。
- CSV セルのクォート解析規則(二重引用符で囲む、内部の二重引用符は二重化)が契約に明記されている。

## CR-c770d8f0-003: run_id の形式をローカルタイムゾーンの時刻 + job_id + hex 乱数に確定する

- severity: improvement
- related_ids: [REQ-011, REQ-009]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/情報.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

元の方針資料のデータモデル ER 図は `run_id` の型を `uuid` と書いているが、形式の要件(発行方法・ソート性)は書いていない。現在の spec は `shared_rules.run_id` を `{UTC yyyymmddThhmmssZ}-{job_id}-{8 桁 hex 乱数}`(例 `20260830T113000Z-JOB001-3f9a1c2e`)と仮採用し、confidence low として todo(DIST-018)に登録している。RDRA 情報「並行稼働実行(parallel_run)」「実行設定(execution-spec)」は run_id の形式を定めていない。

### 現在の仕様と問題

run_id は成果物ディレクトリ名・管理 DB の主キー・リラン系譜の相関キーとして複数 tier が共有する算出規則であり、要件レベルで確定されていない。利用者の判断として「時刻付き形式は維持するが、時刻は運用者が読めるようローカルタイムゾーンにする」と決定した(元資料の `uuid` 表記は型の例示として扱い、UUID には戻さない)。

### 変更してほしいこと

- USDM REQ-011 配下に「run_id は `{ローカルタイムゾーンの yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}` の形式で発行する(例 `20260830T203000-JOB001-3f9a1c2e`。時刻部はホストのローカルタイムゾーン、タイムゾーン指示子は付けない)」を SPEC として追加し、受け入れ条件に「成果物ディレクトリ名と管理 DB の run_id が同じ値である」「管理 DB なし(`RAPID_CROSSCHECK_MODE=off`)でも facade 単独で発行できる」を含める。
- RDRA 情報「並行稼働実行(parallel_run)」の run_id 属性の説明に同じ形式を記す。
- 下流(spec の `shared_rules.run_id` の format / example / test_verification の正規表現、`final_crosscheck_id` の時刻部も同じローカル時刻形式、run_id の時刻部を UTC と説明している箇所、テスト用時刻注入 `RELAY_GATE_NOW` の扱いの整合)を追従させる。

### 完了条件

- USDM と RDRA に run_id の形式(ローカルタイムゾーン、`Z` 無し)が記載されている。
- spec の `shared_rules.run_id.format` が `{yyyymmddThhmmss(ローカル)}-{job_id}-{8 桁 hex}` になり、`confidence: low` の注記が外れている。

## CR-c770d8f0-004: RAPID_CROSSCHECK_MODE=off でも background slot の中止とリランが成立するよう成果物に中止マーカーを加える

- severity: blocker
- related_ids: [REQ-003, REQ-009, REQ-010, REQ-008]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/情報.tsv, docs/rdra/latest/状態.tsv, docs/rdra/latest/条件.tsv]

### 観測した事実

元の方針資料は次の 3 点を定めている。(1)「`RAPID_CROSSCHECK_MODE=off` の場合は parallel_run を作成せず、slot 実行と background 側リランは成果物ファイルだけで動作します」。(2)「`RUNNING` の background 実行は、運用者が明示中止してからリランします」「`RUNNING` の実行は受け付けません」。(3) abort-blue / abort-green は「対象 slot が `background` かつ `RUNNING` のときだけ中止できます」。

現在の spec(todo DIST-017)は off のとき abort-blue / abort-green を「管理 DB が無い旨を stderr に出して終了する(状態更新先が無い)」としている。RDRA 状態モデル「slot 実行」の ABORTED 遷移は「abort-blue / abort-green を実行して yes と答えたときだけ」で、状態の正本(ファイルか DB か)は定めていない。arch storage_mapping E-014 は slot 実行を「Runner Result(exitcode.txt)をファイル正本とし、速報有効時だけ管理 DB にも保持する二重マッピング」と仮採用している(todo DIST-009)。

### 現在の仕様と問題

off のとき、exitcode.txt が無い(RUNNING 相当の)background slot は、中止できず(abort-* がエラー終了)、リランもできない(RUNNING はリラン拒否)。元資料の (1)(2)(3) を同時に満たせない。原因は、ファイル正本側に「中止済み」を表す成果物が無いこと。

### 変更してほしいこと

- RDRA 情報「Runner Result」の属性に `aborted.txt`(中止日時を 1 行で保持。中止時のみ生成)を追加し、説明に「slot 実行の状態はファイル正本(exitcode.txt / aborted.txt の有無と値)から導出し、速報クロスチェック有効時は管理 DB にも同じ状態を保持する」を明記する。
- RDRA 状態モデル「slot 実行」の RUNNING → ABORTED 遷移の説明に「abort-blue / abort-green は成果物ディレクトリに aborted.txt を書く。`RAPID_CROSSCHECK_MODE` が off 以外なら管理 DB の状態も ABORTED に更新する」を追加する。
- RDRA 条件に「slot 実行の状態導出規則: exitcode.txt があれば SUCCEEDED(0)/ FAILED(非 0)、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING」を追加する。background 側リランとハング検知はこの規則で状態を判定する(aborted.txt がある監視対象は監視記録を終端する)。
- USDM REQ-010 の該当 SPEC に「Given `RAPID_CROSSCHECK_MODE=off` で background slot が RUNNING When abort-blue を実行して yes と答える Then aborted.txt が書かれ、background-rerun で同じ run をリランできる」を受け入れ条件として追加する。
- 下流(arch E-014 の rdb 側 confidence の確定、spec の abort-blue / abort-green / background-rerun / hang-detector の契約と UC spec)を追従させる。

### 完了条件

- RDRA 情報「Runner Result」に aborted.txt が含まれ、状態導出規則が条件に存在する。
- USDM に off モードでの中止 → リランの受け入れ条件が存在する。
- spec の abort-blue / abort-green 契約に「off では管理 DB が無い旨を出して終了する」という記述が残っていない。

## CR-c770d8f0-005: 速報完了通知の送信失敗は自動検知しないことを要件として明記する

- severity: spec-gap
- related_ids: [REQ-005, REQ-008]
- related_files: [docs/rdra/latest/条件.tsv, docs/usdm/latest/requirements.yaml]

### 観測した事実

元の方針資料「ハング検知」の検知条件は、exitcode.txt の有無と値、経過時間と hang_detect_limit_minutes、速報比較依頼の FAILED または比較 NG の 5 行だけで、slot runner から rapid-crosscheck-runner.sh への完了通知(blue-completed / green-completed)が失敗した場合の検知は書かれていない。現在の spec は通知失敗時に slot runner が実行ログに `WARN completion notice failed` を残し、復旧は運用者が rapid-crosscheck-runner.sh を同一引数で再実行する(冪等・先勝ち)としてスコープ外にしている(todo DIST-020、rdra-feedback #8)。RDRA にはこの前提を表す条件が無い。

### 現在の仕様と問題

spec が仮採用したスコープ外の判断が RDRA に無く、トレーサビリティ上で孤立している。要件として「自動検知しない」を明記しないと、後工程で片系完了のまま残った run の扱いが再び議論になる。

### 変更してほしいこと

- RDRA 条件に「完了通知の失敗は自動検知しない。slot runner は実行ログに警告を残し Runner Result と終了コードは変更しない。復旧は運用者が速報クロスチェック runner を同一引数で再実行する(冪等・先勝ち)」を追加し、関連 UC を「速報クロスチェック runner へ完了通知を送信する」とする。
- USDM REQ-005 の該当 SPEC に「Given 完了通知の送信が失敗した When slot runner が終了する Then 終了コードは実装スクリプトの exitcode のままで、実行ログに警告が残る」「Given 運用者が同一引数で完了通知を再送した Then 完了結果は一度だけ登録される」を受け入れ条件として追加する。

### 完了条件

- RDRA 条件に完了通知失敗の扱いが存在し、spec の「(spec 追加)」注記を外せる状態になっている。
- USDM に通知失敗時の受け入れ条件が存在する。

## CR-c770d8f0-006: 管理 DB を外部システムから relay-gate 内部のデータストアへ移す

- severity: improvement
- related_ids: [REQ-011, REQ-013]
- related_files: [docs/rdra/latest/外部システム.tsv, docs/rdra/latest/BUC.tsv, docs/rdra/latest/システム概要.json]

### 観測した事実

元の方針資料 C2 Container は「rapid-crosscheck job queue」「final-crosscheck job queue」を RelayGate のコンテナとして図示し、配置図では「PostgreSQL(RelayGate データ)」を relay-gate のデータとして置いている。一方で SSH 接続先は「実装固有の起動方式、ホスト、OS、プロトコルを slot の runner に閉じ込めます」と適用側の関心事にしている。現在の RDRA 外部システム.tsv は「管理 DB(RDB)」と「リモート実行ホスト(SSH)」の両方を外部システムとして登録している(todo DIST-001)。arch の BC 境界では管理 DB を内部データストアとして扱っている。

### 現在の仕様と問題

RDRA では外部、arch では内部という二重表現が残り、実装時の境界判断の混乱源になる。

### 変更してほしいこと

- RDRA 外部システム.tsv から「管理 DB(RDB)」を削除し、システム概要(または情報モデル)側で relay-gate 内部のジョブキュー兼管理 DB として保持する。BUC の関連先から管理 DB を外し、必要なら BUC の説明に内部データストアとして言及する。
- 「リモート実行ホスト(SSH)」は適用側の関心事として外部システムのまま維持する。

### 完了条件

- 外部システム.tsv に「管理 DB(RDB)」が無く、「リモート実行ホスト(SSH)」は残っている。
- システム概要または情報モデルに管理 DB が内部構成要素として記載されている。

## CR-c770d8f0-007: 情報モデルの属性 2 件を実態に合わせて整理する(調整記録の置き場、応答日時の削除)

- severity: improvement
- related_ids: [REQ-008, REQ-002, REQ-012]
- related_files: [docs/rdra/latest/情報.tsv]

### 観測した事実

rdra-feedback #1: RDRA 情報「ハング検知上限設定」は属性に「調整日時」「調整根拠(最後の警告の経過時間)」を持つが、spec はジョブマップの列に含めず、調整根拠は監視記録(警告時経過時間)から読み取り、記録の正本は適用構成文書またはコミット履歴とした。元の方針資料は「ジョブごとに最後の警告の経過時間を基準として hang_detect_limit_minutes を調整します」とだけ書き、調整の記録先は定めていない。

rdra-feedback #2: RDRA 情報「ジョブスケジューラ応答」は属性に「応答日時」を持つが、元の方針資料は facade が 3 ファイルを標準出力・標準エラー・終了コードとして中継するだけで時刻を持たず、実行履歴はジョブスケジューラの責務としている。

### 現在の仕様と問題

情報モデルの属性が spec の設計判断および元資料の責務分担と食い違い、トレーサビリティで未カバーになっている(網羅率 99.4% の未カバー 2 件)。

### 変更してほしいこと

- 情報「ハング検知上限設定」から「調整日時」「調整根拠」を外し、情報「適用構成文書」の属性(運用者の調整記録: 調整日時、調整根拠となる警告時経過時間)へ移す。
- 情報「ジョブスケジューラ応答」から「応答日時」を削除する。

### 完了条件

- 情報「ハング検知上限設定」に調整日時・調整根拠が無く、「適用構成文書」にある。
- 情報「ジョブスケジューラ応答」に応答日時が無い。

## CR-c770d8f0-008: 監視状態とハング検知判定結果の値集合を統一し、通知後・中止後の終端遷移を追加する

- severity: spec-gap
- related_ids: [REQ-008, REQ-010]
- related_files: [docs/rdra/latest/状態.tsv, docs/rdra/latest/バリエーション.tsv, docs/rdra/latest/情報.tsv]

### 観測した事実

rdra-feedback #3: 状態.tsv の「監視状態」は 6 値(監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了)だが、バリエーション.tsv の同名「監視状態」は 4 値(未検知、ハング疑い、通知済み、通知後正常終了)で一致しない。spec は状態.tsv を正として英字コード 6 値(NOT_TARGET / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED)を採用した。

rdra-feedback #7: 状態.tsv にハング疑い通知後に対象が終端した場合の遷移(HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED)が無く、通知済み run が再判定されず監視記録が未終端のまま残る欠陥があった。元の方針資料は「通知後に正常終了した実行についても、警告した経過時間を記録して通常処理の警告傾向を確認します」と定めている。

rdra-feedback #11: 実行中止フロー(abort-*)で ABORTED になった監視対象の監視記録が未終端のまま残る欠陥を防ぐため、spec は ABORTED を判定 COMPLETED として終端する仮採用を置いた。バリエーション「ハング検知判定結果」の値集合も spec の hang_judgement 6 値(NOT_TARGET / COMPLETED / MONITORING / HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR)と食い違う。元の方針資料「監視ジョブは ABORTED へ遷移させません」は実行状態についての記述であり、監視記録の終端とは矛盾しない。

### 現在の仕様と問題

RDRA 内で同名の値集合が二重定義され、spec の遷移が RDRA に存在しないため、状態遷移の正本が RDRA から spec に移ってしまっている。

### 変更してほしいこと

- バリエーション「監視状態」の値を状態モデル「監視状態」の 6 値に揃え、「通知後正常終了」は遷移(ハング疑い通知済み → 正常終了)の別名として説明列に記す。
- 状態モデル「監視状態」に遷移を追加する: ハング疑い通知済み → 比較異常通知済み(速報比較依頼が NG / FAILED)、ハング疑い通知済み → 実行エラー通知済み(background slot が非 0 終了)、ハング疑い通知済み → 正常終了(exitcode 0)、監視中 / ハング疑い通知済み → 正常終了(監視対象が ABORTED になったとき。中止済みとして終端)。遷移 UC は「background 実行の経過時間と終了状態を判定する」「ハング疑い・実行エラー・比較異常を通知する」。
- バリエーション「ハング検知判定結果」の値を 6 値(監視対象外 / 正常終了または中止済み / 監視中 / ハング疑い / 実行エラー / 比較異常)に揃える。
- 情報「監視記録」の monitor_status の値説明を上記と一致させる。

### 完了条件

- バリエーション.tsv と状態.tsv の「監視状態」の値集合が一致している。
- 状態.tsv にハング疑い通知後の 3 終端遷移と ABORTED 対象の終端遷移が存在する。
- バリエーション「ハング検知判定結果」が 6 値になっている。

## CR-c770d8f0-009: 並行稼働実行の状態遷移に STARTED → ABORTED とリラン由来 run の COMPLETED 遷移を追加する

- severity: spec-gap
- related_ids: [REQ-011, REQ-009, REQ-010]
- related_files: [docs/rdra/latest/状態.tsv]

### 観測した事実

rdra-feedback #4: 状態.tsv の「並行稼働実行」は RUNNING → ABORTED しか無い。facade が parallel_run を STARTED で作成した直後(RUNNING 更新前)に中止された実行を取りこぼさないため、spec の UC「実行を ABORTED へ遷移させる」は `status IN ('STARTED','RUNNING')` を条件にしている。

rdra-feedback #5: 状態.tsv の RUNNING → COMPLETED は「foreground slot の結果をジョブスケジューラへ中継する」だけが遷移 UC。background-rerun(--role rapid-crosscheck)で作成した parallel_run には foreground slot が無く、COMPLETED に到達する経路が未定義。元の方針資料は parallel_run.status の値と遷移を定めていない。

### 現在の仕様と問題

spec が仮採用した遷移が RDRA に無く、状態モデルの正本性が崩れている。

### 変更してほしいこと

- 状態モデル「並行稼働実行」に STARTED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」)を追加する。
- 状態モデル「並行稼働実行」の RUNNING → COMPLETED に遷移 UC「比較ツールでジョブ単位比較を実行して結果を登録する」を追加し、説明に「速報比較依頼だけを新規作成したリラン由来の parallel_run は、依頼が終端状態(SUCCEEDED / FAILED)になった時点で worker が COMPLETED にする」を記す。
- 既存の「元の execution-spec.json から復元して新しい run_id で起動する」経路の parallel_run(background slot のリラン)についても、COMPLETED に到達する遷移 UC を「実装スクリプトを実行して Runner Result を出力する」(background slot の終端時に runner が更新)として明記する。

### 完了条件

- 状態.tsv の「並行稼働実行」に STARTED → ABORTED が存在する。
- リラン由来の parallel_run が COMPLETED に到達する遷移 UC が状態.tsv に存在する。

## CR-c770d8f0-010: ハング検知定期ジョブの通知先・送信コマンド設定(hang-detector.env)を情報モデルと設定所有区分に追加する

- severity: spec-gap
- related_ids: [REQ-008, REQ-012, REQ-013]
- related_files: [docs/rdra/latest/情報.tsv, docs/rdra/latest/バリエーション.tsv]

### 観測した事実

rdra-feedback #6 / todo DIST-019: UC「ハング疑い・実行エラー・比較異常を通知する」は通知メールの送信手段と宛先の設定を要する。spec は OS 標準の mail / sendmail コマンドを tier-ops の gateway で呼び、宛先・件名プレフィックス・送信コマンド・DB 接続参照名を hang-detector 用 env 設定ファイル(`hang-detector.env`: `ALERT_MAIL_TO` / `ALERT_MAIL_CMD` / `ALERT_SUBJECT_PREFIX` / `HANG_DB_CONN_REF`)で指定する仮採用を置いた。RDRA の情報「通知メール」は宛先(運用者)を持つが、バリエーション「設定所有区分」(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 適用文書)に該当する置き場が無い。元の方針資料は「warning、error でメールを飛ばす」とだけ定め、送信手段と宛先の設定場所を定めていない。

### 現在の仕様と問題

spec が仮置きした設定ファイル契約が RDRA に無く、設定所有区分に穴がある。

### 変更してほしいこと

- 情報「ハング検知定期ジョブ設定」を適用構成管理コンテキストに新規追加する(属性: 通知先メールアドレス、送信コマンド、件名プレフィックス、管理 DB 接続参照名。関連: 通知メール、監視記録)。認証情報は値を置かず参照名のみとする。
- バリエーション「設定所有区分」に「ハング検知定期ジョブ設定」を追加し、所有者を基盤適用設計者とする。
- UC「ハング疑い・実行エラー・比較異常を通知する」の入力情報に「ハング検知定期ジョブ設定」を加える。

### 完了条件

- 情報.tsv に「ハング検知定期ジョブ設定」が存在する。
- バリエーション「設定所有区分」にハング検知定期ジョブ設定が含まれている。

## CR-c770d8f0-011: 比較結果の登録条件を条件モデルに追加する

- severity: improvement
- related_ids: [REQ-005, REQ-007]
- related_files: [docs/rdra/latest/条件.tsv]

### 観測した事実

rdra-feedback #12: spec は「comparison_results の登録条件」(比較結果は比較ツールを起動して終了コードを得たときだけ登録する。比較定義なし・起動失敗では登録せず依頼だけ FAILED で終端する)を条件名として新設したが、RDRA 条件.tsv に存在しないためトレーサビリティ集計で孤立している。元の方針資料は「クロスチェック依頼の状態は worker の exitcode に従う」「比較差分の詳細は comparison_result、stdout、stderr に保持します」と定めている。

### 現在の仕様と問題

spec 側だけにある条件名が RDRA に無く、要件網羅率に影響する。

### 変更してほしいこと

- 条件.tsv に「比較結果の登録条件: 比較結果(comparison_result)は比較ツールを起動して終了コードを得たときだけ登録する。比較定義なし・起動失敗では登録せず、依頼だけを FAILED(exit_code=6 相当、error_summary に理由)で終端する」を追加し、関連 UC を「比較ツールでジョブ単位比較を実行して結果を登録する」とする。

### 完了条件

- 条件.tsv に比較結果の登録条件が存在し、spec の「(spec 追加)」注記を外せる状態になっている。

## CR-c770d8f0-012: 低確信度で仮採用した非機能要求グレード 7 項目を既定値として確定する

- severity: improvement
- related_ids: [NFR-A.2.1.1, NFR-A.3.1.1, NFR-A.3.1.2, NFR-C.2.1.2, NFR-C.4.1.1, NFR-C.5.1.1, NFR-C.6.1.1]
- related_files: [docs/nfr/latest/nfr-grade.yaml]

### 観測した事実

nfr-grade.yaml の A.2.1.1(サーバ内冗長化 Lv2)、A.3.1.1(災害対策 Lv0)、A.3.1.2(業務継続 Lv0)、C.2.1.2(パッチ適用 Lv1)、C.4.1.1(テスト環境 Lv2)、C.5.1.1(サポート時間 Lv1)、C.6.1.1(ログ保管期間 Lv2)は confidence low で仮採用され、todo DIST-003〜008 に登録されている。arch CTP-009(運用体制)も C.5.1.1 を踏襲している(todo DIST-012)。元の方針資料はこれらの根拠となる機器構成・運用体制・保管期間を定めておらず、「warning / error でメールを飛ばし、静観してもらう運用を想定」とだけ書いている。

### 現在の仕様と問題

利用者の判断として、7 項目は仮採用値をそのまま「適用側で上書き可能な既定値」として確定した。confidence low のままでは後工程で再確認を求め続ける。

### 変更してほしいこと

- 上記 7 項目のグレードは変更せず、confidence を medium 以上に上げ、reason に「2026-09-05 に利用者が既定値として確定。適用先ごとに見直す運用パラメータ」を追記する。
- C.5.1.1 の reason に、元資料の「warning / error でメールを飛ばし静観してもらう運用」を根拠として記す。

### 完了条件

- 7 項目の confidence が low でなく、reason に確定日と「適用側で上書き可能な既定値」である旨が記載されている。
- グレード値は変更されていない。
