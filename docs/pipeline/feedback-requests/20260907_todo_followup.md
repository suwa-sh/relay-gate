---
schema_version: distillery.feedback-request/v1
feedback_id: 20260907_todo_followup
created_at: 2026-09-07T10:00:00+09:00
source: distillery-impl
uc_id: c770d8f0
---

## CR-c770d8f0-013: 速報クロスチェック設定(rapid-crosscheck.env)を情報モデルと設定所有区分に追加する

- severity: spec-gap
- related_ids: [REQ-005, REQ-007, REQ-013]
- related_files: [docs/rdra/latest/情報.tsv, docs/rdra/latest/バリエーション.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

spec の CLI 契約 `config_files` には速報クロスチェック用の設定ファイル `rapid-crosscheck.env`(`RAPID_DB_CONN_REF` = 管理 DB 接続の参照名、`RAPID_LEASE_SEC` = lease 期間、`RAPID_POLL_INTERVAL_SEC` = worker の poll 間隔)があり、facade / slot runner / rapid-crosscheck-runner / rapid-crosscheck-worker が読む。一方、RDRA の情報モデルには対応する情報が無く、バリエーション「設定所有区分」にも該当する区分が無い(todo DIST-023)。同型の hang-detector.env は feedback `20260905_todo_resolution` の CR-c770d8f0-010 で情報「ハング検知定期ジョブ設定」として追加済み。元の方針資料は「速報クロスチェック用の DB 接続設定なしで slot 実行できます」と DB 接続設定の存在を前提にしているが、設定の置き場は定めていない。

### 現在の仕様と問題

spec 側だけにある設定ファイル契約が RDRA に無く、トレーサビリティに乗らない。前回の spec 生成で `_model-summary.yaml` に誤った rdra_info を紐づけていた経緯があり、正しい参照先が必要。

### 変更してほしいこと

- 情報「速報クロスチェック設定」を適用構成管理コンテキストに新規追加する(属性: 管理 DB 接続参照名、lease 期間(秒)、worker の poll 間隔(秒)。関連: 速報比較依頼、並行稼働実行、完了通知。所有者: 基盤適用設計者)。認証情報は値を置かず参照名のみ。
- バリエーション「設定所有区分」に「速報クロスチェック設定」を追加する。
- 関連 UC(「速報クロスチェック runner へ完了通知を送信する」「両系成功時に速報比較依頼を作成する」「速報比較依頼を claim する」「slot 実行モードを選択して runner を起動する」)の入力情報に「速報クロスチェック設定」を加える。
- 下流(spec の `config_files[rapid-crosscheck.env]` の owner / defined_in_uc、`_model-summary.yaml` の rdra_info)を追従させる。

### 完了条件

- 情報.tsv に「速報クロスチェック設定」が存在し、設定所有区分に含まれている。
- spec の `config_files[rapid-crosscheck.env]` が RDRA 情報「速報クロスチェック設定」を参照している。

## CR-c770d8f0-014: 中止済みの run では速報比較依頼を作成せず、中止時に未着手の速報比較依頼も ABORTED にする

- severity: spec-gap
- related_ids: [REQ-005, REQ-010, REQ-011]
- related_files: [docs/rdra/latest/条件.tsv, docs/rdra/latest/状態.tsv, docs/usdm/latest/requirements.yaml]

### 観測した事実

feedback `20260905_todo_resolution` の CR-c770d8f0-004 で、slot 実行の状態導出規則を「exitcode.txt があれば SUCCEEDED / FAILED、無く aborted.txt があれば ABORTED。両方あれば exitcode.txt 優先」と定めた。運用者が abort-blue / abort-green で中止した後にプロセスの停止が不完全で実装が走り切ると、runner は exitcode.txt を公開し、通常どおり rapid-crosscheck-runner へ完了通知(blue-completed / green-completed)を送る。もう片方の slot が成功済みなら、現在の条件「速報比較依頼の作成条件(両系成功)」により中止した run の速報比較依頼が作成される(todo DIST-024)。また、両 slot 完了直後に中止した場合、既に REQUESTED で作成済みの速報比較依頼は abort-blue / abort-green の対象外(abort-rapid-crosscheck は RUNNING の依頼だけを対象)で、worker が拾って比較を実行する。

元の方針資料は「blue / green runner は相手側の状態や比較依頼を判断しません。比較規約は rapid-crosscheck-runner.sh と rapid-crosscheck-worker.sh に閉じ込めます」と定め、abort-blue / abort-green は「対象 slot を ABORTED へ遷移させる」、RDRA 状態モデルは「運用者が中止スクリプトで slot 実行または比較依頼を明示中止したとき、並行稼働実行も ABORTED にする」としている。

### 現在の仕様と問題

利用者の決定は「abort したなら速報クロスチェックは実施しない。判断は責務が自然な場所に持たせる」。比較の要否判断を slot runner に持たせるのは元資料の責務分担に反するため、判断は速報クロスチェック側(dispatcher = rapid-crosscheck-runner)に置く。加えて中止時点で未着手の依頼を放置すると、両 slot 完了直後に中止した場合だけ比較が走る抜けが残るため、abort-blue / abort-green の責務を「slot の中止」から「run の中止(未着手の速報比較依頼を含む)」へ半歩広げる。

### 変更してほしいこと

- 条件「速報比較依頼の作成条件」(または同等の既存条件)に「並行稼働実行(parallel_run)が ABORTED の run では、完了通知を受けても速報比較依頼を作成しない。完了事実(blue_status / green_status と成果物 URI)は記録し、実行ログに警告を残す」を追加する。判断主体は速報クロスチェック runner(dispatcher)。slot runner は自 slot の中止状態を判断せず通常どおり完了通知を送る。
- UC「実行を ABORTED へ遷移させる」(abort-blue / abort-green)の説明に「対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があれば、それも ABORTED にする。CLAIMED / RUNNING の依頼は abort-rapid-crosscheck の対象」を追加する。状態モデル「クロスチェック依頼」に REQUESTED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」。速報比較依頼のみ)を追加する。
- USDM REQ-005 / REQ-010 の該当 SPEC に受け入れ条件を追加する: 「Given 並行稼働実行が ABORTED When 後から完了通知を受ける Then 速報比較依頼は作成されず、完了事実だけが記録される」「Given REQUESTED の速報比較依頼がある run When abort-blue または abort-green を実行して yes と答える Then その依頼も ABORTED になる」「Given 中止した run を background-rerun でリランした When 新しい run の両系が成功する Then 新しい run_id で速報比較依頼が作成される」。
- 下流(arch の比較規約・abort 方針、spec の rapid-crosscheck-runner / abort-blue / abort-green / worker の契約と UC spec、rdb-schema の遷移注記)を追従させる。`RAPID_CROSSCHECK_MODE=off` では完了通知も比較依頼も存在しないため、この規則は速報有効時だけに適用される。

