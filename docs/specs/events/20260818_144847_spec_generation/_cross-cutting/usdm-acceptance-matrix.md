# USDM acceptance criteria 逆引き行列

本文書は、USDM 正本（`docs/usdm/latest/requirements.yaml`、REQ 12 / SPEC 38）の acceptance criteria から、UC Spec の BDD シナリオへの逆引き行列である。
実装者が「この受け入れ条件を検証するテストはどのファイルのどの Scenario か」を一意に引けるようにする。

- 1 行 = 1 acceptance criterion。SPEC に複数 criteria がある場合は `#1` / `#2` で行を分ける
- 「UC Scenario」列は各 UC の `spec.md` に実在する Scenario 見出し、「tier Scenario」列は `tier-facade.md` / `tier-worker.md` に実在する Scenario 見出しをそのまま記載した
- 対応するシナリオが存在しない criterion は「未対応」と明記し、末尾の「未対応 criteria と対応方針」で 1 件ずつ方針を示す
- 要素単位（情報属性・条件・バリエーション・状態遷移・外部システム）の網羅判定は既存の [traceability-matrix.md](traceability-matrix.md) が正本であり、本書は acceptance criteria 単位の逆引きを補完する

## 網羅サマリ

| 区分 | 件数 |
|---|---|
| SPEC 総数 | 38 |
| acceptance criteria 総数 | 43 |
| UC Scenario へ対応付いた criteria | 42 |
| 未対応の criteria | 1 |

## 逆引き行列

UC 名の業務/BUC パスは省略する（23UC の名称は一意）。tier Scenario 列の「同左 UC」は「対応 UC」列の UC 配下の tier ファイルを指す。

