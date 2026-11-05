# background 実行の経過時間と終了状態を判定する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detector.sh` を追加する(走査・判定部分)。presentation(引数検証)→ usecase(feature flag 読込 → 成果物走査 → 依頼走査(off 以外)→ 対象ごとの判定 → 通知 UC / 記録 UC へ)→ domain(slot 実行の状態導出・判定表・異常判定表・対象除外)→ repository(成果物 / 依頼 / 監視記録 / 通知済みの印)→ gateway(ファイルシステム走査 / RDB)。通知(標準エラーの alert 行と終了コード、通知済みの印)は UC「ハング疑い・実行エラー・比較異常を通知する」、記録(`monitor_records`)は UC「監視記録を保存する」の tier md に続く。`hang-detector.sh` のコマンド契約(引数・設定・終了コード)の正本はこのファイルとする。

## コマンド契約

### hang-detector.sh

- **書式**: `hang-detector.sh [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラのハング検知定期ジョブ(5 分ごと)。運用者が手動起動してもよい(冪等)。成果物ディレクトリの読み取り権限と、RAPID_CROSSCHECK_MODE が off 以外のとき管理 DB の閉域接続(CTP-002)
- **トリガー**: ジョブスケジューラ定期ジョブ(5 分ごと。間隔はジョブ定義側で決める。hang-detector.sh 自身は常駐しない)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--verbose` | boolean | No | false | 対象ごとの `info: judged ...` を stderr にも出す(既定は実行ログのみ) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし

#### 設定契約(ハング検知定期ジョブ設定 = hang-detector.env。`RELAY_GATE_CONFIG_DIR/hang-detector.env`。所有者: 基盤適用設計者(設定所有区分: ハング検知定期ジョブ設定)。RDRA 情報「ハング検知定期ジョブ設定」)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `RAPID_HANG_DETECT_LIMIT_MINUTES` | integer | No | 60 | 正の整数(`^[1-9][0-9]{0,8}$`。違反は `error: invalid value key=RAPID_HANG_DETECT_LIMIT_MINUTES value=... path: ...` + `hint: use a positive integer` で終了コード 2)。速報比較依頼(role=rapid-crosscheck)のハング疑い上限(運用チューニング値。仮採用: 依頼は run の execution-spec.json ではなく hang-detector.env のクロスチェック側の値を使う。ui-design.md「依頼の場合はクロスチェック側の値」) |
| `HANG_SCAN_WINDOW_HOURS` | integer | No | 72 | 正の整数(`^[1-9][0-9]{0,8}$`。違反は `error: invalid value key=HANG_SCAN_WINDOW_HOURS value=... path: ...` + `hint: use a positive integer` で終了コード 2)。started-at.txt がこの時間より古い run は走査しない(運用チューニング値。仮採用: 成果物の蓄積で走査が肥大しないための上限。監視記録が未終端の run は窓外でも走査する。off では通知済みの印の中身が HANG_SUSPECTED_NOTIFIED の run を窓外でも走査する(契約 shared_rules.hang_alert.notified_mark.scan_window)) |
| `HANG_DB_CONN_REF` | string | RAPID_CROSSCHECK_MODE が off でないとき Yes | — | 管理 DB 接続情報の参照名(値は置かない。認証情報の値を設定に含めない) |

- hang-detector.env のキーは上の 3 つだけとする。異常は `hang-detector.sh` 自身の終了コードと標準エラーの alert 行で知らせるため、CLI の出力以外で運用者へ知らせるための項目(宛先・送信コマンド・件名など)は持たない。未知のキーは `warn: unknown key key=<KEY> path: ...` を出して続ける(行の形・重複の扱いは CLI 契約 `config_input_rules.env_files`。出す時点・順・出さない回は下の「未知キーの warn を出す時点」)
- 中身の検査(キーの許可・必須の判定・値の形・行の形)は `hang-detector.sh` が走査前に行う。`validate-config.sh` に hang-detector.env の検証種別は無く、構築手順の配置時の検査はファイルがあることの確認だけ(CLI 契約 `config_files` の hang-detector.env)
- 走査前の検査の順: (a) 引数 → (b) hang-detector.env(存在・読み取り・入力の守備範囲)→ (c) feature-flag.env(存在・読み取り・入力の守備範囲・`RAPID_CROSSCHECK_MODE`)→ (d) hang-detector.env のキー(`HANG_DB_CONN_REF`(off 以外のときだけ)→ `RAPID_HANG_DETECT_LIMIT_MINUTES` → `HANG_SCAN_WINDOW_HOURS`)→ (e) `RELAY_GATE_ARTIFACT_ROOT`。最初に設定エラーを見つけたところで止め、その error 行(と hint)だけを出す(入力の守備範囲の違反が複数行あるときは契約 `config_input_rules` のとおり複数行)。走査前の設定エラーで止まる回((a)〜(e) のどこで止まっても)は未知のキーの warn を出さない
  - (c) で feature-flag.env について検査するのは存在・読み取り・入力の守備範囲と `RAPID_CROSSCHECK_MODE` だけ。feature-flag.env の他のキー、未知キー、`FINAL_` で始まるキーは検査せず、warn も error も出さない(それらの検査は facade.sh と `validate-config.sh --feature-flag`)
  - (e) の「無い」は、成果物ルートの存在確認が ENOENT で終わったとき、存在確認そのものが失敗したとき(親ディレクトリの権限不足など)、ディレクトリでないときで、どれも `error: artifact root not found path: ...`(2)
