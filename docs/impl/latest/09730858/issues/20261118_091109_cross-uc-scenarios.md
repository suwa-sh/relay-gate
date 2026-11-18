# UC 横断 Scenario 一覧(S2 test-scaffold 起票)

- uc_id: 09730858(slot 実行モードを選択して runner を起動する / select-slot-mode-and-launch-runners)
- 起票 stage: S2 test-scaffold
- 目的: UC BDD(`features/uc/select-slot-mode-and-launch-runners.feature`、19 件)・tier BDD(`facade/features/select-slot-mode-and-launch-runners.feature`、18 件)・対象 ATDD(14 件)の Given / When / Then ごとに担当 UC を判定し、他 UC の責務を含む Scenario を着手前に一覧化する。S4 / S6 / S7 でのハーネス注入の要否を決める
- 種別: 仕様疑義ではなく責務分担の記録(4 だけは扱いの決定が要る。実装の blocker ではない)
- 扱いの前例: `docs/impl/latest/65b09d93/issues/20261118_012630_cross-uc-scenarios.md`

## 判定結果の要約

| # | 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|---|
| 1 | UC BDD | 新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03) | Then 4 行目(green/ に started-at.txt が存在する) | 要(テスト用 runner が started-at.txt を書く) |
| 2 | UC BDD | RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06) | Then 2 行目の後半(終了コードは foreground の exitcode.txt の値)/ Then 3 行目(blue/ と green/ に started-at.txt) | 要(テスト用 runner が started-at.txt と exitcode.txt を書く) |
| 3 | UC BDD | background を先に起動し foreground だけを待機する(SPEC-002-01) | Given 2 行目(green の実装スクリプトは 600 秒、blue は 5 秒で終了する)/ Then 2 行目(green/exitcode.txt は存在しない) | 要(テスト用 runner が実装スクリプトの代わりに待つ) |
| 4 | UC BDD | 値が空のジョブマップの場所のキーがある slot の runner は固定の名前のジョブマップで実行先を解決する(SPEC-004-01) | Given(標準の slot runner を割り当てる)/ Then 2 行目(execution-spec.json の slots.green)/ Then 3 行目(green/stderr.log) | 決定が要る(下記) |
| 5 | UC BDD | 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01) | Given 2 行目(両 slot のジョブマップに JOB001 の行) | 不要(facade はジョブマップを検査しない。置くだけ) |
| 6 | ATDD | SPEC-001-04-2 | Then(facade と比較規約を変更せずに並行稼働できる)の「比較規約」 | 不要(判定のしかたを下記に固定する) |
| 7 | ATDD | SPEC-011-04-1 | 割り当てが UC「execution-spec.json を確定保存する」(43850d68)と重なる | 不要(この UC で判定できる) |
| 8 | 先行 UC の feature | assign-slot-runner-scripts の facade.sh を起動する 3 Scenario(UC BDD 2 件・tier BDD 1 件) | この UC が facade.sh を作ると保留(skipped)が外れる | 不要(この UC の S4 / S6 で step を実装する) |

上記以外の Scenario(UC BDD 14 件、tier BDD 18 件、ATDD 12 件)は、Then がすべて facade.sh の終了コード・stderr・実行ログ・runner の起動記録(引数と環境変数)・管理 DB の行・成果物ディレクトリの有無だけを判定しており、この UC の責務に閉じる。

## 仕様の記載と担当 UC の判定

### 1・2. started-at.txt と exitcode.txt

| 行 | 文言(要約) | 担当 UC の判定 |
|---|---|---|
| Then | facade/<run_id>/green/ に started-at.txt が存在する | started-at.txt を書くのは runner(spec.md 状態遷移一覧「slot 実行」: runner が started-at.txt を出力)。UC「実装スクリプトを実行して Runner Result を出力する」の担当。この UC が作るのは role ディレクトリまで |
| Then | 終了コードは foreground の exitcode.txt の値である | exitcode.txt を書くのは runner。値を終了コードにするのは tier-facade.md の出力契約でこの UC の正常終了と書かれている(stdout / stderr の中継は UC「foreground slot の結果をジョブスケジューラへ中継する」) |

この UC の時点で標準の slot runner は `--help` 以外は仮の応答なので、started-at.txt / exitcode.txt を書くテスト用 runner(一時ディレクトリに置く実スクリプト)を step が置く。Then は「facade が runner を起動し、runner が書いた結果を facade が読む」ことの確認になる。

### 3. 実装スクリプトの実行時間

