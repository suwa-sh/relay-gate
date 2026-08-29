# USDM acceptance criteria 逆引き行列

本文書は、USDM 正本（`docs/usdm/latest/requirements.yaml`、REQ 12 / SPEC 42）の acceptance criteria から、UC Spec の BDD シナリオへの逆引き行列である。
実装者が「この受け入れ条件を検証するテストはどのファイルのどの Scenario か」を一意に引けるようにする。

- 1 行 = 1 acceptance criterion。SPEC に複数 criteria がある場合は `#1` / `#2` で行を分ける
- 「UC Scenario」列は各 UC の `spec.md` に実在する Scenario 見出し、「tier Scenario」列は `tier-facade.md` / `tier-worker.md` に実在する Scenario 見出しをそのまま記載した
- 対応するシナリオが存在しない criterion は「未対応」と明記し、末尾の「未対応 criteria と対応方針」で 1 件ずつ方針を示す
- 要素単位（情報属性・条件・バリエーション・状態遷移・外部システム）の網羅判定は既存の [traceability-matrix.md](traceability-matrix.md) が正本であり、本書は acceptance criteria 単位の逆引きを補完する

## 網羅サマリ

| 区分 | 件数 |
|---|---|
| SPEC 総数 | 42 |
| acceptance criteria 総数 | 57 |
| UC Scenario へ対応付いた criteria | 57 |
| 未対応の criteria | 0 |

## 逆引き行列

UC 名の業務/BUC パスは省略する（23UC の名称は一意）。tier Scenario 列の「同左 UC」は「対応 UC」列の UC 配下の tier ファイルを指す。