- 未知キーの warn を出す時点(契約 `shared_rules.hang_alert.unknown_key_warn`): 走査を始めるときに出す。off 以外は管理 DB への接続と SELECT(走査手順 0)が通ったあと、off は印の置き場の検査(走査手順 0)が通ったあと(facade/ を列挙する前)。キー表に無いキーごとに 1 行、ファイル内の出現順(物理行番号の昇順)に出し、stderr のどの行(`error: artifact root is not readable`、走査中の warn 行、`info:` 行、alert 行、対象ごとの error 行)よりも前に置く。管理 DB に接続・SELECT できない回と印の置き場を読めない回は error 1 行だけで、未知キーの warn も出さない

  | 回の結果 | 未知キーの warn |
  |---|---|
  | 走査前の設定エラー(2) | 出さない(error 行と hint だけ) |
  | off 以外で管理 DB に接続・SELECT できない(6) | 出さない(error 1 行だけ) |
  | off で印の置き場を読めない、または置き場の存在を確認できない(成果物ルートが読めないときを含む)(6) | 出さない(error 1 行だけ) |
  | 走査した(0 / 3 / 6) | 走査を始めるときに、stderr の先頭に出現順で出す |

- feature flag 設定(env 形式。9 キー)の `RAPID_CROSSCHECK_MODE`(foreground / background / off)を読む(ファイル名・所在は tier-facade の設定契約を正とする)。判定は「off か off 以外か」だけで行う(foreground と background の挙動差は無い)。`BLUE_MODE` / `GREEN_MODE` は読まない(role の mode は run 開始時に確定した execution-spec.json を正とする)
- execution-spec.json(run 単位 1 ファイル。構造は UC「execution-spec.json を確定保存する」の契約 = step3 canonical C1 を正とする)から読むキー: `job_id`、`slots.<role>.mode`(foreground / background)、`slots.<role>.hang_detect_limit_minutes`。mode が off の slot は節を持たないため走査に現れない。ファイルが無い run(started-at.txt はあるが execution-spec.json が無い契約違反状態)は `warn: execution-spec missing run_id=...` を stderr に出して判定対象外にする(既定値で判定しない。監視記録も作らない。終了コードは 0 のまま)
- slot 実行の状態は RAPID_CROSSCHECK_MODE によらず成果物ファイル正本から導出する(条件「slot 実行の状態導出規則」): `<role>/exitcode.txt` があれば 0 = SUCCEEDED / 非 0 = FAILED、無く `<role>/aborted.txt`(abort-blue / abort-green が中止時に書く。中止日時 1 行)があれば ABORTED、どちらも無ければ RUNNING。両方あるときは exitcode.txt を優先する。ABORTED の background slot は中止済み(COMPLETED)として終端し通知しない。管理 DB の `slot_executions.status` は条件付き UPDATE で一度だけ終端値を書いた複製(abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した経路では ABORTED のまま残り、導出値と異なる)であり、判定には読まない
- 環境変数 `RELAY_GATE_NOW`(テスト専用。cli-command-contract.yaml environment_variables で宣言。UTC ISO 8601 Z 付きで受け取り、ローカル時刻へ変換して使う。本番未設定): 設定時はシステム時刻の代わりに now として使う(経過時間・detected_at・judged_at)
- 日時の時刻軸: 経過時間の計算、detected_at、judged_at、実行ログの出力日時はホストのローカルタイムゾーン(プロセスの TZ 環境変数に従う)の ISO 8601 秒精度・指示子なし。started-at.txt / aborted.txt の中身だけは UTC ISO 8601 Z 付きのままなので(Runner Result Contract)、読み取り時にローカル時刻へ変換してから経過時間の計算・監視記録への転記に使う

## 出力契約

