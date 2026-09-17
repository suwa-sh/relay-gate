# 20260917_004437_config_confirmed_atdd_mapping_all_ucs

全 32 UC の UC→ATDD マッピングを Scenario(受け入れ基準)単位で一括確定した。

## 選択した方針

| 問い | 選択 |
|---|---|
| A ATDD の Given に後続 UC のコマンド(abort-blue / abort-green / abort-rapid-crosscheck / background-rerun)が出る基準を、DB 行・成果物ファイルを直接用意して振る舞い所有 UC で検証するか、実コマンドを呼ぶのでそのコマンドを実装する UC で検証するか | DB 行・ファイルを直接用意して振る舞い所有 UC で検証する |
| B facade 起動系の基準を、runner をスタブにして facade 起動 UC(slot 実行モードを選択して runner を起動する)で検証するか、実 runner を要求するので runner 実装 UC(実装スクリプトを実行して Runner Result を出力する)以降で検証するか | runner をスタブにして facade 起動 UC で検証する |
| C 統合的な確認 UC(業務ジョブの実行結果を確認する / 切り替えた運用モードで業務ジョブを実行する)を primary にするか、also(補助)にとどめるか | also にとどめ、振る舞い所有 UC(中継 UC)を primary にする |
| D 速報・確報に共通する依頼ライフサイクルの基準(SPEC-007-01 / 007-02)を、実装順で先に来る確報 worker(claim / 全量比較)で検証するか、速報 worker(claim / ジョブ単位比較)で検証するか | 確報 worker で検証する(実装順で先) |
| E 振る舞いを持たない、または実行時に観測できない基準(設定所有者の契約記載照合 / worker 実体の flag 解決 / 適用構成文書への調整記録 / 全スクリプト不変の統合確認)を、matrix の配置どおり UC に紐づけて low confidence で残すか、SPEC-011-05 と同じく primary null(モデル・契約整合)にするか | matrix の配置どおり UC に紐づける(low / medium) |

## UC 別の件数(実装順)

| # | UC | primary | also | atdd_scenarios |
|---|---|---|---|---|
| 1 | feature flag を設定する | 1 | 0 | 1 |
| 2 | slot ごとのジョブマップを定義する | 2 | 0 | 2 |
| 3 | クロスチェックのジョブマップと比較定義を定義する | 1 | 0 | 1 |
| 4 | slot runner の実体スクリプトを割り当てる | 0 | 0 | 0 |
| 5 | slot 実行モードを選択して runner を起動する | 14 | 0 | 14 |
| 6 | ジョブマップで JOB_ID から実行先を解決する | 7 | 0 | 7 |
| 7 | execution-spec.json を確定保存する | 3 | 1 | 4 |
| 8 | 実装スクリプトを実行して Runner Result を出力する | 8 | 4 | 12 |
| 9 | foreground slot の結果をジョブスケジューラへ中継する | 9 | 1 | 10 |
| 10 | 速報クロスチェック runner へ完了通知を送信する | 6 | 1 | 7 |
| 11 | 確報比較依頼を登録して終端状態まで待機する | 2 | 0 | 2 |
| 12 | 業務ジョブの実行結果を確認する | 0 | 6 | 6 |
| 13 | 両系成功時に速報比較依頼を作成する | 10 | 1 | 11 |
| 14 | 確報比較依頼を claim する | 2 | 0 | 2 |
| 15 | 速報比較依頼を claim する | 2 | 2 | 4 |
| 16 | 比較ツールで日次全量比較を実行して結果を保存する | 3 | 1 | 4 |
| 17 | 比較ツールでジョブ単位比較を実行して結果を登録する | 8 | 1 | 9 |
| 18 | 保存済みの確報結果をジョブスケジューラへ返す | 3 | 0 | 3 |
| 19 | 速報比較結果を参照する | 0 | 1 | 1 |
| 20 | 確報クロスチェック結果を確認する | 0 | 0 | 0 |
| 21 | 現在状態を確認して停止確認に応答する | 1 | 0 | 1 |
| 22 | background 実行の経過時間と終了状態を判定する | 3 | 0 | 3 |
| 23 | ハング疑い・実行エラー・比較異常を通知する | 9 | 1 | 10 |
| 24 | 監視記録を保存する | 4 | 2 | 6 |
| 25 | 実行を ABORTED へ遷移させる | 12 | 1 | 13 |
| 26 | リラン対象を検証する | 3 | 0 | 3 |
| 27 | background 異常の通知メールを受け取る | 0 | 1 | 1 |
| 28 | hang_detect_limit_minutes をジョブごとに調整する | 0 | 2 | 2 |
| 29 | 元の execution-spec.json から復元して新しい run_id で起動する | 3 | 2 | 5 |
| 30 | 速報比較依頼だけを新規作成する | 1 | 1 | 2 |
| 31 | 切り替えた運用モードで業務ジョブを実行する | 1 | 7 | 8 |
| 32 | リラン結果を parent_run_id で追跡する | 1 | 0 | 1 |

## どこにも付けない基準(3)

- SPEC-008-03-5: 監視状態の 6 値がモデル間で一致
- SPEC-011-05-1: 管理 DB は外部システムに含めない
- SPEC-011-05-2: SSH ホストは外部システムのまま

## Scenario 別の付け先と根拠