| 行 | 文言(要約) | 担当 UC の判定 |
|---|---|---|
| Given | green の実装スクリプトは 600 秒、blue の実装スクリプトは 5 秒で終了する | 実装スクリプトを起動するのは runner(後続 UC)。この UC ではテスト用 runner が同じ時間だけ待つ |
| Then | facade は blue の終了後 10 秒以内に終了する | この UC(foreground の PID だけを待機する)。600 秒の green を待たないことを確かめる時間で、仕様のシナリオが定める振る舞い |
| Then | facade 終了時点で green/exitcode.txt は存在しない(green は実行中) | この UC(background を待たない)。exitcode.txt を書くのはテスト用 runner |

実装で決めること: 600 秒待つ green のテスト用 runner は、Scenario の終了時に step が止める(PID を記録して後始末で kill する。プロセスを残さない)。

### 4. 標準の slot runner と execution-spec.json(決定が要る)

| 行 | 文言(要約) | 担当 UC の判定 |
|---|---|---|
| Given | 標準の slot runner /opt/relay-gate/runners/standard-runner.sh を BLUE_RUNNER / GREEN_RUNNER に割り当てる | 標準の slot runner の中身(解決・実行・結果の出力)は後続 UC。現時点では `--help` 以外は仮の応答(引数の誤り 2、正しい引数 6) |
| Then 1 行目 | green runner は環境変数 GREEN_JOB_MAP_CSV=/etc/relay-gate/green-job-map.csv を受け取って起動される(空の値は渡らない) | この UC(facade が場所を決めて渡す)。ただし標準の slot runner は受け取った環境変数を記録しないため、そのままでは観測できない |
| Then 2 行目 | execution-spec.json の slots.green は script=… work_dir=… hang_detect_limit_minutes=60 である | UC「ジョブマップで JOB_ID から実行先を解決する」(7c41c7cd)と UC「execution-spec.json を確定保存する」(43850d68) |
| Then 3 行目 | green/stderr.log に "error: job map not found" で始まる行は無い | runner の担当(同上の後続 UC) |

spec.md「関連 USDM」の REQ-004 行の注記も、この Scenario を「起動側(facade が場所を決めて runner へ渡す)」とし、「受け取った場所で実行先を解決する側は UC〈ジョブマップで JOB_ID から実行先を解決する〉で覆う」と書いている。Then 2・3 行目はその後続 UC の判定にあたる。

| 案 | 内容 | 長所 | 短所 |
|---|---|---|---|
| A(推奨) | この UC の S6 では Then 1 行目だけを判定する。標準の slot runner の前に、受け取った環境変数を記録してから標準の slot runner へ処理を渡すテスト用の包みを置く。Then 2・3 行目は、標準の slot runner が execution-spec.json を作れるようになるまで(後続 UC の完了まで)step が保留(skipped)を返し、後続 UC の S6 で判定する。先行 UC の facade.sh の扱いと同じ | 仕様を変えずに進められる。この UC の担当(場所を渡す)は今回確かめられる。同じ内容は tier BDD「値が空の GREEN_JOB_MAP_CSV の行がある設定で green の runner へ既定の場所を渡す」でも判定する | この Scenario は今回 passed にならず skipped が残る。S6 のゲートで「保留 1 件」を認める判断が要る |
| B | S8 で仕様の変更要求を出し、Then 2・3 行目を UC「ジョブマップで JOB_ID から実行先を解決する」の Scenario へ移す。この UC には Then 1 行目だけを残す | 各 UC のゲートが自分の担当だけで閉じる | 仕様の変更要求の往復が要る |
| C | execution-spec.json と stderr.log を書くスタブを標準の slot runner の代わりに置いて green にする | 今回 passed になる | 判定対象(標準の slot runner の解決)をスタブに置き換えるので、何も確かめないことになる(採らない) |

### 5. ジョブマップの行

Given「両 slot のジョブマップに job_id=JOB001 の行がある」は、runner が実行先を解決するための前提(後続 UC)。facade はジョブマップの存在を検査しない(tier-facade.md)。step はファイルを置くだけで、この UC の Then には影響しない。

### 6. ATDD SPEC-001-04-2(比較規約)

| 行 | 文言 | 判定のしかた |
|---|---|---|
| Given / When | green runner を次世代実装用に差し替える / feature flag と runner 設定だけを変更する | テスト用の runner を 2 つ置き、feature-flag.env の GREEN_RUNNER(と GREEN_IMPL)だけを書き換える |
| Then | facade と比較規約を変更せずに並行稼働できる | (a) 書き換えの前後で facade.sh とその本体(facade/bin・facade/src・facade/lib・facade/runners)のファイルの内容が同じ、(b) 書き換え後の facade.sh の起動で差し替えた runner が runner IF で起動される、の 2 点を実体で判定する。「比較規約」(比較定義・比較ツール)はクロスチェックの UC の担当で、この UC では触れていないこと((a) に含まれない設定ファイルを書き換えていないこと)までを見る |