| SPEC ID | acceptance criterion（要約） | 対応 UC | UC Scenario（spec.md） | tier Scenario（tier-*.md） |
|---|---|---|---|---|
| SPEC-001-01 | flag 設定投入済みで facade が JOB_ID を受けると設定どおり blue/green slot が起動する | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-001-02 | flag の組み合わせ変更だけで、同一ジョブ定義のまま運用モードが切り替わる | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=off, GREEN_MODE=foregroundで新実装単独本番の運用モードとして起動する | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-001-03 | BLUE/GREEN 両方 foreground の設定は検証で起動を許可しない | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundに設定されている | tier-facade.md / Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる |
| SPEC-001-04 | 新世代 runner を差し替えても実装固有差異が facade 本体に影響しない | feature flag設定に基づきslotを選択して起動する | Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）（SPEC-012-01 と共通） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-002-01 #1 | foreground 完了時、stdout.log/stderr.log の内容がそのままジョブスケジューラへ中継される | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果を標準出力・標準エラー・終了コードのみで応答する | tier-facade.md / Scenario: 確定済みforeground実行結果を3項目のみで応答する |
| SPEC-002-01 #2 | exitcode.txt の非 0 値（例: 3）を一律の値へ丸めずプロセス終了コードとして透過する | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果の非0終了コードをそのまま透過する | tier-facade.md / Scenario: 非0のexitcode.txt値を丸めずそのまま透過する |
| SPEC-002-02 | background role を先に起動し、foreground 待機中も background が並走する固定順序 | feature flag設定に基づきslotを選択して起動する | Scenario: background roleを先に起動しforegroundの完了を待たずに応答する（UC01。送出順序と非待機）、および uc-dependencies.md「UC 横断統合シナリオ」Scenario: background roleを先に起動しforeground待機中もbackgroundが並走する（UC01+UC02+UC03 の統合） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-002-03 #1 | 実行結果が未確定・取得不能なら終了コード 125 で応答し、業務終了コードとして解釈させない | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果が待機上限内に確定しない、Scenario: 起動イベント送出失敗でFAILEDかつexit_code=NULLの場合は退避コード125で応答する、Scenario: foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する、Scenario: foreground実行結果がABORTED（中止済み）の場合は退避コード125で応答する | tier-facade.md / Scenario: foreground実行結果が待機上限内に確定せず退避コード125を返す |
| SPEC-002-03 #2 | run_id 未指定などバリデーションエラーは終了コード 124 で応答する | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: run_id未指定でバリデーションエラーになる | tier-facade.md / Scenario: run_id未指定で退避コード124を返す |
| SPEC-002-03 #3 | UNKNOWN を推測で FAILED 相当の業務終了コードへ変換せず退避コード 125 を使う | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する（FAILED 相当へ推測変換されないことをアサート） | tier-facade.md / Scenario: foreground実行結果が待機上限内に確定せず退避コード125を返す |
| SPEC-002-04 #1 | relay-gate エラー時に stderr.log を取得できる場合、標準エラーへ stderr.log 内容と relay-gate エラー内容（原因と次アクション）を併記する | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する（stderr.log 内容と relay-gate エラー内容の併記をアサート） | tier-facade.md / Scenario: relay-gateエラー時にstderr.log内容とrelay-gateエラー内容を併記する |
| SPEC-002-04 #2 | stderr.log を取得できない場合は relay-gate エラー内容（原因と次アクション）を標準エラーへ出力する | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果がABORTED（中止済み）の場合は退避コード125で応答する（stderr.log 取得不能時に relay-gate エラー内容と次アクションを出力することをアサート） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-01 | runner 終了後に execution-spec.json・started-at.txt・stdout.log・stderr.log・exitcode.txt が揃う | background roleを起動する | Scenario: runner終了後にRunner Result Contractの成果物ファイル一式が揃う | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-02 | SSH 失敗等の異常終了でも可能な範囲で実行結果を出力・記録する | background roleを起動する | Scenario: 起動先実装への接続に失敗しFAILEDとして記録する | tier-worker.md / Scenario: green実装ホストへの接続に失敗しFAILEDとして記録する |
| SPEC-003-03 | 出力中の成果物を後続処理が読まない（一時ファイル→リネーム公開） | background roleを起動する | Scenario: 成果物を一時ファイルへ出力してから確定名へリネームし書き込み途中を読ませない | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-04 #1 | 同一 run_id・slot 種別・role 区分の複数回起動が attempt_id で一意識別され、attempt_no が連番になる | 並行稼働実行結果を確認する | Scenario: 同一run_id・slot・roleの複数起動試行をattempt_idとattempt_no連番で一意に確認する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-04 #2 | 起動受付時に accepted_at が記録され実行状態が STARTING である | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（accepted_at 付き status="STARTING" の runner_results INSERT をアサート） | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-003-04 #3 | timeout で結果を取得できない場合は UNKNOWN とし、推測で FAILED を確定しない | background roleを起動する、background実行の未完了・非0終了・速報比較異常を定期検知する、feature flag設定に基づきslotを選択して起動する | Scenario: SSH起動タイムアウトでUNKNOWNとして記録する、Scenario: 結果取得不能の起動試行をUNKNOWNへ確定する、Scenario: 起動イベントの送出がtimeoutした試行をUNKNOWNへ補償記録する | tier-worker.md / Scenario: SSH起動タイムアウトでUNKNOWNとして記録する（background roleを起動する） |
| SPEC-003-04 #4 | UNKNOWN からの確定は実結果の回収または対話確認による回復でのみ SUCCEEDED/FAILED/ABORTED へ行う | background実行の未完了・非0終了・速報比較異常を定期検知する | Scenario: UNKNOWN状態の起動試行の実結果を回収しSUCCEEDEDへ確定する | （spec.md シナリオで検証。tier-worker.md はビジネスルールとして規定） |
| SPEC-004-01 | blue/green の完了順に依存せず、両系成功時に比較依頼を重複なく 1 件だけ作成する | blue-green runnerの完了通知を受けて速報比較依頼を作成する | Scenario: blue/green双方のbackground実行完了で速報比較依頼を新規作成する、Scenario: blue側のみ完了しgreen側が未完了の場合は依頼を作成せず次回サイクルまで待機する、Scenario: 既に依頼済みの比較対象試行ペアはスキップする | tier-worker.md / Scenario: blue/green双方が揃った未依頼job_idから速報比較依頼を作成する |
| SPEC-004-02 | RAPID_CROSSCHECK_MODE=off なら完了時に速報管理 DB への接続・書込みが発生しない | feature flag設定に基づきslotを選択して起動する、blue-green runnerの完了通知を受けて速報比較依頼を作成する | Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない、Scenario: RAPID_CROSSCHECK_MODEがoffの場合は依頼を作成しない | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-004-03 | 速報比較が FAILED でも foreground 応答の内容は影響を受けない | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果を標準出力・標準エラー・終了コードのみで応答する（比較結果・差分件数・レポートURIを一切出力しないことをアサート） | tier-facade.md / Scenario: 確定済みforeground実行結果を3項目のみで応答する |
| SPEC-005-01 | 確報専用ジョブ定義から起動し、全テーブル・全ファイルが比較対象になる | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 全テーブル・全ファイルが一致しSUCCEEDEDへ遷移する | tier-worker.md / Scenario: workerがREQUESTED状態の確報比較依頼をlease/claim取得しRUNNINGへ遷移させる |
| SPEC-005-02 | 確報完了時、runner の応答は stdout・stderr・exitcode だけである | 確報クロスチェック結果をstdout-stderr-exitcodeで応答する | Scenario: SUCCEEDED状態の確報比較依頼が終了コード0で応答される、Scenario: 差分件数・レポートURIを応答に含めない制約が守られる | tier-worker.md / Scenario: presentation層がSUCCEEDEDのstatusをexitcode 0に変換して応答する |
| SPEC-006-01 | exitcode.txt 未出力で hang_detect_limit_minutes 超過ならハング疑いとして通知する | background実行の未完了・非0終了・速報比較異常を定期検知する、ハング疑い・異常を運用者へ通知する | Scenario: exitcode.txt未出力かつしきい値超過でハング疑いを検知する、Scenario: 未通知のハング検知記録を運用者へ通知する | tier-worker.md / Scenario: しきい値超過によりハング疑いを記録する、tier-worker.md / Scenario: 未通知のハング検知記録をbannerで通知しnotified_atを更新する |
| SPEC-006-02 | exitcode.txt 非 0 の background role を background 実行エラーとして通知する | background実行の未完了・非0終了・速報比較異常を定期検知する、ハング疑い・異常を運用者へ通知する | Scenario: exitcode.txtの非0終了コードをbackground実行エラーとして検知する、Scenario: 未通知のハング検知記録を運用者へ通知する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-006-03 | 速報比較依頼の FAILED または比較 NG を速報クロスチェック異常として通知する | background実行の未完了・非0終了・速報比較異常を定期検知する、ハング疑い・異常を運用者へ通知する | Scenario: 速報比較結果NGを速報クロスチェック異常として検知する、Scenario: 速報比較結果NGが継続する場合も重複した検知記録を作成しない、Scenario: 未通知のハング検知記録を運用者へ通知する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-006-04 | hang-detector は状態を RUNNING のまま保持し、自動 ABORTED 遷移・新規依頼作成をしない | background実行の未完了・非0終了・速報比較異常を定期検知する | Scenario: exitcode.txt未出力かつしきい値超過でハング疑いを検知する（RUNNING のまま変更されないことをアサート）、Scenario: 結果取得不能の起動試行をUNKNOWNへ確定する（ABORTED へ変更されないことをアサート） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-007-01 #1 | background かつ RUNNING の slot は対話確認 yes で ABORTED へ遷移する | 対話確認のうえblue background実行をABORTEDへ遷移させる、対話確認のうえgreen background実行をABORTEDへ遷移させる | Scenario: 対話確認でyを応答しABORTEDへ遷移する（blue/green 両 UC に同名シナリオ） | tier-facade.md / Scenario: 対話確認y応答でABORTEDへ状態遷移し監査イベントを記録する（blue）、tier-facade.md / Scenario: abort_green_confirm_対話確認y応答の場合_ABORTEDへ遷移し監査イベントを記録すること（green） |
| SPEC-007-01 #2 | 対象 slot が foreground または off の場合は状態を変更せずエラー終了する | 対話確認のうえblue background実行をABORTEDへ遷移させる、対話確認のうえgreen background実行をABORTEDへ遷移させる | Scenario: 対象slotがforeground roleのため状態を変更せずエラー終了する、Scenario: 対象slotのmodeがoffのため状態を変更せずエラー終了する（blue/green 両 UC に同名シナリオ） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-007-02 | RUNNING の比較依頼は対話確認 yes で ABORTED へ遷移する | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる、対話確認のうえ確報比較依頼をABORTEDへ遷移させる | Scenario: 対話確認(y)によりABORTEDへ遷移する（速報/確報 両 UC に同名シナリオ） | tier-worker.md / Scenario: abort_rapid_crosscheck_confirm_対話確認y応答の場合_ABORTEDへ更新し監査イベントを記録すること、tier-worker.md / Scenario: abort_final_crosscheck_confirm_対話確認y応答の場合_ABORTEDへ更新し監査イベントを記録すること |
| SPEC-007-03 | 対話確認で yes 以外を回答した場合は状態を変更しない | 対話確認のうえblue background実行をABORTEDへ遷移させる、対話確認のうえgreen background実行をABORTEDへ遷移させる、対話確認のうえ速報比較依頼をABORTEDへ遷移させる、対話確認のうえ確報比較依頼をABORTEDへ遷移させる | Scenario: 対話確認でnを応答し遷移を中断する（blue/green）、Scenario: 対話確認で拒否(n)した場合は遷移させない（速報/確報） | tier-facade.md / Scenario: 対話確認n応答で状態変更を行わない（blue）、tier-facade.md / Scenario: abort_green_confirm_対話確認n応答の場合_状態変更を行わないこと（green） |
| SPEC-008-01 #1 | 完了/中止済み実行を元の execution-spec 設定で新 run_id 再実行し parent_run_id を設定する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: 完了済みのbackground実行を元の実行設定のまま新run_idで再実行する | tier-facade.md / Scenario: rerun_run_facadeが元の実行設定を保ったまま新規run_idでbackground roleを再起動すること |
| SPEC-008-01 #2 | 再実行しても元の実行のレコード・状態・履歴は変更されない | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: 完了済みのbackground実行を元の実行設定のまま新run_idで再実行する（元 run_id の行が一切変更されないことをアサート） | tier-facade.md / Scenario: rerun_run_facadeが元の実行設定を保ったまま新規run_idでbackground roleを再起動すること |
| SPEC-008-02 #1 | RUNNING 中の対象はリランせずエラー終了する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: RUNNING中の速報比較依頼はリランできない（重複起動防止） | tier-worker.md / Scenario: rerun_run_RUNNING中の対象を指定した場合_重複起動防止のため拒否すること、tier-facade.md / Scenario: rerun_run_STARTING中の対象を指定した場合_リランせずエラー終了すること |
| SPEC-008-02 #2 | 元の slot mode が foreground/off の role 指定はリランせずエラー終了する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: 元のslot modeがforegroundまたはoffのためリランせずエラー終了する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-008-03 #1 | role=rapid-crosscheck 指定で業務ジョブを再実行せず、新 run_id の速報比較依頼を parent_run_id 付きで新規作成する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: 中止済みの速報比較依頼から新run_idの依頼を新規作成する | tier-worker.md / Scenario: rerun_run_workerが中止済みの速報比較依頼から新run_idの依頼を新規作成すること |
| SPEC-008-03 #2 | rapid-crosscheck 再実行後も元依頼の状態・履歴は変更されない | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: 中止済みの速報比較依頼から新run_idの依頼を新規作成する（元依頼が ABORTED のまま一切変更されないことをアサート） | tier-worker.md / Scenario: rerun_run_workerが中止済みの速報比較依頼から新run_idの依頼を新規作成すること |
| SPEC-008-04 | foreground slot と確報クロスチェックはジョブスケジューラの正規ジョブで再実行する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: foreground slot・確報クロスチェックのリラン指定を拒否し正規ジョブでの再実行を案内する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-009-01 | JOB_ID と追加引数だけを受け、実行先詳細はジョブマップで解決される | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する、Scenario: JOB_IDに対応するジョブマップが存在しない、Scenario: ジョブマップの必須フィールドが欠落している | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-02 | job map の固定引数の後ろに追加引数を順序どおり連結する | feature flag設定に基づきslotを選択して起動する | Scenario: job mapの固定引数の後ろに追加引数を順序を変えず連結する、Scenario: 空白・引用符・改行を含む引数が保存と復元の往復で同一になる | tier-facade.md / Scenario: 追加引数をJSON配列で保存し要素順のままargvへ復元する |
| SPEC-009-03 #1 | 解決済み設定を execution spec（run 共通の execution_specs と slot 別の slot_execution_specs）として RDB へ一度だけ確定保存し、認証情報は参照名のみ保存する | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（execution_specs / slot_execution_specs への確定 INSERT と credential_ref 参照名のみ保存をアサート） | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-03 #2 | hang_detect_limit_minutes は run 共通の 1 値（background slot のジョブマップ値）として execution_specs に保存され、role 別・slot 別の値は保存されない | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（hang_detect_limit_minutes=45 = background slot の値をアサート）、Scenario: BLUE_MODE=background, GREEN_MODE=backgroundの場合は両ジョブマップのhang_detect_limit_minutesの大きい方を採用する | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-04 | job map 変更後も既存 run_id の execution spec は変更前設定を保持する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: job map変更後もリランは既存run_idの変更前実行設定を保持したまま使用する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-009-05 #1 | run 共通の実行設定と slot 別実行設定が分離して保存され、slot 別実行設定が run_id と slot 種別で一意に識別される | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（execution_specs 1 行 + slot_execution_specs 2 行の分離 INSERT と (run_id, slot_type) の一意識別をアサート） | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-05 #2 | slot 別実行設定には認証情報の参照名のみが保存され実値は含まれない | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（credential_ref に参照名のみ保存、実値は保存されないことをアサート）、Scenario: credential_refから認証情報を解決し実値を露出させない | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-010-01 | 速報側の各エンティティが同一 run_id で相関付けられている | blue-green runnerの完了通知を受けて速報比較依頼を作成する、速報クロスチェックを実行し差分を検知する | Scenario: blue/green双方のbackground実行完了で速報比較依頼を新規作成する（blue/green run_id・attempt_id による相関をアサート）、Scenario: 差分ありでFAILEDへ遷移する（依頼と同一 run_id の速報比較結果作成をアサート） | tier-worker.md / Scenario: blue/green双方が揃った未依頼job_idから速報比較依頼を作成する |
| SPEC-010-02 | 確報比較依頼は速報側エンティティを参照・再利用しない独立モデルである | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 確報比較依頼は速報側エンティティを参照・再利用せず独立して完結する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-010-03 | 複数回リラン時に parent_run_id を数珠つなぎにたどって元の実行まで追跡できる | 速報クロスチェック結果を確認する、execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: リランで作成された依頼をparent_run_id付きで確認する、Scenario: 完了済みのbackground実行を元の実行設定のまま新run_idで再実行する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-011-01 | CLAIMED で lease 失効かつ未開始の依頼は REQUESTED へ戻る | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: lease失効かつ未着手のためREQUESTEDへ差し戻す、Scenario: lease失効かつ未着手の依頼はREQUESTEDへ差し戻される | tier-worker.md / Scenario: lease失効かつ未着手の依頼が次回ポーリングでREQUESTEDへ差し戻される（確報） |
| SPEC-011-02 #1 | worker 終了時 exitcode=0 なら依頼状態を SUCCEEDED へ更新する | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 差分なしでSUCCEEDEDへ遷移する、Scenario: 全テーブル・全ファイルが一致しSUCCEEDEDへ遷移する | tier-worker.md / Scenario: REQUESTED行をlease取得し差分なしでSUCCEEDEDへ確定する（速報） |
| SPEC-011-02 #2 | worker 終了時 exitcode 非 0 または実行エラーなら依頼状態を FAILED へ更新する | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 差分ありでFAILEDへ遷移する、Scenario: 差分検出によりFAILEDへ遷移する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-011-03 | 確報 runner は worker 保存の exitcode を中継し、状態名そのものは返さない | 確報クロスチェック結果をstdout-stderr-exitcodeで応答する | Scenario: SUCCEEDED状態の確報比較依頼が終了コード0で応答される、Scenario: FAILED状態の確報比較依頼が終了コード1で応答される | tier-worker.md / Scenario: presentation層がSUCCEEDEDのstatusをexitcode 0に変換して応答する |
| SPEC-012-01 | runner 設定の差し替えだけで facade 本体を変更せず新世代実装を並行稼働できる | feature flag設定に基づきslotを選択して起動する | Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）（SPEC-001-04 と共通） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-012-02 | RAPID_CROSSCHECK_MODE=off で速報クロスチェックの完了通知・DB 接続・書込みを停止できる | feature flag設定に基づきslotを選択して起動する、blue-green runnerの完了通知を受けて速報比較依頼を作成する | Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない、Scenario: RAPID_CROSSCHECK_MODEがoffの場合は依頼を作成しない | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-012-03 #1 | job_id ごとに異なる比較対象・比較実装の比較定義が速報・確報の双方で適用される | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: job_idに応じた比較定義が適用される（速報）、Scenario: job_idに応じた比較定義が確報クロスチェックへ適用される（確報） | tier-worker.md / Scenario: 依頼が保持する比較定義世代を1件解決して比較に適用する（速報）、tier-worker.md / Scenario: workerが依頼の保持する世代キーで比較定義を1件解決しcomparator_idを適用する（確報） |
| SPEC-012-03 #2 | 同一 JOB_ID に有効期間の異なる比較定義があるとき、実行時点に該当する 1 件だけが適用される | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する、blue-green runnerの完了通知を受けて速報比較依頼を作成する | Scenario: 有効期間に該当する比較定義が1件だけ適用される（速報/確報 両 UC に同名シナリオ）、Scenario: 実行時点で有効な比較定義世代のvalid_fromを依頼に保存する | tier-worker.md / Scenario: 依頼が保持する比較定義世代を1件解決して比較に適用する（速報）、tier-worker.md / Scenario: workerが依頼の保持する世代キーで比較定義を1件解決しcomparator_idを適用する（確報） |