- **stdout**: 出力しない(0 行)。判定結果は実行ログと `--verbose` の stderr にのみ出す(ui-design.md「大量出力」)
- **stderr**:
  - alert 行(その回に新たに知らせる異常 1 件につき 1 行): `alert: level=<warning|error> kind=<hang-suspected|background-exec-error|rapid-crosscheck-error> run_id=<run_id> role=<blue|green|rapid-crosscheck> job_id=<job_id> elapsed_minutes=<n>`。出す条件・並び順・通知済みの判定は UC「ハング疑い・実行エラー・比較異常を通知する」の tier 仕様を正とする
  - 設定・入力エラー(2。上の「走査前の検査の順」で最初に見つけたもの): `error: unknown option option=...` / `error: unexpected argument value=...` / `error: config file not found path: ...`(hang-detector.env 不在。ui-design.md の定型文)/ `error: config file is not readable path: ...`(hang-detector.env が読めない)/ 入力の守備範囲の違反(契約 `config_input_rules` の文言)/ `error: config file not found path: ...` / `error: config file is not readable path: ...`(feature-flag.env が無い・読めない)/ `error: option required option=RAPID_CROSSCHECK_MODE path: ...` / `error: invalid value key=RAPID_CROSSCHECK_MODE value=...` + `hint: use foreground, background or off` / `error: option required option=HANG_DB_CONN_REF path: ...`(RAPID_CROSSCHECK_MODE が off 以外で欠落・空)/ `error: invalid value key=RAPID_HANG_DETECT_LIMIT_MINUTES value=... path: ...` / `error: invalid value key=HANG_SCAN_WINDOW_HOURS value=... path: ...` + `hint: use a positive integer` / `error: artifact root not found path: ...`(`RELAY_GATE_ARTIFACT_ROOT` が無い)
  - 管理 DB に接続・SELECT できない回(6。RAPID_CROSSCHECK_MODE が off 以外): `error: management db connection failed conn_ref=...` / `error: management db query failed ...` の 1 行だけ。成果物の走査・判定・alert 行・監視記録の保存をしない(契約 `shared_rules.hang_alert.db_unavailable`)
  - 印の置き場を読めない回(6。RAPID_CROSSCHECK_MODE=off): `error: notified mark dir is not readable path: ...` の 1 行だけ。走査・判定・alert 行・印の書き込みをしない(契約 `shared_rules.hang_alert.notified_mark.directory_unreadable`。置き場が無いときは印なしとして続ける)
  - 走査の途中の実行エラー(6): `error: artifact root is not readable path: ...`(走査の最初に出る)/ `error: notified mark invalid run_id=... role=... path: ...`(通知 UC)/ `error: monitor record save failed run_id=... role=...`(記録 UC)/ `error: notified mark save failed run_id=... role=... path: ...`(通知 UC)
  - 継続する警告: `warn: unknown key key=<KEY> path: ...`(hang-detector.env。走査を始めるときに出現順で出す。上の「未知キーの warn を出す時点」)/ `warn: execution-spec missing run_id=... path: ...`(当該 run は判定対象外)/ `warn: started-at is invalid run_id=... role=... value=...`(当該 role は判定しない)/ `warn: execution-spec invalid run_id=... key=...`
  - 行の並び順: 未知キーの warn 行(出現順)→ `error: artifact root is not readable`(出る回だけ)→ 走査の warn 行 → `--verbose` の `info: judged` 行 → 対象ごとの行(通知 UC。契約 `shared_rules.hang_alert.order`)
  - `--verbose` 時: `info: judged run_id=... role=... judgement=NOT_TARGET|COMPLETED|EXEC_ERROR|MONITORING|HANG_SUSPECTED|COMPARE_ERROR elapsed_minutes=... limit_minutes=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 新たな異常なし | その回の見回りで新たに知らせる異常が無く、走査・判定・記録がすべて成功した(通知済みの異常が続いていても 0) |
  | 3 | 警告終了 | 新たに知らせる異常がハング疑い(warning)だけ。確報の比較 NG(3)と同じく、ジョブスケジューラのジョブステータスが警告終了になる値 |
  | 6 | 失敗 | background 実行エラーまたは速報クロスチェック異常(error)を新たに 1 件以上知らせた。または `hang-detector.sh` 自身の実行エラー(off 以外で管理 DB 接続・SELECT 失敗(alert 行を出さず error 1 行だけ)、off で印の置き場を読めない(error 1 行だけ。走査しない)、成果物ルートの読み取り失敗、監視記録の保存失敗、通知済みの印の不正、通知済みの印の保存失敗) |
  | 2 | 入力・設定エラー | 走査前に検出: 未知のオプション、オプション以外の引数、`hang-detector.env` 不在・読み取り不可、読んだ設定ファイルの入力の守備範囲の違反、feature-flag.env が無い・読めない・`RAPID_CROSSCHECK_MODE` が無い・空・列挙外、RAPID_CROSSCHECK_MODE が off 以外で `HANG_DB_CONN_REF` 欠落・空、`RAPID_HANG_DETECT_LIMIT_MINUTES` / `HANG_SCAN_WINDOW_HOURS` が正の整数でない、`RELAY_GATE_ARTIFACT_ROOT` が存在しない(存在確認の失敗・ディレクトリでないを含む) |

  - 優先順位: 2 のときは走査しない。off 以外で管理 DB に接続・SELECT できないとき、off で印の置き場を読めないときは走査せずに 6。走査した場合は 6 > 3 > 0(同じ回にハング疑いとエラーを見つけたら 6、ハング疑いを新たに知らせた回に保存失敗・印の不正があれば 6)
  - 走査の途中の実行エラー(成果物ルート・印・保存)があっても、残りの対象の判定・alert 行・記録は続けてから終了コードを決める

- 実行ログ(`RELAY_GATE_LOG_DIR/hang-detector.sh.log`。run_id 欄は対象の run_id、全体処理は `-`):
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの ローカル出力日時の列に対応する(以下は `{LEVEL} {message}` 部分)
  - `INFO scan started mode=background artifact_root=... window_hours=72`(mode は RAPID_CROSSCHECK_MODE の値 foreground / background)
  - `INFO scanning artifacts only mode=off`
  - `INFO judged run_id=... role=... judgement=HANG_SUSPECTED elapsed_minutes=74 limit_minutes=60`(`--verbose` の stderr 行と同じ形式。cli-command-contract.yaml の `--verbose` 説明に合わせ job_id は含めない)
  - `WARN started-at is invalid run_id=... role=... value=...` / `WARN invalid exitcode run_id=... role=... value=...` / `WARN execution-spec missing run_id=... path: ...`(stderr の `warn:` と同じ文言を同時に残す)
  - `INFO scan finished targets=N judged=N alerts=N`

## UC ロジック

- **設定ファイルの読み込み(共通規約の参照)**: 読む設定ファイル(env / CSV)の入力の守備範囲は CLI 契約 `config_input_rules` に従う(形式(UTF-8 / LF)から外れた NUL バイト・不正な文字コード・BOM・CR と、env の invalid line・同じキーが 2 行以上ある設定(`error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...`。どちらの行の値も使わない。報告の順は `config_input_rules.env_files`)は契約と同文の error 行で拒否して終了コード 2、読み込みは 1 時点の内容だけで判定、補助コマンドの失敗は終了コード 6。値は本 tier に複写しない。判定する BDD は UC「slot ごとのジョブマップを定義する」に置く)。stdout / stderr / 実行ログに出す任意入力の制御文字は `ui-design.md`「制御文字の表記」の可視表記にする。bash の最低版は 5.0(契約 `conventions.runtime_prerequisites`)
- **バリデーション**: 未知のオプションは `error: unknown option option=...`、オプション以外の引数は `error: unexpected argument value=...`(いずれも終了コード 2)
- **確認プロンプト**: なし
- **冪等性**: 判定は純粋関数(入力: 成果物ファイル・依頼レコード・現在時刻)。同じ状態で何度実行しても同じ判定。状態を変更せず(RUNNING → ABORTED にしない、プロセスを止めない、依頼を作らない)、副作用は通知 UC(alert 行・通知済みの印)/ 記録 UC に限る
- **run ディレクトリ列挙の規則**(成果物ルート配下の列挙。housekeep / background-rerun と共通):
  | 対象 | 扱い |
  |---|---|
  | `$RELAY_GATE_ARTIFACT_ROOT/facade/` 直下のディレクトリで、名前が run_id 形式 `^[0-9]{8}T[0-9]{6}-<job_id>-[0-9a-f]{8}$` に合うもの | run ディレクトリとして列挙する |
  | `facade/` 直下で `.tmp` で終わる名前、run_id 形式に合わない名前 | 無視する(warn も出さない) |
  | 成果物ルート直下の `hang-detector-notified/`(通知済みの印の置き場)と `housekeep-pending/`(削除待ちの置き場) | `facade/` の外にあるため run ディレクトリとして列挙しない。`hang-detector-notified/` は手順 2 の窓の例外の判定(off のみ)にだけ読む |
- **走査手順**:
  0. off 以外のときは、成果物を走査する前に管理 DB に接続し、走査に使う行(monitor_records と、手順 4 の条件の rapid_crosscheck_requests)を SELECT する。接続に失敗したら `error: management db connection failed conn_ref=...`、SELECT に失敗したら `error: management db query failed ...` の 1 行だけを出し、手順 1 以降(走査・判定・通知・記録)を行わずに終了コード 6 で終える(契約 `shared_rules.hang_alert.db_unavailable`)。off のときは、手順 1 の前(facade/ を列挙する前)に印の置き場 `hang-detector-notified/` を検査し、あるのに列挙・読み取りできなければ `error: notified mark dir is not readable path: ...` の 1 行だけを出して同じく終了コード 6 で終える(`error: artifact root is not readable` は出さない。置き場が無ければ印なしとして続ける。「無い」は存在確認が ENOENT で終わったときだけで、成果物ルートの権限不足などで存在確認そのものが失敗したときは「あるのに読めない」と同じ error 1 行だけ。契約 `notified_mark.directory_unreadable`)。どちらの 1 行だけで終える回も、hang-detector.env の未知キーの warn は出さない。手順 0 が通ったら(off 以外は SELECT のあと、off は置き場の検査のあと)、手順 1 の前に hang-detector.env の未知キーの warn をファイル内の出現順に出す(契約 `shared_rules.hang_alert.unknown_key_warn`)
  1. 上の規則で run ディレクトリを列挙する。`<role>/started-at.txt`(role ∈ {blue, green})が 1 つも無い run ディレクトリは `execution-spec.json` を読まずに飛ばす。started-at.txt がある run だけ `execution-spec.json` の `job_id` と `slots.<role>` を読む。execution-spec.json が無い run は `warn: execution-spec missing run_id=...` を出して判定対象外にする(job_id / mode を埋められないため。監視記録も作らない)。`final-crosscheck` ディレクトリは走査しない
  2. started-at.txt が `HANG_SCAN_WINDOW_HOURS` より古い run は除く。ただし次の run は窓外でも走査する
     - off 以外: 監視記録が未終端(MONITORING / HANG_SUSPECTED_NOTIFIED)の run。監視記録が終端(COMPLETED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / NOT_MONITORED)の run は窓内でも除く
     - off: `hang-detector-notified/<run_id>.<role>` の中身が規定の値(英字コード + LF。契約 `shared_rules.hang_alert.notified_mark.content`)の HANG_SUSPECTED_NOTIFIED の run(`.tmp` で終わる名前は読まない)。中身が EXEC_ERROR_NOTIFIED / COMPLETED の印は終端として扱い、その run を窓外では走査しない。窓外の run の印が不正・読めないときは印が無いものとして扱い、走査せず、error 行も出さない(窓内の run の印の不正は通知 UC が error 行を出す。契約 `notified_mark.scan_window`)
  3. 走査対象 run の `<role>/exitcode.txt` と `<role>/aborted.txt` を読み、slot 実行の状態を導出する(RUNNING / SUCCEEDED / FAILED / ABORTED。RAPID_CROSSCHECK_MODE によらず成果物ファイルが正本。`slot_executions` は読まない)
  4. off 以外のとき `rapid_crosscheck_requests` から status ∈ {REQUESTED, CLAIMED, RUNNING} と、monitor_records が未終端(記録なし / MONITORING / HANG_SUSPECTED_NOTIFIED)の {SUCCEEDED, FAILED} と、monitor_records が未終端(MONITORING / HANG_SUSPECTED_NOTIFIED の記録あり)の ABORTED を取得する。比較異常は依頼の status(と exit_code)だけで判定し、別テーブルは結合しない(HANG_SUSPECTED_NOTIFIED の依頼を除外しない。除外すると warning 通知後に終端・中止した依頼が二度と判定されず run_count に永続的に数えられる)
  5. 対象ごとに domain の判定表で判定
- **状態導出表**(domain `derive_slot_status`。条件「slot 実行の状態導出規則」。縦軸 exitcode.txt、横軸 aborted.txt):
  | exitcode.txt | aborted.txt なし | aborted.txt あり |
  |---|---|---|
  | なし | RUNNING | ABORTED |
  | あり・0 | SUCCEEDED | SUCCEEDED(exitcode.txt を優先) |
  | あり・非 0 | FAILED | FAILED(exitcode.txt を優先) |
- **判定表**(domain `judge_background_role`。hang_judgement は 6 値: NOT_TARGET / COMPLETED / EXEC_ERROR / MONITORING / HANG_SUSPECTED / COMPARE_ERROR = RDRA バリエーション「ハング検知判定結果」の 6 値。cli-command-contract.yaml `shared_rules.state_codes.hang_judgement`):
  | 導出状態 | exitcode.txt | 経過時間 | 判定 |
  |---|---|---|---|
  | ABORTED | なし(aborted.txt あり) | — | COMPLETED(中止済み → COMPLETED。通知しない) |
  | SUCCEEDED | あり・0 | — | COMPLETED(正常終了 → COMPLETED) |
  | FAILED | あり・非 0 | — | EXEC_ERROR |
  | FAILED | あり・整数でない | — | EXEC_ERROR(`WARN invalid exitcode` を残す。alert 行は通常の書式で出す) |
  | RUNNING | なし | ≤ limit | MONITORING |
  | RUNNING | なし | > limit | HANG_SUSPECTED |
  前提: mode=background かつ limit > 0。それ以外は NOT_TARGET(監視対象外 → NOT_MONITORED)。走査窓内の ABORTED slot は監視記録の有無によらず COMPLETED と判定し、記録 UC が COMPLETED の監視記録を UPSERT する(off 以外。終端済みの監視記録がある run は手順 2 で走査から外れる)。現在の monitor_status が HANG_SUSPECTED_NOTIFIED でも同じ表で再判定する(遷移の可否は通知 UC の冪等判定が決める)
- **異常判定表**(domain `judge_rapid_request`。入力は依頼の status / exit_code / 経過時間だけ。別テーブルは結合しない):
  | 依頼状態 | 経過時間 | 判定 |
  |---|---|---|
  | FAILED(exit_code=3 比較 NG / 6 実行エラー / 起動失敗) | — | COMPARE_ERROR |
  | SUCCEEDED | — | COMPLETED |
  | RUNNING | > RAPID_HANG_DETECT_LIMIT_MINUTES | HANG_SUSPECTED |
  | RUNNING | ≤ RAPID_HANG_DETECT_LIMIT_MINUTES | MONITORING |
  | REQUESTED / CLAIMED | — | MONITORING |
  | ABORTED(未終端の監視記録がある依頼のみ走査。abort-rapid-crosscheck による中止と abort-blue / abort-green による未着手依頼の中止を含む) | — | COMPLETED(運用者が中止済み → monitor_status COMPLETED で終端。状態.tsv「監視状態」の中止済み終端) |
- **エラーハンドリング**: 1 対象の読み取り失敗(不正な started-at.txt、execution-spec.json 欠落・不正)は `warn:` を出して他の対象を継続する(終了コードに影響しない)。off 以外で管理 DB に接続・SELECT できない場合は、監視記録(現在の通知済み状態)を読めないため走査も判定もせず、error 1 行だけを出して終了コード 6 で終える(走査手順 0)。通知済みの異常を、管理 DB の障害が続くあいだ見回りのたびに知らせないため。異常は通知済みにならないので、接続できた最初の回に通知 UC の通常の規則で一度だけ知らせる
- **クラッシュ耐性**: 状態を変更しないため途中終了で壊れるものは無い。次回の定期起動が同じ判定をやり直す。再通知の要否は監視記録(off は通知済みの印)の遷移判定で決める(通知 UC)
- **監視は通知のみ**: usecase は abort / rerun / 依頼作成の repository を呼ばない(LP-017)

## データモデル変更

### monitor_records(参照。更新は UC「監視記録を保存する」)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / role | string | 主キー | 追加(参照) |
| monitor_status | string | 終端済み(COMPLETED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / NOT_MONITORED)の判定に使う。HANG_SUSPECTED_NOTIFIED は未終端 | 追加(参照) |

### rapid_crosscheck_requests(参照。off 以外のみ。内部データストア: ジョブキュー兼管理 DB)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| rapid_crosscheck_requests.run_id / job_id / status / started_at / requested_at / exit_code | string / string / string / datetime / datetime / integer | 異常判定の入力(status=FAILED → 比較異常。ABORTED は未終端の監視記録がある依頼のみ)。別テーブルは結合しない | 追加(参照) |

- `slot_executions` は読まない(slot 実行の状態はファイル正本から導出する。管理 DB の status は同じ値の複製)

### 成果物ディレクトリ(参照)

| ファイル | 型 | 説明 | 変更種別 |
|---------|---|------|---------|
| `facade/<run_id>/execution-spec.json` | JSON | job_id、role ごとの mode / hang_detect_limit_minutes | 追加(参照) |
| `facade/<run_id>/<role>/started-at.txt` | text | 経過時間の起点。中身は UTC ISO 8601 Z 付き(Runner Result Contract)。ローカル時刻へ変換して経過時間の計算と monitor_records.started_at への転記に使う | 追加(参照) |
| `facade/<run_id>/<role>/exitcode.txt` | text | 終了状態(確定名のみ) | 追加(参照) |
| `facade/<run_id>/<role>/aborted.txt` | text | 中止日時 1 行(UTC ISO 8601 Z 付き。中身は変換しない)。abort-blue / abort-green が中止時のみ生成。exitcode.txt が無いときの ABORTED 判定に使う(確定名のみ。日時の値は判定に使わない) | 追加(参照) |
| `hang-detector-notified/<run_id>.<role>` | text | 通知済みの印(off のみ。成果物ルート直下)。中身が HANG_SUSPECTED_NOTIFIED の run を窓外でも走査し、EXEC_ERROR_NOTIFIED / COMPLETED の run は窓外では走査しない。書き方は UC「ハング疑い・実行エラー・比較異常を通知する」 | 追加(参照) |

## ビジネスルール

- slot 実行の状態導出規則: exitcode.txt / aborted.txt の有無と値から RUNNING / SUCCEEDED / FAILED / ABORTED を導出する(RAPID_CROSSCHECK_MODE によらない)
- ハング検知判定: 判定表のとおり(hang_judgement 6 値)。exitcode.txt / aborted.txt は確定名だけを読む(成果物公開判定)。ABORTED(exitcode.txt なし・aborted.txt あり)は中止済み(COMPLETED)として終端し通知しない
- ハング検知対象の除外: foreground role と hang_detect_limit_minutes=0 は NOT_TARGET → NOT_MONITORED。execution-spec.json が無い run は判定対象外(監視記録なし)
- 速報比較依頼の異常判定: FAILED / 比較 NG → 比較異常、RUNNING で上限超過 → ハング疑い(状態は変更しない)
- 速報クロスチェック有効判定: off では管理 DB に接続しない(LP-020)。通知済みかどうかは成果物ルート配下の通知済みの印で判定する
- 通知レベルの判定: 終了コードは新たに知らせる異常の段階で決まる(0 / 3 / 6)。CLI の出力以外の通知手段は持たない
- 監視は通知のみ: 状態変更・プロセス停止・依頼作成をしない(LP-017)
- 上限は run 開始時に確定した execution-spec.json の値(ハング検知上限の調整基準: 変更は次回以降の run に反映)

## ティア完了条件(BDD)

```gherkin
Feature: background 実行の経過時間と終了状態を判定する - 実行監視・復旧ティア

  Scenario: 成果物だけでハング疑いを判定する(off)
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green が無い
    And facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json に job_id=JOB001 slots.green.mode=background slots.green.hang_detect_limit_minutes=60 がある
    And green/started-at.txt が 2026-08-30T11:30:05Z、exitcode.txt が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 3 で stdout は 0 行、stderr に "info: judged run_id=20260830T113000-JOB001-3f9a1c2e role=green judgement=HANG_SUSPECTED elapsed_minutes=74 limit_minutes=60" と "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green job_id=JOB001 elapsed_minutes=74" が出る

  Scenario: 継続監視は通知しない
    Given 同じ run で RELAY_GATE_NOW=2026-08-30T12:00:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "judgement=MONITORING elapsed_minutes=29 limit_minutes=60" を含む行が出て、"alert:" で始まる行は出ない

  Scenario: 正常終了は COMPLETED と判定する
    Given 同じ run の green/exitcode.txt の中身が 0 である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "judgement=COMPLETED" を含む行が出る

  Scenario: aborted.txt がある slot 実行は COMPLETED と判定する(SPEC-010-01)
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、monitor_records に run_id=20260830T113000-JOB001-3f9a1c2e role=green monitor_status=MONITORING の行がある
    And green/exitcode.txt が無く green/aborted.txt(中身 2026-08-30T12:40:00Z)があり、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "info: judged run_id=20260830T113000-JOB001-3f9a1c2e role=green judgement=COMPLETED" で始まる行が出て、"alert:" で始まる行は出ない
    And slot_executions は SELECT されない(状態は成果物ファイルから導出する)

  Scenario: off でも aborted.txt がある slot 実行は COMPLETED と判定する(SPEC-010-01)
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、green/exitcode.txt が無く green/aborted.txt がある
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "judgement=COMPLETED" を含む行が出て、管理 DB には接続しない

  Scenario: aborted.txt.tmp は無視する
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green が無い
    And green/exitcode.txt が無く green/aborted.txt.tmp だけがあり、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 判定は HANG_SUSPECTED で(確定名の aborted.txt が無いため RUNNING と導出する)、終了コード 3 で終了する

  Scenario: facade/ 直下の run_id 形式のディレクトリだけを run として列挙する
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off がある
    And $RELAY_GATE_ARTIFACT_ROOT/facade/ 直下に 20260830T113000-JOB001-3f9a1c2e(green/started-at.txt と execution-spec.json あり)、20260830T113000-JOB001-3f9a1c2e.tmp、work と名付けたディレクトリがある
    And $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ と $RELAY_GATE_ARTIFACT_ROOT/housekeep-pending/20260801T020000-JOB001-1a2b3c4d/green/started-at.txt がある
    When `hang-detector.sh --verbose` を実行する
    Then stderr の "info: judged" で始まる行は run_id=20260830T113000-JOB001-3f9a1c2e の行だけである
    And 20260830T113000-JOB001-3f9a1c2e.tmp・work・hang-detector-notified・housekeep-pending・20260801T020000-JOB001-1a2b3c4d について warn 行も info 行も出ない

  Scenario: execution-spec.json が無い run は判定対象外にする
    Given facade/20260830T113000-JOB002-9a8b7c6d/execution-spec.json が無く green/started-at.txt がある
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "warn: execution-spec missing run_id=20260830T113000-JOB002-9a8b7c6d path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB002-9a8b7c6d/execution-spec.json" が出る
    And stderr に "info: judged run_id=20260830T113000-JOB002-9a8b7c6d" で始まる行は出ず、monitor_records に該当 run_id の行は作られない

  Scenario: hang-detector.env に HANG_DB_CONN_REF が無い
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env に HANG_DB_CONN_REF が無い
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr に "error: option required option=HANG_DB_CONN_REF path: /etc/relay-gate/hang-detector.env" が出て、走査は行われない

  Scenario: 未知のオプション
    When `hang-detector.sh --all` を実行する
    Then 終了コード 2 で stderr に "error: unknown option option=--all" が出る

  Scenario Outline: hang-detector.env の監視の調整値が正の整数でなければ走査しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env の内容が "<line>" の 1 行である
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr は "error: invalid value key=<key> value=<value> path: /etc/relay-gate/hang-detector.env" と "hint: use a positive integer" の 2 行で、走査は行われない

    Examples:
      | line                                | key                             | value |
      | RAPID_HANG_DETECT_LIMIT_MINUTES=0   | RAPID_HANG_DETECT_LIMIT_MINUTES | 0     |
      | HANG_SCAN_WINDOW_HOURS=072          | HANG_SCAN_WINDOW_HOURS          | 072   |
      | HANG_SCAN_WINDOW_HOURS=             | HANG_SCAN_WINDOW_HOURS          |       |

  Scenario: off では HANG_DB_CONN_REF が無くても監視の調整値と字下げしたコメント行を受理する
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector.env の内容が "  # tuning"、"RAPID_HANG_DETECT_LIMIT_MINUTES=90"、"HANG_SCAN_WINDOW_HOURS=24" の 3 行である
    And 走査する run が 1 つも無い
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で stderr に "error:" / "warn:" で始まる行は出ない

  Scenario: 設定エラーが複数あるときは検査の順で最初の 1 件だけを出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、hang-detector.env に HANG_DB_CONN_REF が無く、RAPID_HANG_DETECT_LIMIT_MINUTES=abc がある
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr は "error: option required option=HANG_DB_CONN_REF path: /etc/relay-gate/hang-detector.env" の 1 行だけである

  Scenario: hang-detector.env の未知のキーは warn を出して続ける
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector.env の内容が "ALERT_MAIL_TO=ops@example.com" の 1 行で、走査する run が 1 つも無い
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で stderr は "warn: unknown key key=ALERT_MAIL_TO path: /etc/relay-gate/hang-detector.env" の 1 行だけである

  Scenario: 未知のキーの warn は走査を始めるときにファイル内の出現順で、走査中の warn 行より前に出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env の内容が "ZZZ_NOTE=1"、"HANG_SCAN_WINDOW_HOURS=72"、"AAA_NOTE=2" の 3 行である
    And facade/20260830T113000-JOB002-9a8b7c6d/ に green/started-at.txt(中身 2026-08-30T11:30:05Z)があり execution-spec.json が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である(run は走査の窓の内側)
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で stderr は次の 3 行がこの順に出る(キー名の順ではなく行番号の順)
      | 行 |
      | warn: unknown key key=ZZZ_NOTE path: /etc/relay-gate/hang-detector.env |
      | warn: unknown key key=AAA_NOTE path: /etc/relay-gate/hang-detector.env |
      | warn: execution-spec missing run_id=20260830T113000-JOB002-9a8b7c6d path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB002-9a8b7c6d/execution-spec.json |

  Scenario: 未知のキーがあっても管理 DB に接続できない回は error 1 行だけを出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、hang-detector.env の内容が "HANG_DB_CONN_REF=relaygate-db"、"ALERT_MAIL_TO=ops@example.com" の 2 行で、relaygate-db の接続先に接続できない
    When `hang-detector.sh` を実行する
    Then 終了コード 6 で stderr は "error: management db connection failed conn_ref=relaygate-db" の 1 行だけで、"warn: unknown key" で始まる行は出ない

  Scenario: 未知のキーがあっても off で印の置き場を読めない回は error 1 行だけを出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector.env の内容が "ALERT_MAIL_TO=ops@example.com" の 1 行で、$RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ が hang-detector.sh のプロセスユーザーから読めない
    When `hang-detector.sh` を実行する
    Then 終了コード 6 で stderr は "error: notified mark dir is not readable path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified" の 1 行だけで、"warn: unknown key" で始まる行は出ない

  Scenario: 管理 DB を使う設定でも未知のキーの warn は SELECT のあと、alert 行より前に出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env の内容が "HANG_DB_CONN_REF=relaygate-db"、"ALERT_MAIL_TO=ops@example.com" の 2 行で、relaygate-db に接続でき、monitor_records に該当の行が無い
    And facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json に job_id=JOB001 slots.green.mode=background slots.green.hang_detect_limit_minutes=60 があり、green/started-at.txt が 2026-08-30T11:30:05Z で exitcode.txt が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh` を実行する
    Then 終了コード 3 で stderr は "warn: unknown key key=ALERT_MAIL_TO path: /etc/relay-gate/hang-detector.env" と "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green job_id=JOB001 elapsed_minutes=74" の 2 行がこの順に出る

  Scenario: 未知のキーの warn は成果物ルートの読み取り失敗の error 行より前に出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env の内容が "HANG_DB_CONN_REF=relaygate-db"、"ALERT_MAIL_TO=ops@example.com" の 2 行で、relaygate-db に接続でき、走査する速報比較依頼が無い
    And $RELAY_GATE_ARTIFACT_ROOT/facade/ が hang-detector.sh のプロセスユーザーから列挙できない
    When `hang-detector.sh` を実行する
    Then 終了コード 6 で stderr は "warn: unknown key key=ALERT_MAIL_TO path: /etc/relay-gate/hang-detector.env" と、"error: artifact root is not readable path: " で始まる 1 行の 2 行がこの順に出る

  Scenario: off で成果物ルートが読めず印の置き場の存在を確認できない回は error 1 行だけを出す
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector.env の内容が "ALERT_MAIL_TO=ops@example.com" の 1 行で、$RELAY_GATE_ARTIFACT_ROOT に hang-detector.sh のプロセスユーザーの検索権限が無い
    When `hang-detector.sh` を実行する
    Then 終了コード 6 で stderr は "error: notified mark dir is not readable path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified" の 1 行だけで、"warn: unknown key" / "error: artifact root is not readable" で始まる行は出ない

  Scenario: 成果物ルートがディレクトリでなければ走査前の設定エラーにする
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、hang-detector.env の内容が "ALERT_MAIL_TO=ops@example.com" の 1 行で、RELAY_GATE_ARTIFACT_ROOT=/var/relay-gate が通常のファイルである
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr は "error: artifact root not found path: /var/relay-gate" の 1 行だけで、"warn: unknown key" で始まる行は出ない

  Scenario: feature-flag.env の未知のキーと FINAL_ で始まるキーは hang-detector.sh では検査しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off と "LEGACY_FLAG=1" と "FINAL_CROSSCHECK_MODE=on" があり、hang-detector.env の内容が "HANG_SCAN_WINDOW_HOURS=72" の 1 行で、走査する run が 1 つも無い
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で stderr は 0 行である

  Scenario: 未知のキーがあっても走査前の設定エラーで止まる回は warn を出さない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、RELAY_GATE_CONFIG_DIR=/etc/relay-gate の hang-detector.env の内容が "ALERT_MAIL_TO=ops@example.com"、"HANG_SCAN_WINDOW_HOURS=0" の 2 行である
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr は "error: invalid value key=HANG_SCAN_WINDOW_HOURS value=0 path: /etc/relay-gate/hang-detector.env" と "hint: use a positive integer" の 2 行だけで、"warn: unknown key" で始まる行は出ない

  Scenario: 管理 DB に接続できない回は成果物を走査しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=foreground があり、HANG_DB_CONN_REF=relaygate-db の接続先に接続できない
    And facade/20260830T113000-JOB001-3f9a1c2e/green/started-at.txt が 2026-08-30T11:30:05Z で exitcode.txt が無く、facade/20260830T113000-JOB002-9a8b7c6d/ には green/started-at.txt があり execution-spec.json が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 6 で stderr は "error: management db connection failed conn_ref=relaygate-db" の 1 行だけで、stdout は 0 行である
    And stderr に "warn: execution-spec missing" / "info: judged" で始まる行は出ず、実行ログに "INFO judged" で始まる行は残らない(成果物を走査しない)

  Scenario: off で印の置き場を読めない回は走査しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、$RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ が hang-detector.sh のプロセスユーザーから読めない
    And facade/20260830T113000-JOB001-3f9a1c2e/ の green の判定が HANG_SUSPECTED になる成果物がある
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 6 で stderr は "error: notified mark dir is not readable path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified" の 1 行だけで、"alert:" / "info: judged" で始まる行は出ない

  Scenario: execution-spec.json が無い run の印は読まない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off があり、facade/20260830T113000-JOB002-9a8b7c6d/ に green/started-at.txt があり execution-spec.json が無く、hang-detector-notified/20260830T113000-JOB002-9a8b7c6d.green の内容が空である
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で stderr は "warn: execution-spec missing run_id=20260830T113000-JOB002-9a8b7c6d path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB002-9a8b7c6d/execution-spec.json" の 1 行だけで、"error: notified mark invalid" で始まる行は出ず、印の内容は変わらない
```