| SPEC ID | acceptance criterion（要約） | 対応 UC | UC Scenario（spec.md） | tier Scenario（tier-*.md） |
|---|---|---|---|---|
| SPEC-001-01 | flag 設定投入済みで facade が JOB_ID を受けると設定どおり blue/green slot が起動する | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-001-02 | flag の組み合わせ変更だけで、同一ジョブ定義のまま運用モードが切り替わる | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=off, GREEN_MODE=foregroundで新実装単独本番の運用モードとして起動する | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-001-03 | BLUE/GREEN 両方 foreground の設定は検証で起動を許可しない | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundに設定されている | tier-facade.md / Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる |
| SPEC-001-04 | 新世代 runner を差し替えても実装固有差異が facade 本体に影響しない | feature flag設定に基づきslotを選択して起動する | Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）（SPEC-012-01 と共通） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-002-01 | foreground 完了時、stdout.log/stderr.log/exitcode.txt の内容だけをそのままジョブスケジューラへ中継する | foreground roleの標準出力・標準エラー・終了コードを応答する | Scenario: foreground実行結果を標準出力・標準エラー・終了コードのみで応答する | tier-facade.md / Scenario: 確定済みforeground実行結果を3項目のみで応答する |
| SPEC-002-02 | background role を先に起動し、foreground 待機中も background が並走する固定順序 | feature flag設定に基づきslotを選択して起動する | Scenario: background roleを先に起動しforeground待機中もbackgroundが並走する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-01 | runner 終了後に execution-spec.json・started-at.txt・stdout.log・stderr.log・exitcode.txt が揃う | background roleを起動する | Scenario: runner終了後にRunner Result Contractの成果物ファイル一式が揃う | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-003-02 | SSH 失敗等の異常終了でも可能な範囲で実行結果を出力・記録する | background roleを起動する | Scenario: 起動先実装への接続に失敗しFAILEDとして記録する | tier-worker.md / Scenario: green実装ホストへの接続に失敗しFAILEDとして記録する |
| SPEC-003-03 | 出力中の成果物を後続処理が読まない（一時ファイル→リネーム公開） | background roleを起動する | Scenario: 成果物を一時ファイルへ出力してから確定名へリネームし書き込み途中を読ませない | （spec.md シナリオで検証。tier 個別シナリオなし） |
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
| SPEC-009-01 | JOB_ID と追加引数だけを受け、実行先詳細はジョブマップで解決される | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する、Scenario: JOB_IDに対応するジョブマップが存在しない | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-02 | job map の固定引数の後ろに追加引数を順序どおり連結する | feature flag設定に基づきslotを選択して起動する | Scenario: job mapの固定引数の後ろに追加引数を順序を変えず連結する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-009-03 | 解決済み設定を execution spec として一度だけ確定保存し、認証情報は参照名のみ保存する | feature flag設定に基づきslotを選択して起動する | Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する（execution_specs / slot_execution_specs への確定 INSERT と credential_ref をアサート） | tier-facade.md / Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する |
| SPEC-009-04 | job map 変更後も既存 run_id の execution spec は変更前設定を保持する | execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: job map変更後もリランは既存run_idの変更前実行設定を保持したまま使用する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-010-01 | 速報側の各エンティティが同一 run_id で相関付けられている | blue-green runnerの完了通知を受けて速報比較依頼を作成する、速報クロスチェックを実行し差分を検知する | Scenario: blue/green双方のbackground実行完了で速報比較依頼を新規作成する（blue/green run_id・attempt_id による相関をアサート）、Scenario: 差分ありでFAILEDへ遷移する（依頼と同一 run_id の速報比較結果作成をアサート） | tier-worker.md / Scenario: blue/green双方が揃った未依頼job_idから速報比較依頼を作成する |
| SPEC-010-02 | 確報比較依頼は速報側エンティティを参照・再利用しない独立モデルである | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 確報比較依頼は速報側エンティティを参照・再利用せず独立して完結する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-010-03 | 複数回リラン時に parent_run_id を数珠つなぎにたどって元の実行まで追跡できる | 速報クロスチェック結果を確認する、execution-spec.jsonの実行設定を保ったまま再実行する | Scenario: リランで作成された依頼をparent_run_id付きで確認する、Scenario: 完了済みのbackground実行を元の実行設定のまま新run_idで再実行する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-011-01 | CLAIMED で lease 失効かつ未開始の依頼は REQUESTED へ戻る | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: lease失効かつ未着手のためREQUESTEDへ差し戻す、Scenario: lease失効かつ未着手の依頼はREQUESTEDへ差し戻される | tier-worker.md / Scenario: lease失効かつ未着手の依頼が次回ポーリングでREQUESTEDへ差し戻される（確報） |
| SPEC-011-02 #1 | worker 終了時 exitcode=0 なら依頼状態を SUCCEEDED へ更新する | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 差分なしでSUCCEEDEDへ遷移する、Scenario: 全テーブル・全ファイルが一致しSUCCEEDEDへ遷移する | tier-worker.md / Scenario: REQUESTED行をlease取得し差分なしでSUCCEEDEDへ確定する（速報） |
| SPEC-011-02 #2 | worker 終了時 exitcode 非 0 または実行エラーなら依頼状態を FAILED へ更新する | 速報クロスチェックを実行し差分を検知する、全テーブル・全ファイルを対象に確報クロスチェックを実行する | Scenario: 差分ありでFAILEDへ遷移する、Scenario: 差分検出によりFAILEDへ遷移する | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-011-03 | 確報 runner は worker 保存の exitcode を中継し、状態名そのものは返さない | 確報クロスチェック結果をstdout-stderr-exitcodeで応答する | Scenario: SUCCEEDED状態の確報比較依頼が終了コード0で応答される、Scenario: FAILED状態の確報比較依頼が終了コード1で応答される | tier-worker.md / Scenario: presentation層がSUCCEEDEDのstatusをexitcode 0に変換して応答する |
| SPEC-012-01 | runner 設定の差し替えだけで facade 本体を変更せず新世代実装を並行稼働できる | feature flag設定に基づきslotを選択して起動する | Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）（SPEC-001-04 と共通） | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-012-02 | RAPID_CROSSCHECK_MODE=off で速報クロスチェックの完了通知・DB 接続・書込みを停止できる | feature flag設定に基づきslotを選択して起動する、blue-green runnerの完了通知を受けて速報比較依頼を作成する | Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない、Scenario: RAPID_CROSSCHECK_MODEがoffの場合は依頼を作成しない | （spec.md シナリオで検証。tier 個別シナリオなし） |
| SPEC-012-03 | job_id ごとに異なる比較対象・比較実装の定義が適用される | 未対応 | 未対応 | 未対応 |

## 未対応 criteria と対応方針

Spec 側（各 UC の spec.md へのシナリオ追加）で解消できるものはすべて解消済み。残る未対応は以下の 1 件のみであり、Spec 側の追記では解消できず **RDRA 側の見直しが必要**である。

| # | SPEC ID | criterion 要約 | 想定される理由 | 対応方針 |
|---|---|---|---|---|
| 1 | SPEC-012-03 | job_id ごとの比較定義差し替え | 速報・確報の比較実行 UC は比較処理を単一の定義で記述しており、job_id 別の比較定義切替がシナリオ・分岐条件に現れていない。比較定義に相当する情報モデルが RDRA に存在しないため、Spec 側だけで RDRA モデルに無い情報を発明してシナリオ化することはできない | RDRA 側の見直しが必要: 比較定義（対象テーブル・ファイル・比較実装）を情報モデルとして RDRA に追加したうえで、「速報クロスチェックを実行し差分を検知する」「全テーブル・全ファイルを対象に確報クロスチェックを実行する」に job_id 別定義の適用シナリオを追加する（feedback request 経由で dist-requirements の差分更新に戻す） |