### 完了条件

- 条件.tsv に「ABORTED の run では速報比較依頼を作成しない」規則が存在し、判断主体が速報クロスチェック runner であることが読み取れる。
- 状態.tsv の「クロスチェック依頼」に REQUESTED → ABORTED(abort-blue / abort-green による未着手依頼の中止)が存在する。
- USDM に上記 3 つの受け入れ条件が存在する。
- spec の rapid-crosscheck-runner 契約に ABORTED run の扱い、abort-blue / abort-green 契約に未着手依頼の ABORTED 化が記載されている。

## CR-c770d8f0-015: 実行ログの日時をホストのローカルタイムゾーンに統一する

- severity: improvement
- related_ids: [ARCH-CLP-002, REQ-012]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

feedback `20260905_todo_resolution` の CR-c770d8f0-003 で run_id の時刻部を「ホストのローカルタイムゾーン、タイムゾーン指示子なし」と決定した。一方、arch のログ方針 CLP-002 は実行ログの日時を UTC(`Z` 付き ISO 8601)で統一しており、spec の実行ログ行書式 `{script} {run_id} {UTC 日時} {LEVEL} {message}` と管理 DB の `*_at` 列もそれに従う。arch stage と spec stage の両方が「run_id の時刻部とログ日時の時刻軸が食い違う」を確認推奨項目として返した(todo DIST-022)。元の方針資料は日時のタイムゾーンを定めていない。

### 現在の仕様と問題

障害調査で run_id(ローカル時刻)と実行ログ行(UTC)を突き合わせるとき、運用者が時差を読み替える必要がある。run_id をローカル時刻にした理由(運用者が読める)は実行ログにも当てはまる。

### 変更してほしいこと

- arch CLP-002 のログ日時を「ホストのローカルタイムゾーン、ISO 8601 秒精度、タイムゾーン指示子なし(run_id の時刻部と同じ時刻軸)」に改める。管理 DB の `*_at` 列は RDB のタイムスタンプ型に委ね、CLI の stdout に出す日時もローカル時刻で表示する。
- テスト用の時刻注入 `RELAY_GATE_NOW` の入力形式は UTC の `Z` 付きのまま受け付け、内部でローカル時刻へ変換する規則を維持する(spec 既存の記述を確認して整合させる)。
- 下流(spec の execution_log 行書式、`shared_rules` の日時説明、各 UC spec / tier-*.md の例示、data-visualization の日時列)を追従させる。

### 完了条件

- arch-design.yaml の CLP-002 がローカルタイムゾーンを規定し、UTC 統一の記述が無い。
- spec の実行ログ行書式と例示がローカル時刻(`Z` 無し)になっている。