## 未対応 criteria と対応方針

未対応の criteria は 0 件である。USDM 正本の全 57 acceptance criteria が、イベントディレクトリ内の UC Scenario（spec.md）へ対応付いた。

前回版で未対応だった SPEC-012-03（job_id 別の比較定義差し替え）は、RDRA へ情報「比較定義」が追加されたことを受けて、「速報クロスチェックを実行し差分を検知する」「全テーブル・全ファイルを対象に確報クロスチェックを実行する」「blue-green runnerの完了通知を受けて速報比較依頼を作成する」の各 spec.md に job_id 別・有効期間解決の Scenario が追加され、解消済みである。

また、本 run で新規追加された criteria のうち次の 3 件は、対応する Scenario を本行列の整備にあわせて spec.md へ追加した（いずれも RDRA モデルに既存の情報・状態の範囲内での追加）。

| SPEC ID | 追加した Scenario | 追加先 |
|---|---|---|
| SPEC-003-04 #1 | Scenario: 同一run_id・slot・roleの複数起動試行をattempt_idとattempt_no連番で一意に確認する | 並行稼働実行結果を確認する/spec.md |
| SPEC-003-04 #4 | Scenario: UNKNOWN状態の起動試行の実結果を回収しSUCCEEDEDへ確定する | background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md（tier-worker.md の走査条件・状態遷移も同期更新） |
| SPEC-009-05 #2 | 既存 Scenario「BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する」へ credential_ref 参照名のみ保存のアサートを追記 | feature flag設定に基づきslotを選択して起動する/spec.md |

さらに feedback request `20260822_085257_impl_feedback_6078c4ed`（CR-6078c4ed-012 / 013 / 016 / 018）の反映で、次の Scenario を追加・移動した。

| SPEC ID | 追加・移動した Scenario | 追加先 |
|---|---|---|
| SPEC-009-03 #2 | Scenario: BLUE_MODE=background, GREEN_MODE=backgroundの場合は両ジョブマップのhang_detect_limit_minutesの大きい方を採用する（既存 Scenario「BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する」には background slot の値 45 の採用アサートを追記） | feature flag設定に基づきslotを選択して起動する/spec.md |
| SPEC-002-02 | Scenario: background roleを先に起動しforeground待機中もbackgroundが並走する を UC01 spec.md から uc-dependencies.md「UC 横断統合シナリオ」へ移動（UC01 側は Scenario: background roleを先に起動しforegroundの完了を待たずに応答する へ改名し責務内の Then に限定） | _cross-cutting/uc-dependencies.md |
| SPEC-003-04 #3 | Scenario: 起動イベントの送出がtimeoutした試行をUNKNOWNへ補償記録する | feature flag設定に基づきslotを選択して起動する/spec.md |