| Scenario | ラベル | primary | also | 確信 | 根拠 |
|---|---|---|---|---|---|
| SPEC-001-01-1 | blue 前面・green 背面で起動する | 5 slot 実行モードを選択して runner を起動する | 31 切り替えた運用モードで業務ジョブを実行する | high | UC-02 の BDD「並行稼働モードで blue foreground と green background を起動する」が対応。facade.sh が $BLUE_RUNNER / $GREEN_RUNNER を --mode 付きで起動することをスタブ runner で観測できる |
| SPEC-001-01-2 | off の slot は起動しない | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の BDD「off の slot は起動しない」が対応(runner 未起動と slot ディレクトリ未作成を観測) |
| SPEC-001-01-3 | 確報クロスチェックを起動しない | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の BDD「確報クロスチェックを起動しない」が対応(final-crosscheck-runner.sh が起動されないこと) |
| SPEC-001-01-4 | 9 キー設定で未知キー警告なし | 1 feature flag を設定する |  | high | UC-29 の BDD「元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する」が対応。validate-config.sh --feature-flag の stderr に warn: unknown key が出ない |
| SPEC-001-01-5 | 実装版は BLUE/GREEN_IMPL 由来 | 7 execution-spec.json を確定保存する |  | high | UC-04 の BDD「run 開始時に自 slot の節を保存する」(impl_version は GREEN_IMPL の値)/「ローカル実行と任意列なしのジョブマップでは…null で保存する」(BLUE_IMPL)が対応。execution-spec.json の impl_version の出所を観測 |
| SPEC-001-01-6 | 完了通知先と worker を flag で解決 | 10 速報クロスチェック runner へ完了通知を送信する |  | medium | UC-08 の BDD「blue の完了通知が rapid_runs に登録される」(送信先は環境変数 RAPID_CROSSCHECK_RUNNER)が対応。後半「worker の実体は RAPID_CROSSCHECK_WORKER で解決される」は実行時の起動経路が無く、UC-29 の validate-config.sh(速報 runner と worker の実体が必須)で検証する定義側の話なので、Then 後半の観測方法は要確認 |
| SPEC-001-02-1 | 両 slot foreground を拒否する | 5 slot 実行モードを選択して runner を起動する | 31 切り替えた運用モードで業務ジョブを実行する | high | UC-02 の BDD「両 slot foreground は入力検証で拒否する」が対応(終了コード 2、両 runner 未起動)。UC-28「誤った運用モード設定は業務ジョブを起動せずに止まる」で再検証できる |
| SPEC-001-03-1 | 並行稼働で blue の結果を返す | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する / 31 切り替えた運用モードで業務ジョブを実行する | high | UC-06 の BDD「foreground の 3 ファイルをそのまま中継する」が対応。「blue の結果が返る」は facade の中継(UC-06)で初めて観測できる。UC-01「並行稼働中の応答は blue の結果だけである」/ UC-28「並行稼働モードで業務ジョブを実行する」で再検証 |
| SPEC-001-03-2 | 単独本番で green の結果を返す | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する / 31 切り替えた運用モードで業務ジョブを実行する | high | UC-02「新実装の単独本番モードでは green だけを起動し管理 DB に触れない」+ UC-06 の中継で green の結果が返る。速報が動作しないことは off 時に完了通知を送らない runner(UC-05)で担保。UC-01 / UC-28 の単独本番シナリオで再検証 |
| SPEC-001-03-3 | flag だけで運用モードを切り替える | 9 foreground slot の結果をジョブスケジューラへ中継する | 31 切り替えた運用モードで業務ジョブを実行する | medium | facade.sh JOB001 を同じジョブ定義で 2 回実行し feature flag だけ変えて応答が blue → green に変わることを観測する。必要な振る舞いは UC-02(起動)+ UC-06(中継)で、spec 側の所有は UC-28「ジョブ定義を変えずに並行稼働から単独本番へ切り替える」/ UC-29。UC-28 を primary にする案もある |
| SPEC-001-04-1 | 設定された runner をそのまま起動する | 5 slot 実行モードを選択して runner を起動する | 31 切り替えた運用モードで業務ジョブを実行する | high | UC-02 が BLUE_RUNNER / GREEN_RUNNER の実体を runner IF で起動する。UC-30 の BDD「facade は設定された runner を runner IF で起動するだけである」が直接対応するが UC-30 は実装順で facade(UC-02)より前のため、pass は UC-02 完了時 |
| SPEC-001-04-2 | runner 差し替えで facade 変更不要 | 5 slot 実行モードを選択して runner を起動する | 31 切り替えた運用モードで業務ジョブを実行する | medium | UC-30 の BDD「runner 実体を差し替えても facade は変更不要である」/ UC-28「次世代並行稼働モードで業務ジョブを実行する」が対応。GREEN_RUNNER を契約準拠の別スタブに差し替えて facade.sh が変更なしで起動し green/ に 3 ファイルが揃うことは UC-02 で観測できる。「比較規約を変更せずに」まで(速報依頼作成)観測するなら UC-09 以降が必要 |
| SPEC-002-01-1 | green 先行起動・blue のみ待機 | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の BDD「background を先に起動し foreground だけを待機する」が対応(実行ログの slot started 順と facade が blue の PID だけを待つこと) |
| SPEC-002-01-2 | 背面 slot は前面と同時に実行される | 5 slot 実行モードを選択して runner を起動する | 9 foreground slot の結果をジョブスケジューラへ中継する | high | UC-02 の BDD「background を先に起動し foreground だけを待機する」(facade 終了時点で green/exitcode.txt が無い)が対応。UC-06「background の完了を待たずに応答する」で再検証 |
| SPEC-002-02-1 | 3 ファイルを無加工で中継する | 9 foreground slot の結果をジョブスケジューラへ中継する |  | high | UC-06 の BDD「foreground の 3 ファイルをそのまま中継する」/「非 0 の exitcode.txt をそのまま終了コードにする」が対応 |
| SPEC-002-02-2 | 速報失敗でも応答は不変 | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する | medium | UC-06 の BDD「速報クロスチェックが失敗しても応答は変わらない」が対応。UC-06 側は green の失敗で速報失敗を代替しており、速報比較依頼 FAILED そのものを Given にする(UC-01 の BDD)なら DB 行を直接用意する。実際に worker で FAILED を作るなら UC-11 以降 |
| SPEC-002-02-3 | 応答に応答時刻を持たない | 9 foreground slot の結果をジョブスケジューラへ中継する |  | high | UC-06 の BDD「foreground の 3 ファイルをそのまま中継する」(標準出力・標準エラーに run_id や relay-gate の文字列を含まない。応答時刻を付加しない)が対応 |
| SPEC-002-03-1 | JOB_ID を渡し runner が実行先を解決 | 6 ジョブマップで JOB_ID から実行先を解決する |  | high | facade が JOB_ID を runner に渡す(UC-02)+ runner がジョブマップで解決する(UC-03「ジョブマップの行から実行先を解決する」)。両方が必要で実装順の後は UC-03 |
| SPEC-003-01-1 | 終了後に 3 ファイルが揃う | 8 実装スクリプトを実行して Runner Result を出力する |  | high | UC-05 の BDD「実行終了後に 3 ファイルが揃う」が対応(exitcode.txt は数値 1 行) |
| SPEC-003-01-2 | 終了コードは exitcode.txt と一致 | 8 実装スクリプトを実行して Runner Result を出力する |  | high | UC-05 の BDD「runner の終了コードは exitcode.txt と一致する」が対応 |
| SPEC-003-01-3 | 起動時に started-at.txt を記録 | 8 実装スクリプトを実行して Runner Result を出力する |  | high | UC-05 の BDD「起動時に started-at.txt を出力する」が対応 |
| SPEC-003-02-1 | ジョブマップ未定義でも 3 ファイル出力 | 6 ジョブマップで JOB_ID から実行先を解決する | 8 実装スクリプトを実行して Runner Result を出力する | high | UC-03 の BDD「ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する」が対応(exitcode.txt=2、stderr.log に not found in job map)。UC-05「SSH 失敗でも 3 ファイルを揃える」が同 SPEC の補強 |
| SPEC-003-03-1 | 書き込み途中の確定名ファイルなし | 8 実装スクリプトを実行して Runner Result を出力する |  | high | UC-05 の BDD「書き込み途中の確定名ファイルは存在しない」が対応(.tmp のみ存在し確定名は無い)。UC-04「一時ファイル経由で確定保存する」も同 SPEC だが実装順が前 |
| SPEC-003-04-1 | background でも 3 ファイルが残る | 8 実装スクリプトを実行して Runner Result を出力する |  | high | UC-05 の BDD「background でも同じ 3 ファイルを残す」が対応 |
| SPEC-004-01-1 | ジョブマップ行から実行先を解決する | 6 ジョブマップで JOB_ID から実行先を解決する |  | high | UC-03 の BDD「ジョブマップの行から実行先を解決する」が対応(runner が host / user / script / work_dir / hang_detect_limit_minutes を解決し実行ログに job map resolved を出す)。UC-31 の validate-config.sh は定義側の検証で When「runner が解決する」ではない |
| SPEC-004-02-1 | 固定引数の後に PARAM を順序保持連結 | 6 ジョブマップで JOB_ID から実行先を解決する | 8 実装スクリプトを実行して Runner Result を出力する | medium | UC-03 の BDD「固定引数の後ろに PARAM を順序保持で連結する」が対応。「実装へ渡す引数」を実装スクリプト(スタブ)の受け取りで観測するなら UC-05「空白を含む引数を 1 引数として実装へ渡す」の実行機能が必要になるため、観測方法次第で primary を UC-05 へ |
| SPEC-004-03-1 | 実行設定を run 開始時に確定保存 | 7 execution-spec.json を確定保存する |  | high | UC-04 の BDD「run 開始時に自 slot の節を保存する」/「認証情報の値を保存しない」が対応(解決済み設定・params・map_version・impl_version・hang_detect_limit_minutes、credential_ref は参照名のみ) |
| SPEC-004-03-2 | ジョブマップ変更後も上書きしない | 7 execution-spec.json を確定保存する |  | high | UC-04 の BDD「既存の節は上書きしない」が対応 |
| SPEC-004-04-1 | 元資料の列名を読み替えなしで解決 | 6 ジョブマップで JOB_ID から実行先を解決する |  | high | UC-03 の BDD「CSV の列名で読み替えなしに実行先を解決する」が対応 |
| SPEC-004-04-2 | fixed_params セルを 2 引数に解析 | 6 ジョブマップで JOB_ID から実行先を解決する |  | high | UC-03 の BDD「二重引用符で囲んだ fixed_params セルを 2 引数として解析する」が対応(When は runner の解析。UC-31 の validate-config.sh 側は定義側の同名検証) |
| SPEC-004-04-3 | host/user 列なしはローカル実行 | 6 ジョブマップで JOB_ID から実行先を解決する | 8 実装スクリプトを実行して Runner Result を出力する | high | UC-03 の BDD「host と user の列が無いジョブマップはローカル実行として解決する」が対応。UC-05「ローカル実行の slot は SSH せず runner のプロセスユーザーで実行する」で実行まで再検証 |
| SPEC-004-04-4 | 任意列なしでもエラーにならない | 2 slot ごとのジョブマップを定義する |  | high | UC-31 の BDD「credential_ref と map_version の列が無くてもエラーにならない」が対応(When「設定を検証する」= validate-config.sh --job-map。両列を末尾に加えた再実行で map_version が読まれる) |
| SPEC-004-04-5 | クロスチェック側も同じ CSV 形式 | 3 クロスチェックのジョブマップと比較定義を定義する |  | high | UC-32 の BDD「クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である」が対応(validate-config.sh --crosscheck-job-map / --target-catalog) |
| SPEC-005-01-1 | blue 完了通知で速報実行に登録 | 10 速報クロスチェック runner へ完了通知を送信する |  | high | UC-08 の BDD「blue の完了通知が rapid_runs に登録される」が対応(rapid-crosscheck-runner.sh blue-completed の起動と rapid_runs.blue_status) |
| SPEC-005-01-2 | runner は相手 slot の状態を見ない | 10 速報クロスチェック runner へ完了通知を送信する |  | high | UC-08 の BDD「green 未完了でも blue の通知は完結する」が対応 |
| SPEC-005-01-3 | 通知失敗でも Runner Result 不変 | 10 速報クロスチェック runner へ完了通知を送信する |  | high | UC-08 の BDD「通知先が終了コード 6 でも Runner Result は変わらない」が対応(runner の終了コードは exitcode.txt のまま、実行ログに WARN completion notice failed) |
| SPEC-005-01-4 | 完了通知の再送は先勝ちで冪等 | 10 速報クロスチェック runner へ完了通知を送信する |  | high | UC-08 の BDD「通知失敗を運用者が同じ引数の再実行で復旧する」が対応(同一コマンド 2 回目でも green_* 列は変わらない。先勝ち) |
| SPEC-005-01-5 | 通知失敗はハング検知で検知しない | 22 background 実行の経過時間と終了状態を判定する | 23 ハング疑い・実行エラー・比較異常を通知する | medium | UC-08 の BDD「通知失敗はハング検知で自動検知されない」が対応するが、When「ハング検知が実行される」には hang-detector.sh(UC-18)が必要。UC-18 では exitcode.txt=0 の判定 COMPLETED で観測でき、「通知メールが送られない」まで意味のある否定検証にするなら UC-19 で再検証 |
| SPEC-005-01-6 | 中止済みでも完了通知を通常送信 | 10 速報クロスチェック runner へ完了通知を送信する |  | medium | UC-08 の BDD「aborted.txt がある slot でも完了通知は通常どおり送る」が対応。Given の abort-blue は成果物に aborted.txt を置くことで代替できる(UC-08 の BDD も同じ前提)。ATDD step が abort-blue.sh を実際に呼ぶなら primary は UC-23(d0977c60)へ |
| SPEC-005-02-1 | 両系成功で依頼を 1 件作成する | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「後に完了した側の通知で依頼が 1 件作成される」が対応 |
| SPEC-005-02-2 | 完了順が逆でも依頼は 1 件 | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「green 先行・blue 後続でも依頼は 1 件」が対応 |
| SPEC-005-02-3 | blue 失敗なら依頼を作らない | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「blue が失敗なら依頼を作成しない」が対応 |
| SPEC-005-02-4 | run が ABORTED なら依頼を作らない | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「並行稼働実行が ABORTED の run では完了通知を受けても依頼を作成しない」が対応(Given の ABORTED は parallel_runs の行を直接用意する) |
| SPEC-005-02-5 | slot が ABORTED なら依頼を作らない | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「parallel_runs が COMPLETED で対象 slot の slot 実行が ABORTED の run では完了通知を受けても依頼を作成しない」が対応(slot_executions と aborted.txt を直接用意する) |
| SPEC-005-02-6 | 前面完了後の abort-green で依頼なし | 13 両系成功時に速報比較依頼を作成する |  | medium | UC-09 の BDD「foreground の blue 完了後に abort-green で中止した green が走り切って完了通知を送っても依頼を作成せず警告を残す」が対応。判定するのは dispatcher(UC-09)で、Given の abort-green は DB 行と aborted.txt の直接用意で代替できる。step が abort-green.sh を呼ぶなら primary は UC-23(d0977c60)へ |
| SPEC-005-02-7 | ABORTED run は両系成功でも依頼なし | 13 両系成功時に速報比較依頼を作成する |  | high | UC-09 の BDD「ABORTED の run で両系成功になっても依頼を作成せず警告を残す」が対応(stderr / 実行ログの warn: rapid request not created reason=parallel_run_aborted) |
| SPEC-005-02-8 | リラン run では新 run_id で依頼作成 | 13 両系成功時に速報比較依頼を作成する | 29 元の execution-spec.json から復元して新しい run_id で起動する | medium | UC-09 の BDD「中止した run のリランでは新しい run_id で依頼が作成される」が対応。UC-09 の BDD はリラン結果の parallel_runs / rapid_runs 行を直接用意する。background-rerun.sh を実際に使うなら UC-26(9aedf7cc)で再検証(その場合 primary を UC-26 へ) |
| SPEC-005-02-9 | 中止 slot は走り切っても ABORTED | 8 実装スクリプトを実行して Runner Result を出力する | 13 両系成功時に速報比較依頼を作成する | medium | slot_executions.status が ABORTED のまま残るのは slot runner の終端 UPDATE が WHERE status=RUNNING の条件付きで 0 件になる振る舞い(UC-05 の BDD「中止後に実装が終了した場合は exitcode.txt を優先して状態を導出する」で条件付き UPDATE 0 件と WARN を検証)。spec 側の配置は UC-09(同名 BDD)で、Given の abort-blue は DB 行と aborted.txt の直接用意で代替。step が abort-blue.sh を呼ぶなら primary は UC-23 |
| SPEC-005-03-1 | worker が claim して比較・結果登録 | 17 比較ツールでジョブ単位比較を実行して結果を登録する |  | high | UC-10「REQUESTED の依頼を claim する」+ UC-11「比較 OK で SUCCEEDED と OK を登録する」が対応。claim から結果登録までは UC-11 完了時に初めて通る |
| SPEC-005-03-2 | job_id ごとの比較定義を使う | 17 比較ツールでジョブ単位比較を実行して結果を登録する |  | high | UC-11 の BDD「job_id の比較定義が使われる」が対応 |
| SPEC-005-03-3 | 比較定義なしは依頼だけ FAILED | 17 比較ツールでジョブ単位比較を実行して結果を登録する |  | high | UC-11 の BDD「比較定義が無い job_id」が対応(FAILED / exit_code=6 / error_summary、comparison_results 無し) |
| SPEC-005-03-4 | 比較ツール起動失敗は依頼だけ FAILED | 17 比較ツールでジョブ単位比較を実行して結果を登録する |  | high | UC-11 の BDD「比較ツールの起動に失敗する」が対応 |
| SPEC-005-03-5 | 終了コード取得で比較結果を登録 | 17 比較ツールでジョブ単位比較を実行して結果を登録する |  | high | UC-11 の BDD「比較 OK で SUCCEEDED と OK を登録する」/「比較 NG(3)で FAILED と NG を登録する」が対応(終了コードを得たときだけ comparison_results を INSERT) |
| SPEC-005-04-1 | off では DB 設定なしで実行できる | 8 実装スクリプトを実行して Runner Result を出力する | 10 速報クロスチェック runner へ完了通知を送信する | high | UC-02「RAPID_CROSSCHECK_MODE=off では管理 DB に触れない」(facade)+ UC-05「RAPID_CROSSCHECK_MODE=off では管理 DB に触れず完了通知も送らない」(runner)が対応。slot 実行全体では UC-05 完了時に通る。UC-08「off では通知しない」で再検証 |
| SPEC-005-04-2 | background で通知と依頼が書かれる | 13 両系成功時に速報比較依頼を作成する |  | high | 「完了結果と比較依頼が書き込まれる」の比較依頼作成は UC-09。完了結果の登録は UC-08「blue の完了通知が rapid_runs に登録される」 |
| SPEC-005-04-3 | 速報 foreground でも同じく通知 | 13 両系成功時に速報比較依頼を作成する |  | high | UC-08「RAPID_CROSSCHECK_MODE=foreground でも background と同じく通知する」+ UC-09 の依頼作成(dispatcher は mode を区別しない)。UC-02 / UC-05 の foreground 同等シナリオが前段 |
| SPEC-005-05-1 | 速報 NG/FAILED でも応答に影響なし | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する | medium | UC-06 の BDD「速報クロスチェックが失敗しても応答は変わらない」/ UC-01「速報が失敗しても応答は変わらない」が対応。Given の比較 NG / FAILED は rapid_crosscheck_requests の行を直接用意して代替する(UC-01 の BDD と同じ)。worker で実際に FAILED を作るなら UC-11 以降 |
| SPEC-005-06-1 | 速報設定の参照名・lease・poll を使う | 15 速報比較依頼を claim する |  | high | UC-08「設定された参照名で管理 DB に接続して完了結果を登録する」+ UC-10「設定された lease 期間と poll 間隔で claim と poll が行われる」が対応。両方必要で実装順の後は UC-10 |
| SPEC-005-06-2 | 速報設定の所有者は基盤適用設計者 | 15 速報比較依頼を claim する |  | low | UC-10 の BDD「速報クロスチェック設定の所有者は基盤適用設計者である」が対応するが、内容は契約 config_files[rapid-crosscheck.env].owner の記載照合で実行時の振る舞いではない。null(モデル・契約整合)扱いにする案もある |
| SPEC-005-06-3 | 速報設定に認証情報の値を置かない | 5 slot 実行モードを選択して runner を起動する |  | medium | UC-02 の BDD「速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない」が対応(設定ファイルの静的検査 + facade が参照名で接続し値をログに出さないこと) |
| SPEC-005-06-4 | off なら速報設定なしで slot 実行 | 5 slot 実行モードを選択して runner を起動する | 8 実装スクリプトを実行して Runner Result を出力する | high | UC-02 の BDD「RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる」が対応(runner はスタブで可)。UC-05 の off シナリオで runner 側も再検証 |
| SPEC-006-01-1 | 確報依頼を登録し終端まで待機する | 11 確報比較依頼を登録して終端状態まで待機する |  | high | UC-13 の BDD「確報依頼を登録して SUCCEEDED まで待機する」が対応(終端は別プロセスで依頼行を更新して代替。worker 不要) |
| SPEC-006-02-1 | 確報 worker が比較し結果を保存する | 16 比較ツールで日次全量比較を実行して結果を保存する |  | high | UC-14「REQUESTED の依頼を claim する」+ UC-15「exit_code=0 で SUCCEEDED になる」/「exit_code=3 で FAILED になる」が対応。claim から保存までは UC-15 完了時に通る |
| SPEC-006-03-1 | 確報 FAILED を終了コード 3 で返す | 18 保存済みの確報結果をジョブスケジューラへ返す |  | high | UC-16 の BDD「exit_code=3 の FAILED をそのまま返す」が対応(FAILED / difference_count / report_uri を含まない) |
| SPEC-006-03-2 | ABORTED でも 3 値だけ返し状態名なし | 18 保存済みの確報結果をジョブスケジューラへ返す |  | high | UC-16 の BDD「ABORTED で exit_code が NULL のとき終了コード 6 を返す」が対応(状態名を出さない) |
| SPEC-006-04-1 | 確報は速報テーブルを変更しない | 11 確報比較依頼を登録して終端状態まで待機する | 16 比較ツールで日次全量比較を実行して結果を保存する | high | UC-13 の BDD「速報側テーブルを変更しない」が対応(final_crosscheck_requests だけが 1 件増える)。worker まで含めた確報実行で再検証するなら UC-15 |
| SPEC-007-01-1 | lease 失効の依頼を戻して再取得 | 14 確報比較依頼を claim する | 15 速報比較依頼を claim する | medium | 速報・確報共通の基準。UC-14 の BDD「lease 失効かつ未開始の依頼を再取得できる」(確報)が実装順で先に通り、UC-10「lease 失効かつ未開始の依頼を再取得する」(速報)で再検証。step を速報 worker で書くなら primary を UC-10 へ |
| SPEC-007-01-2 | 終了コード 0 で SUCCEEDED になる | 16 比較ツールで日次全量比較を実行して結果を保存する | 17 比較ツールでジョブ単位比較を実行して結果を登録する | medium | 速報・確報共通の基準。UC-15 の BDD「exit_code=0 で SUCCEEDED になる」(確報)が実装順で先に通り、UC-11「比較 OK で SUCCEEDED と OK を登録する」(速報)で再検証 |
| SPEC-007-02-1 | claim で担当 worker と期限を記録 | 14 確報比較依頼を claim する | 15 速報比較依頼を claim する | medium | 速報・確報共通の基準。UC-14 の BDD「REQUESTED の依頼を claim する」(worker_id / lease_until)が実装順で先に通り、UC-10 の同名 BDD で再検証 |
| SPEC-007-03-1 | 比較 NG(3)は FAILED・終了コード 3 | 18 保存済みの確報結果をジョブスケジューラへ返す |  | high | UC-15「exit_code=3 で FAILED になる」+ UC-16「exit_code=3 の FAILED をそのまま返す」が対応。ジョブスケジューラへの終了コード 3 は UC-16 完了時に通る |
| SPEC-008-01-1 | 上限超過をハング疑いとして通知 | 23 ハング疑い・実行エラー・比較異常を通知する |  | high | UC-18「上限超過をハング疑いと判定する」+ UC-19「ハング疑いを warning メールで通知する」が対応。「通知される」は UC-19 完了時に通る |
| SPEC-008-01-2 | 非 0 終了を実行エラーとして通知 | 23 ハング疑い・実行エラー・比較異常を通知する |  | high | UC-18「非 0 終了を実行エラーと判定する」+ UC-19「実行エラーを error メールで通知する」が対応 |
| SPEC-008-01-3 | exitcode 0 は通知しない | 23 ハング疑い・実行エラー・比較異常を通知する |  | high | UC-18 の BDD「0 終了は通知対象外」が対応。否定検証(通知されない)が意味を持つのは通知機能(UC-19)実装後なので primary は UC-19 |
| SPEC-008-02-1 | 速報依頼 FAILED を異常として通知 | 23 ハング疑い・実行エラー・比較異常を通知する |  | high | UC-18「FAILED の速報比較依頼を比較異常と判定する」+ UC-19「速報比較依頼の FAILED を error メールで通知する」が対応 |
| SPEC-008-03-1 | 通知後正常終了の警告時経過を記録 | 24 監視記録を保存する |  | high | UC-20 の BDD「通知後に正常終了した実行の警告時経過時間を残す」が対応(elapsed_minutes_at_alert=74 を保持) |
| SPEC-008-03-2 | off では成果物だけで監視する | 22 background 実行の経過時間と終了状態を判定する | 24 監視記録を保存する | high | UC-18 の BDD「off では管理 DB なしで成果物だけを走査する」が対応。UC-20「off では実行ログにのみ残す」で記録側も再検証 |
| SPEC-008-03-3 | 通知後の比較異常は再判定して通知 | 24 監視記録を保存する |  | high | UC-19「ハング疑い通知後の速報比較依頼の比較異常は別種別として 1 回送る」(error メール)+ UC-20 の記録(monitor_status=COMPARE_ERROR_NOTIFIED)が対応。状態遷移の永続化は UC-20 |
| SPEC-008-03-4 | 通知後の中止は正常終了で終端 | 24 監視記録を保存する |  | high | UC-18「ハング疑い通知後に中止された slot 実行を終端する」+ UC-20「通知後に中止された slot 実行を中止済みで終端する」が対応。Given の ABORTED は aborted.txt を置いて代替できる。「監視記録が終端し以後再判定されない」は UC-20 の記録で観測 |
| SPEC-008-03-5 | 監視状態の 6 値がモデル間で一致 | (付けない) |  | high | RDRA モデル整合(バリエーション「監視状態」と状態モデル「監視状態」の値集合の一致)のみで実行時の振る舞いが無い。usdm-acceptance-matrix.md の前提節で BDD 対象外と明記 |
| SPEC-008-04-1 | 検知は通知のみで状態・プロセス不変 | 23 ハング疑い・実行エラー・比較異常を通知する | 24 監視記録を保存する | high | UC-19 の BDD「通知後も状態は RUNNING のままである」が対応(warning メール後も依頼は RUNNING、新依頼なし、worker 停止なし)。UC-20「監視記録の保存で他テーブルは変更されない」で再検証 |
| SPEC-008-05-1 | 上限変更は次回 run から判定に反映 | 22 background 実行の経過時間と終了状態を判定する | 28 hang_detect_limit_minutes をジョブごとに調整する | high | execution-spec.json への反映は UC-04(UC-31 の BDD「hang_detect_limit_minutes の変更は次回以降の run に反映される」も facade.sh 実行で観測)、「判定に使われる」は UC-18 の判定(limit_minutes を execution-spec から読む)。両方必要で実装順の後は UC-18。UC-21「調整は実行済み run に影響しない」で再検証 |
| SPEC-008-05-2 | 調整記録はジョブマップ列に持たない | 2 slot ごとのジョブマップを定義する | 28 hang_detect_limit_minutes をジョブごとに調整する | medium | UC-21 の BDD「調整の記録はジョブマップの列に持たない」は validate-config.sh --job-map が adjusted_at 列を unknown column として警告することで検証し、その振る舞いは UC-31(「実装版の列は未知列として警告される」と同じ機構)。「調整日時と調整根拠は適用構成文書に残る」は relay-gate 外の運用手順で BDD では検証しない |
| SPEC-008-06-1 | 設定の送信コマンドと宛先でメール | 23 ハング疑い・実行エラー・比較異常を通知する |  | high | UC-19 の BDD「ハング検知定期ジョブ設定の宛先と送信コマンドで送る」が対応(/usr/sbin/sendmail が設定の宛先へ起動される) |
| SPEC-008-06-2 | 検知設定の所有者は基盤適用設計者 | 23 ハング疑い・実行エラー・比較異常を通知する |  | low | UC-19 の同 BDD の Given「基盤適用設計者が所有するハング検知定期ジョブ設定」で 3 条件を 1 シナリオで検証しているが、所有者は契約の owner 記載の照合で実行時の振る舞いではない。SPEC-005-06-2 と同様に null 扱いの案もある |
| SPEC-008-06-3 | 検知設定に認証情報の値を置かない | 23 ハング疑い・実行エラー・比較異常を通知する |  | medium | UC-19 の同 BDD の Given「hang-detector.env に認証情報の値は含まれない(参照名 HANG_DB_CONN_REF だけ)」で検証(設定ファイルの静的検査 + hang-detector.sh が参照名で接続すること) |
| SPEC-009-01-1 | リランで新 run_id と親 run_id | 29 元の execution-spec.json から復元して新しい run_id で起動する |  | high | UC-26 の BDD「完了済みの green をリランして新 run_id を得る」が対応(stdout の run_id / parent_run_id、parallel_runs.parent_run_id) |
| SPEC-009-01-2 | parent_run_id で系譜を辿れる | 32 リラン結果を parent_run_id で追跡する |  | high | UC-24 の BDD「2 回リランした系譜を元の実行まで辿る」が対応(run-lineage.sh で depth 2 → 0)。UC-27「再作成した run をさらに再作成して系譜を伸ばす」も run-lineage.sh を使う |
| SPEC-009-02-1 | リランは元の execution-spec で起動 | 29 元の execution-spec.json から復元して新しい run_id で起動する |  | high | UC-26 の BDD「ジョブマップ変更後でも元の設定で起動する」が対応。前段は UC-04「復元起動では保存しない」/ UC-05「復元起動はジョブマップを再解決しない」 |
| SPEC-009-03-1 | foreground slot のリランを拒否 | 26 リラン対象を検証する |  | high | UC-25 の BDD「foreground の blue は拒否する」が対応(終了コード 3、新 run_id 未発行) |
| SPEC-009-03-2 | RUNNING のリランは中止を促し拒否 | 26 リラン対象を検証する |  | high | UC-25 の BDD「RUNNING の green は中止を促して拒否する」が対応(hint: abort the run with abort-green.sh) |
| SPEC-009-03-3 | 速報依頼だけを再作成する | 30 速報比較依頼だけを新規作成する |  | high | UC-25「ABORTED の速報比較依頼は検証を通過する」+ UC-27「ABORTED の速報比較依頼を新しい依頼として再作成する」が対応(blue / green runner は起動されない) |
| SPEC-009-04-1 | foreground の復旧は正規ジョブ再実行 | 26 リラン対象を検証する |  | medium | 「正規ジョブを再実行する」は運用者の行為で relay-gate 側の振る舞いは background-rerun.sh が foreground を拒否して正規ジョブ再実行を hint で案内すること(UC-25「foreground の blue は拒否する」)。確報側の同旨は UC-12「終了コード 6 で実行エラーと判断し再実行する」。facade.sh の再実行自体は UC-06 で既に通る |
| SPEC-010-01-1 | 実行中の背面 slot を中止する | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「background かつ RUNNING の green を中止する」が対応 |
| SPEC-010-01-2 | foreground slot の中止を拒否する | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「foreground の blue は中止できない」が対応(終了コード 3、状態不変) |
| SPEC-010-01-3 | off で中止した run をリランできる | 29 元の execution-spec.json から復元して新しい run_id で起動する |  | high | UC-23「RAPID_CROSSCHECK_MODE=off でも aborted.txt を書いて中止が成立する」(事前検証通過まで)+ UC-26「off で abort-blue により中止した run を成果物だけでリランできる」が対応。「リランできる」まで観測するのは UC-26 完了時 |
| SPEC-010-01-4 | aborted.txt で中止済みと導出 | 24 監視記録を保存する |  | high | UC-18「aborted.txt がある slot 実行は中止済みとして終端する」(判定 COMPLETED)+ UC-20「通知後に中止された slot 実行を中止済みで終端する」(monitor_status=COMPLETED)が対応。「監視記録を終端する」は UC-20 の記録で観測。UC-22「aborted.txt がある slot は ABORTED と表示する」も導出規則の補強 |
| SPEC-010-01-5 | 中止で管理 DB も ABORTED になる | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「background かつ RUNNING の green を中止する」(aborted.txt + slot_executions / parallel_runs が ABORTED)が対応 |
| SPEC-010-01-6 | 未着手の速報依頼も一緒に中止 | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「REQUESTED の速報比較依頼がある run を中止すると依頼も ABORTED になる」が対応 |
| SPEC-010-01-7 | CLAIMED/RUNNING 依頼は変更しない | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の Scenario Outline「CLAIMED または RUNNING の速報比較依頼は slot の中止では変更されない」が対応 |
| SPEC-010-01-8 | 依頼作成直後の中止で再作成されない | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「依頼作成直後に slot を中止すると依頼も ABORTED になり完了通知で再作成されない」が対応(再送する完了通知は UC-09 の rapid-crosscheck-runner.sh で実装順が前) |
| SPEC-010-02-1 | RUNNING の速報依頼を中止する | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「RUNNING の速報比較依頼を中止する」が対応 |
| SPEC-010-02-2 | REQUESTED/CLAIMED 依頼の中止 | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の Scenario Outline「REQUESTED または CLAIMED の速報比較依頼を中止すると worker は比較を開始しない」が対応(worker 側の条件付き UPDATE 0 件は UC-11 で実装済み) |
| SPEC-010-02-3 | 中止後の RUNNING 遷移は 0 件で終了 | 17 比較ツールでジョブ単位比較を実行して結果を登録する | 25 実行を ABORTED へ遷移させる | medium | UC-11 の BDD「CLAIMED の依頼が ABORTED になった後の RUNNING 条件付き UPDATE は 0 件で比較を開始しない」が対応(worker の振る舞い)。Given の abort-rapid-crosscheck は依頼行を ABORTED に直接更新して代替できる。step が abort-rapid-crosscheck.sh を呼ぶなら primary は UC-23 |
| SPEC-010-02-4 | 終端済み速報依頼の中止を拒否する | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の Scenario Outline「終端状態の速報比較依頼は状態を変更せずエラー終了する」が対応(SUCCEEDED / FAILED / ABORTED) |
| SPEC-010-02-5 | RUNNING 以外の確報依頼中止を拒否 | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の Scenario Outline「RUNNING でない確報比較依頼は状態を変更せずエラー終了する」が対応(REQUESTED / CLAIMED / SUCCEEDED) |
| SPEC-010-03-1 | no 応答では状態を変更しない | 21 現在状態を確認して停止確認に応答する |  | high | UC-22 の BDD「no と答えると状態は変わらない」が対応(終了コード 3、aborted.txt 未作成、slot_executions は RUNNING のまま)。yes 経路は UC-23 だが no 経路は UC-22 単独で通る |
| SPEC-010-03-2 | yes でも状態更新のみでプロセス不停止 | 25 実行を ABORTED へ遷移させる |  | high | UC-22「現在状態を表示して yes と答える」+ UC-23「background かつ RUNNING の green を中止する」(PID にシグナルを送らず状態だけ ABORTED)が対応。状態更新は UC-23 完了時に通る |
| SPEC-011-01-1 | 並行稼働実行が実行設定 URI を持つ | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の BDD「RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする」(execution_spec_uri が facade/<run_id>/execution-spec.json を指す)が対応 |
| SPEC-011-02-1 | comparison_result の保持項目 | 17 比較ツールでジョブ単位比較を実行して結果を登録する | 19 速報比較結果を参照する | high | UC-11 の BDD「比較 OK で SUCCEEDED と OK を登録する」/「比較 NG(3)で FAILED と NG を登録する」で comparison_results の列(comparison_type / status / difference_count / report_uri)を検証。UC-07「比較 OK の依頼を参照する」で表示側を再検証 |
| SPEC-011-03-1 | 確報依頼に日付・版・対象一覧を記録 | 16 比較ツールで日次全量比較を実行して結果を保存する |  | high | business_date / catalog_version は UC-13「確報依頼を登録して SUCCEEDED まで待機する」の依頼レコード、対象一覧は UC-15「対象一覧を成果物に記録する」(input/target-catalog.csv)。3 要素が揃うのは UC-15 完了時 |
| SPEC-011-04-1 | 成果物 dir 名と run_id が同値 | 5 slot 実行モードを選択して runner を起動する | 7 execution-spec.json を確定保存する | high | UC-02 の BDD「run_id はローカルタイムゾーンの時刻と job_id と 8 桁 hex で発行され成果物と管理 DB で同値である」が対応。UC-04「execution-spec.json の run_id は成果物ディレクトリ名と管理 DB の run_id と同じ値である」で再検証 |
| SPEC-011-04-2 | 管理 DB なしで run_id を発行 | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の BDD「RAPID_CROSSCHECK_MODE=off では管理 DB に触れない」(facade 単独で発行した run_id 形式の成果物ディレクトリ)が対応 |
| SPEC-011-04-3 | run_id 形式はローカル時刻・Z なし | 5 slot 実行モードを選択して runner を起動する |  | high | UC-02 の同 BDD(正規表現 ^20260830T113000-JOB001-[0-9a-f]{8}$ に一致し末尾に Z を含まない)が対応 |
| SPEC-011-05-1 | 管理 DB は外部システムに含めない | (付けない) |  | high | RDRA 外部システム一覧に管理 DB が無いことの照合のみで振る舞いが無い。usdm-acceptance-matrix.md で対応 UC なし(uncovered、モデル整合のみ)と明記 |
| SPEC-011-05-2 | SSH ホストは外部システムのまま | (付けない) |  | high | RDRA 外部システム一覧にリモート実行ホスト(SSH)が残ることの照合のみで振る舞いが無い |
| SPEC-011-06-1 | STARTED から直接 ABORTED へ遷移 | 25 実行を ABORTED へ遷移させる |  | high | UC-23 の BDD「STARTED のまま残った parallel_runs も slot の中止に伴い ABORTED になる」が対応 |
| SPEC-011-06-2 | 依頼リラン run は依頼終端で完了 | 17 比較ツールでジョブ単位比較を実行して結果を登録する | 30 速報比較依頼だけを新規作成する | medium | UC-11 の BDD「速報比較依頼だけのリラン由来 run は依頼終端で parallel_run を COMPLETED にする」が対応(worker の振る舞い。Given のリラン由来 parallel_runs 行は直接用意)。background-rerun.sh --role rapid-crosscheck を実際に使う end-to-end は UC-27「再作成した依頼が終端すると parallel_runs は COMPLETED になる」で再検証(その場合 primary を UC-27 へ) |
| SPEC-011-06-3 | slot リラン run は slot 終端で完了 | 8 実装スクリプトを実行して Runner Result を出力する | 29 元の execution-spec.json から復元して新しい run_id で起動する | medium | UC-05 の BDD「background slot をリランした run は slot の終端時に parallel_run を COMPLETED にする」が対応(runner の振る舞い。Given のリラン由来 parallel_runs 行と execution-spec.json は直接用意)。background-rerun.sh を実際に使うなら UC-26「完了済みの green をリランして新 run_id を得る」の末尾 And で再検証(その場合 primary を UC-26 へ) |
| SPEC-012-01-1 | CLI の 3 チャネルだけで判定できる | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する | medium | 「任意のスクリプト」の汎用基準。業務ジョブについては UC-06 の中継(UC-01 の BDD「終了コードだけで成否を判定できる」)で 3 チャネルだけで判定できることを観測。validate-config.sh(UC-29)など他スクリプトでも成り立つため、step の対象スクリプト選択で primary が変わる |
| SPEC-012-01-2 | background 異常はメールで届く | 23 ハング疑い・実行エラー・比較異常を通知する | 27 background 異常の通知メールを受け取る | high | UC-19 の BDD「ハング疑いを warning メールで通知する」/「実行エラーを error メールで通知する」が対応。UC-17「warning メールを受け取って静観する」で受信側を再検証 |
| SPEC-012-02-1 | 実行履歴と成果物・ログで追跡できる | 9 foreground slot の結果をジョブスケジューラへ中継する | 12 業務ジョブの実行結果を確認する | medium | UC-01 の BDD「実行ログと成果物で run を追跡できる」が対応(facade.sh.log の slot started / relay finished 行と green/ の 3 ファイル)。relay finished を出すのは UC-06 の中継、slot started は UC-02。step が確報側(UC-12 の追跡 And)も対象にするなら UC-13 以降 |
| SPEC-013-01-1 | 差し替えだけで基盤スクリプト不変 | 31 切り替えた運用モードで業務ジョブを実行する |  | low | runner・ジョブマップ・比較定義だけを差し替えて facade / クロスチェック runner・worker / hang-detector / background-rerun / abort-* の各スクリプトが不変であることを確認する統合基準。UC-30「runner 実体を差し替えても facade は変更不要である」/ UC-32「比較定義と対象カタログを検証する」/ UC-28「ジョブ定義を変えずに並行稼働から単独本番へ切り替える」が分担するが、列挙された全スクリプトが存在した後にハッシュ不変を確認する形にするなら実装順の末尾近くの UC-28 が妥当。差し替え後の実行まで伴うなら UC-11 以降の複数 UC が前提 |