### 7. ATDD SPEC-011-04-1

uc-map では UC「execution-spec.json を確定保存する」(43850d68)の atdd_scenarios にも載っている。文言(run を開始した / 成果物ディレクトリ名と管理 DB の parallel_run.run_id を確認する / 同じ値である)はこの UC だけで判定できる。step はこの UC が定義し、43850d68 は同じ step を再利用する。

### 8. 先行 UC の保留が外れる

`facade/features/steps/assign-slot-runner-scripts.steps.js`(1 Scenario)と `features/uc/steps/assign-slot-runner-scripts.steps.js`(2 Scenario)の facade.sh を起動する step は、`facade/bin/facade.sh` が無い間 skipped を返し、有ると `not implemented` で落ちる。この UC の S4 で facade.sh を作った時点で、先行 UC の feature が赤くなる。この UC の S4(tier BDD の 1 件)と S6(UC BDD の 2 件)で、その step の中身を実装する。

UC BDD の「runner 実体を差し替えても facade は変更不要である(SPEC-001-04)」の Then 2 行目(green/ に Runner Result の 3 ファイルが揃う)は、step が置く自作の runner スタブが 3 ファイルを書くので、この UC の完了時点で判定できる。

## 仕様に書かれていない前提(step が補うもの)

仕様の Given は要点だけを書いている。次の前提は step が補う。仕様の変更は求めない(先行 UC と同じ扱い)。

| 対象 | 仕様の Given に無いもの | step が補う内容 |
|---|---|---|
| RAPID_CROSSCHECK_MODE が off 以外の UC BDD(9 件。うち 1 件は管理 DB が停止している前提)と tier BDD の一部 | 管理 DB が起動していること、rapid-crosscheck.env があること、RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の実体 | 一時 PostgreSQL(initdb + pg_ctl)を起動し、rapid-crosscheck.env と実行可能なスタブを置く |
| mode だけを書いた Given(多数) | BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER の値 | 有効な値とテスト用 runner を補う(書かれた値は変えない) |
| UC BDD「確報クロスチェックを起動しない」 | mode の値、「起動されない」の観測方法 | 有効な並行稼働の設定を補い、配置ディレクトリに記録用の final-crosscheck-runner.sh を置いて起動記録が無いことを見る |
| UC BDD「未知の実行モードは拒否する」 | RAPID_CROSSCHECK_MODE の行 | 有効な値を補う(補わないと、最初の違反が別のキーになり得る) |
| /etc/relay-gate・/opt/relay-gate・/work | 実在のパス | World の sandbox() で一時ディレクトリの下に置く |

## 実装で判明した事実

- S2 時点では全 step が not implemented の skeleton である。上記の横断部分も skeleton として転写した(転写ルールにより意訳・削除しない)
- 管理 DB のテスト用ハーネス(一時 PostgreSQL)は、リポジトリにまだ無い(facade/・ops/・features/ のどこにも initdb / pg_ctl を使うコードが無い)。`ops/migrations/` も空で、テーブルを作る DDL が無い
- 参照名(RAPID_DB_CONN_REF)から接続情報への解決は、CLI 契約 conventions.credentials が「適用側の運用手順(DB クライアントの接続設定)に委ねる」としている。facade が RDB クライアントへ参照名をどう渡すかは仕様に無い

## 提案

- S4(tier BDD): 一時 PostgreSQL のハーネスを `facade/features/` と `facade/test/` の補助として作る。テーブルの DDL は契約の生成物 `packages/contracts/management-db/schema.json` から作り、暫定である旨を先頭に書く(test-strategy.md「テスト用 DDL は正本ではない」)
- S4(前提の記録): RDB クライアントの呼び出し方(コマンド名、参照名の渡し方)は、実装者が補った前提として AssumptionRecord に書く。候補: `psql` を PATH から探し、参照名を接続サービス名として渡す(tier BDD の「RDB クライアント CLI のパスにラッパーを置く」「ラッパーの記録には参照名 mgmt-db がある」と両立する)
- S6(UC BDD の 1〜3): テスト用 runner を注入する。注入箇所にこのファイルのパスを書く
- S6(UC BDD の 4): 上の案 A / B のどちらにするかを決めてから着手する
- S7(ATDD の 6・7): 上表の判定のしかたで実装する
- S8(feedback): 4 の Then の責務分離を仕様側へ要求するかを検討する(案 B を採る場合)
