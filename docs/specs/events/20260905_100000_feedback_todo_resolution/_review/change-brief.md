# spec 差分更新の変更正本(feedback 20260905_todo_resolution / event 20260905_100000_feedback_todo_resolution)

この文書は、今回の spec 更新で全 subagent が従う「変更の正本」。ここに書かれた決定を各成果物へ反映する。
ここに無い仕様を発明しない。判断に迷う点は完了報告の「要確認」に書く(ファイルに仮採用を書き込まない)。

- 作業対象ルート: `/Users/suwa_sh/src/github.com/suwa-sh/relay-gate/docs/specs/events/20260905_100000_feedback_todo_resolution/`(以下 `$E`)
- `docs/specs/latest/` は読むだけ。**書かない**(最後にオーケストレータが $E を latest へ反映する)
- RDRA の正本: `docs/rdra/latest/*.tsv`(今回更新済み)。差分要約: `docs/rdra/events/20260905_083000_feedback_todo_resolution/_changes.md`
- arch / nfr は `$E/_inputs-digest.md`(再生成済み)を読む。arch-design.yaml / nfr-grade.yaml の丸読みはしない
- 中立表現を守る(固有システム名・製品名を書かない。現行実装 / 新実装 / ジョブスケジューラ / 比較ツール)
- Bash にヒアドキュメントを渡さない。ファイル編集は Edit / Write ツールで行う
- **機械置換は適用済み**(下記「適用済みの機械置換」)。文脈上おかしくなった箇所があれば直す

## 適用済みの機械置換(全ファイル)

| 置換 | 内容 |
|---|---|
| run_id / final_crosscheck_id の例 | `20260830T113000Z-JOB001-…` → `20260830T113000-JOB001-…`(`Z` 除去。数字は変えていない) |
| 形式表記 | `{UTC yyyymmddThhmmssZ}` → `{ローカル yyyymmddThhmmss}`、正規表現 `T[0-9]{6}Z-` → `T[0-9]{6}-` |
| 設定ファイル名 | `*-job-map.tsv` / `crosscheck-job-map.tsv` / `target-catalog.tsv` → `.csv`(`input/target-catalog.csv` も) |
| feature flag 値 | `RAPID_CROSSCHECK_MODE=on` → `RAPID_CROSSCHECK_MODE=background`、execution-spec の `"rapid_crosscheck_mode": "on"` → `"background"` |
| 列名 | `exec_user` → `user`、`script_path` → `script`、`fixed_args_json` / `fixed_args` → `fixed_params` |

機械置換で **直っていない** もの(各 subagent が担当ファイルで直す):
「on のとき」「(on)」「on 時」「on / off」「on|off」「MODE が on」などの文言、TSV としての形式説明(タブ区切り・列の説明)、
`CONFIG_VERSION` / `config_version`、ジョブマップ列としての `impl_version`、`credential_ref` / `map_version` の必須性、
run_id の「UTC」説明、「管理 DB が無い旨を出して終了」(abort-blue / abort-green)、「(spec 追加)」注記、
「rdra-feedback #n」「_inference.md #9 仮採用」「DIST-0xx」「confidence: low」の注記(下記の解消済み項目のみ)、
「外部システム: 管理 DB(RDB)」表記、ハング検知上限設定の「調整日時 / 調整根拠」、ジョブスケジューラ応答の「応答日時」。

## 決定事項(CR ごと)

### D1. feature flag は元資料の 9 キー(CR-001)

`feature-flag.env`(env 形式、KEY=VALUE、`#` コメント可)のキーは次の 9 個 **だけ**。`CONFIG_VERSION` は削除(設定版は持たない)。

| キー | 型 | 必須 | 意味 |
|---|---|---|---|
| BLUE_MODE | enum foreground / background / off | Yes | blue slot の実行モード |
| GREEN_MODE | enum foreground / background / off | Yes | green slot の実行モード |
| RAPID_CROSSCHECK_MODE | enum foreground / background / off | Yes | 速報クロスチェックの制御。foreground / background は runner が完了通知を送信し速報管理 DB へ書き込む。off は完了通知を送信せず速報管理 DB へ接続も書込みもしない(parallel_run も作らない) |
| BLUE_IMPL | string(非空) | BLUE_MODE が off でないとき Yes | blue の実装版。execution-spec.json の `slots.blue.impl_version` の出所 |
| GREEN_IMPL | string(非空) | GREEN_MODE が off でないとき Yes | green の実装版。`slots.green.impl_version` の出所 |
| BLUE_RUNNER | string(absolute path) | BLUE_MODE が off でないとき Yes | blue slot runner 実体の絶対パス。存在・実行可能 |
| GREEN_RUNNER | string(absolute path) | GREEN_MODE が off でないとき Yes | green slot runner 実体の絶対パス。存在・実行可能 |
| RAPID_CROSSCHECK_RUNNER | string(absolute path) | RAPID_CROSSCHECK_MODE が off でないとき Yes | slot runner が完了通知(blue-completed / green-completed)を送る速報クロスチェック runner の実体パス。存在・実行可能 |
| RAPID_CROSSCHECK_WORKER | string(absolute path) | RAPID_CROSSCHECK_MODE が off でないとき Yes | 速報クロスチェック worker の実体パス(ジョブスケジューラの worker ジョブ定義 / 常駐起動が参照する実体)。存在・実行可能 |

- validation_rules: foreground はちょうど 1 slot / 確報の制御キーは置かない / **未知キーは warn**(元資料の 9 キーを未知キーとして列挙しない)/ 上記 9 キー以外に必須キーは無い
- `RAPID_CROSSCHECK_MODE` の foreground と background は、現在 RDRA / USDM(SPEC-005-04)が定める範囲(完了通知の送信・速報管理 DB 書き込み)で **同じ挙動**。両値の挙動差は RDRA に定義が無いため spec では区別しない(判定はすべて「off か off 以外か」で書く)。既存の「on」相当の記述は「off 以外(foreground / background)」に書き換える。BDD の例示値は `background` を使う
- 運用モード(`operation_mode` 派生値)は RDRA バリエーション「運用モード」に従う: 並行稼働 = blue foreground / green background / 速報 background、新実装の単独本番 = blue off / green foreground / 速報 off、次世代実装との並行稼働 = blue background / green foreground / 速報 background。その他の組合せは `custom`
- facade の実行ログ `INFO feature flag loaded ...` から `config_version=` を除去し、`blue_impl=` / `green_impl=` を加える。validate-config.sh --feature-flag の stdout からも `config_version` を除去し `blue_impl` / `green_impl` / `rapid_crosscheck_runner` / `rapid_crosscheck_worker` を出す
- slot runner は完了通知の送信先を `RAPID_CROSSCHECK_RUNNER` で解決する(`$RELAY_GATE_HOME/rapid-crosscheck-runner.sh` の固定パス解決をやめる)
- execution-spec.json の `slots.<role>.impl_version` は feature flag の `BLUE_IMPL` / `GREEN_IMPL` を転記する。`map_version` はジョブマップの任意列 `map_version` を転記し、列が無ければ `null`
- RDRA 情報「feature flag 設定」の属性(9 キー)/ バリエーション「速報クロスチェックモード」(foreground、background、off)/ 条件「速報クロスチェック有効判定」をトレーサビリティ行に反映する

### D2. ジョブマップ・クロスチェックジョブマップ・対象カタログは CSV(CR-002)

- ファイル名: `<role>-job-map.csv`(blue-job-map.csv / green-job-map.csv)、`crosscheck-job-map.csv`、`target-catalog.csv`
- 形式: CSV。1 行目ヘッダー、1 行 1 job_id(対象カタログは 1 行 1 対象)。行頭 `#` の行はコメント(クロスチェックジョブマップの `# exit_code_contract=...` 等の宣言行はこのコメント行に置く)。改行コードは LF。セル内に改行は置けない
- **CSV セルのクォート解析規則(契約に明記)**: セルはカンマ区切り。セルは二重引用符で囲める(囲まない場合はカンマ・二重引用符を含められない)。囲んだセル内の二重引用符は `""` と二重化する。`fixed_params` は JSON 配列文字列を格納するセルで、必ず二重引用符で囲む(例: `"[""p1"",""p2 p3""]"` → 固定引数 `p1` と `p2 p3` の 2 要素。空は `"[]"` または `[]`)。bash 単独(外部 CSV パーサ非依存)で 1 文字ずつ状態機械で解析できる範囲に限定する(ネスト・複数行セル不可)
- slot ジョブマップの列(順序固定): `job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes` の 7 列が必須列。末尾に任意列 `credential_ref` / `map_version` を置ける(ヘッダーに無ければ無いものとして扱う。値が空も可)。**`impl_version` 列は無い**(あれば未知列として warn)
- `host` / `user` は **ローカル実行の slot では空にできる**(両方空 = runner のプロセスユーザーでローカル実行。SSH しない)。片方だけ空は検証 NG(終了コード 2 / runner は exitcode.txt=2)
- 検証エラーの stderr 例は列名を新名称で書く(`error: user is empty ...` / `error: script is not absolute ...` / `error: job map header mismatch expected=job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes[,credential_ref][,map_version] actual=...`)
- `fixed_params` の解析結果を execution-spec.json の `slots.<role>.fixed_params`(JSON 配列)に保存する。引数連結規則は「fixed_params を順序どおり展開 + PARAM を順序保持で後置」(名称変更のみ)
- クロスチェックジョブマップ・対象カタログの列構成は変えない(形式だけ TSV → CSV。列の説明で「タブ」と書いている箇所は「カンマ」に直す)。確報 worker が抜き出す入力ファイルも `input/target-catalog.csv`
- validate-config.sh の `--job-map` の stdout から `impl_version` を除去し `map_version` は任意(無ければ `map_version=-`)
- RDRA 情報「ジョブマップ」の属性名(job_id / host / user / work_dir / script / fixed_params / hang_detect_limit_minutes / credential_ref / map_version)と条件「ジョブマップ解決条件」の CSV 規則をトレーサビリティ行に反映する

### D3. run_id はローカルタイムゾーンの時刻 + job_id + 8 桁 hex(CR-003)

- `shared_rules.run_id.format`: `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}`。例 `20260830T113000-JOB001-3f9a1c2e`。時刻部はホストのローカルタイムゾーン(プロセスの `TZ` 環境変数に従う)で、タイムゾーン指示子(`Z` / オフセット)は付けない
- `final_crosscheck_id` も同じ: `{ローカル yyyymmddThhmmss}-final-{8 桁 hex}`
- 正規表現: `^[0-9]{8}T[0-9]{6}-{job_id}-[0-9a-f]{8}$`
- **`confidence: low` / `_inference.md #9 仮採用` / `todo` の注記を外す**(利用者決定 2026-09-05。USDM SPEC-011-04、RDRA 情報「並行稼働実行(parallel_run)」)
- テスト時刻注入 `RELAY_GATE_NOW` は UTC のまま。**run_id / final_crosscheck_id の時刻部は RELAY_GATE_NOW をプロセスのローカルタイムゾーンへ変換した値**。spec の BDD シナリオと例示値は `TZ=UTC` を前提にしている(RELAY_GATE_NOW=2026-08-30T11:30:00Z → run_id 時刻部 20260830T113000)。この前提を run_id 規則と RELAY_GATE_NOW の説明に 1 行ずつ明記する(シナリオごとに繰り返し書かない)
- 実行ログ・`*_at` 列・started-at.txt・aborted.txt・メール本文の日時は **UTC ISO 8601 Z 付きのまま**(arch CLP-002 は変更されていない)。run_id の時刻部だけがローカル。この不一致は確認推奨項目としてオーケストレータが返すので、subagent は変更しない
- 成果物ディレクトリ名と管理 DB の `run_id` は同じ値。RAPID_CROSSCHECK_MODE=off でも facade 単独で発行する(モードによらず常に発行)

### D4. aborted.txt と slot 実行の状態導出規則(CR-004)

- Runner Result に `aborted.txt` を追加: `$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/<role>/aborted.txt`。内容は中止日時 1 行(UTC ISO 8601 秒精度 Z 付き。RELAY_GATE_NOW 設定時はその値)。writer は abort-blue.sh / abort-green.sh(`.tmp` → mv で公開)。中止時のみ生成
- **状態導出規則(条件「slot 実行の状態導出規則」)**: `exitcode.txt` があれば 0 = SUCCEEDED / 非 0 = FAILED。無く `aborted.txt` があれば ABORTED。どちらも無ければ RUNNING。exitcode.txt と aborted.txt が両方あるときは exitcode.txt を優先する(中止後に実装が終了した場合)
- `shared_rules.exitcode_to_status.slot_execution` を上記に書き換える(「ABORTED は管理 DB の状態更新でのみ表現(成果物からは導出不可)」を削除)
- abort-blue / abort-green:
  - 対象の現在状態は **成果物ファイルから導出**する(started-at.txt なし = 未起動で 3 / exitcode.txt あり = 終端済みで 3 / aborted.txt あり = 中止済みで 3 / どちらも無し = RUNNING)。mode は execution-spec.json の `slots.<role>.mode`(background 以外は 3)
  - yes のとき `aborted.txt` を書く。`RAPID_CROSSCHECK_MODE` が off 以外なら **加えて** 管理 DB(slot_executions / parallel_runs)を条件付き UPDATE で ABORTED にする。off では管理 DB に触れず aborted.txt だけで完了(終了コード 0)
  - **「off では管理 DB が無い旨を stderr に出して終了する」記述を全て除去する**(abort-rapid-crosscheck / abort-final-crosscheck は依頼レコードが管理 DB にしか無いため off で 3 のまま)
  - stdout の `status=ABORTED` 等の出力順は既存どおり。off のときの表示元は成果物ファイル
- background-rerun.sh --role blue|green の事前検証: 元 slot の状態は **常に**ファイル正本(状態導出規則)で判定する(off でも off 以外でも)。ABORTED(aborted.txt あり)/ SUCCEEDED / FAILED はリラン可、RUNNING(exitcode.txt も aborted.txt も無い)は 3
- hang-detector.sh: 走査時に `aborted.txt` を読む。exitcode.txt が無く aborted.txt がある監視対象は判定 `COMPLETED`(中止済み)として監視記録を終端し通知しない。速報比較依頼が ABORTED の場合も同じ
- 管理 DB の `slot_executions.status` はファイル正本と同じ値を保持する二重マッピング(arch storage_mapping E-014 rdb: confidence high に確定)。「仮採用 / DIST-009 / DIST-017」の注記を外す
- RDRA: 情報「Runner Result」の属性 `aborted.txt`、バリエーション「Runner Result 成果物種別」の `aborted.txt`、条件「slot 実行の状態導出規則」「slot 中止可否判定」「リラン事前検証」「ハング検知判定」、状態「slot 実行 RUNNING → ABORTED」をトレーサビリティ行に反映する

### D5. 完了通知失敗の扱い(CR-005)

- RDRA 条件「完了通知失敗の扱い」が新設された。spec 内の「完了通知失敗の検知はスコープ外(spec 追加 / rdra-feedback #8 / DIST-020)」という注記を、条件名 **「完了通知失敗の扱い」** への参照に置き換える
- 内容(変えない): 送信失敗は自動検知しない。slot runner は実行ログに `WARN completion notice failed ...` を残し、Runner Result と終了コードは実装スクリプトの exitcode のまま。復旧は運用者が速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER)を同一引数で再実行する(冪等・先勝ちで完了結果は一度だけ登録)
- 関連 UC: 「速報クロスチェック runner へ完了通知を送信する」(条件行を追加)。USDM SPEC-005-01 の受け入れ条件 3 件(通知失敗時の終了コード / 同一引数再送の冪等 / 自動検知しない)を「関連 USDM」に追記

### D6. 管理 DB は relay-gate 内部のデータストア(CR-006)

- 「外部システム: 管理 DB(RDB)」という表記を **「内部データストア: ジョブキュー兼管理 DB(RDB)」** に改める。RDRA 外部システム.tsv から管理 DB は削除された(残る外部システムは 6 種: ジョブスケジューラ / 現行実装(blue) / 新実装(green) / 比較ツール / メール通知 / リモート実行ホスト(SSH))
- spec.md の「関連 RDRA モデル」外部システム欄・データフロー図のラベル・tier md の gateway 説明で、管理 DB を外部システムとして数えている箇所を内部データストア扱いに直す(参照自体は残してよい。RDB クライアントアダプタは gateway 層のまま)
- 「リモート実行ホスト(SSH)」は外部システムのまま

### D7. 情報属性の整理(CR-007)

- 情報「ハング検知上限設定」の属性から「調整日時」「調整根拠」が削除され、情報「適用構成文書」の属性「運用者の調整記録(hang_detect_limit_minutes の調整日時、調整根拠となる警告時経過時間)」に移った。UC「hang_detect_limit_minutes をジョブごとに調整する」のトレーサビリティ行を付け替える(調整記録の正本 = 適用構成文書またはそのコミット履歴。ジョブマップ列に持たない、は既存の判断どおり)
- 情報「ジョブスケジューラ応答」の属性「応答日時」は削除された。UC「foreground slot の結果をジョブスケジューラへ中継する」等の該当行を削除する(「意図的除外」注記も不要)

### D8. 監視状態 6 値と終端遷移(CR-008)

- バリエーション「監視状態」は状態モデルと同じ 6 値(監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了)。「通知後正常終了」は遷移(ハング疑い通知済み → 正常終了)の別名
- バリエーション「ハング検知判定結果」は 6 値(監視対象外 / 正常終了または中止済み / 監視中 / ハング疑い / 実行エラー / 比較異常)= spec の `hang_judgement`(NOT_TARGET / COMPLETED / MONITORING / HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR)
- 状態.tsv「監視状態」に次の遷移が **RDRA として存在する**(spec の仮採用ではなくなった。「rdra-feedback #3 / #7 / #11」「仮採用」注記を外す): ハング疑い通知済み → 比較異常通知済み / 実行エラー通知済み / 正常終了(通知後正常終了)、監視中 → 正常終了(exitcode 0、または監視対象が ABORTED で中止済み終端)、ハング疑い通知済み → 正常終了(通知後に ABORTED も含む)。遷移 UC は「background 実行の経過時間と終了状態を判定する」「ハング疑い・実行エラー・比較異常を通知する」
- 情報「監視記録」の属性に `monitor_status` の 6 値説明と関連情報「ハング検知定期ジョブ設定」が加わった

### D9. 並行稼働実行の遷移追加(CR-009)

- 状態「並行稼働実行」に次が **RDRA として存在する**(仮採用注記を外す):
  - STARTED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」。既存の `status IN ('STARTED','RUNNING')` 条件付き UPDATE がこれに対応)
  - RUNNING → COMPLETED(遷移 UC「比較ツールでジョブ単位比較を実行して結果を登録する」): 速報比較依頼だけを新規作成したリラン由来(background-rerun --role rapid-crosscheck)の parallel_run は、依頼が終端(SUCCEEDED / FAILED)した時点で速報クロスチェック worker が COMPLETED にする。判定規則: `parallel_runs.parent_run_id IS NOT NULL` かつ当該 run_id の `slot_executions` 行が 0 件(業務ジョブを再実行していない)。条件付き UPDATE(`status='RUNNING'`)
  - RUNNING → COMPLETED(遷移 UC「実装スクリプトを実行して Runner Result を出力する」): 元の execution-spec.json から復元したリラン由来(background-rerun --role blue|green)の parallel_run は、background slot の終端(exitcode.txt 公開)時に slot runner が COMPLETED にする。判定規則: execution-spec.json の `parent_run_id` が非 null(`restored_at` あり)かつ自 slot が background。RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(parallel_run が無い)
- 情報「並行稼働実行(parallel_run)」の説明にも同内容がある

### D10. ハング検知定期ジョブ設定(hang-detector.env)(CR-010)

- RDRA 情報「ハング検知定期ジョブ設定」が新設された(属性: 通知先メールアドレス ALERT_MAIL_TO / 送信コマンド ALERT_MAIL_CMD / 件名プレフィックス ALERT_SUBJECT_PREFIX / 管理 DB 接続参照名 HANG_DB_CONN_REF)。所有者は **基盤適用設計者**(バリエーション「設定所有区分」の値「ハング検知定期ジョブ設定」)
- `config_files[hang-detector.env]`: owner を「基盤適用設計者(設定所有区分: ハング検知定期ジョブ設定)」に改め、「仮採用 / _inference.md #10 / rdra-feedback 対象」注記を外す。キーに `ALERT_SUBJECT_PREFIX`(string、任意、既定 `[relay-gate]`。メール件名の先頭に付ける)を追加する。既存の RAPID_HANG_DETECT_LIMIT_MINUTES / HANG_SCAN_WINDOW_HOURS は運用チューニング値として残す。HANG_DB_CONN_REF の required は「RAPID_CROSSCHECK_MODE が off でないとき Yes」
- 通知メールの件名規約(ui-design.md / 通知 UC)で件名プレフィックスは `ALERT_SUBJECT_PREFIX` から取ると明記する
- UC「ハング疑い・実行エラー・比較異常を通知する」の入力情報に「ハング検知定期ジョブ設定」を加え、関連 USDM に SPEC-008-06 を加える。UC「background 実行の経過時間と終了状態を判定する」も HANG_DB_CONN_REF の出所としてこの情報を参照する

### D11. 比較結果の登録条件(CR-011)

- RDRA 条件「比較結果の登録条件」が新設された(比較ツールを起動して終了コードを得たときだけ comparison_result を登録。比較定義なし・起動失敗では登録せず依頼だけ FAILED(exit_code=6 相当、error_summary に理由)で終端)。spec 内の「comparison_results の登録条件(spec 追加)」を **「比較結果の登録条件」** に改名し「(spec 追加)」「rdra-feedback #12」注記を外す。関連 UC「比較ツールでジョブ単位比較を実行して結果を登録する」、USDM SPEC-005-03

### D12. NFR 7 項目の確定(CR-012)

- nfr の A.2.1.1 / A.3.1.1 / A.3.1.2 / C.2.1.2 / C.4.1.1 / C.5.1.1 / C.6.1.1 は confidence が `user`(利用者確定。適用側で上書き可能な既定値)になった。spec 内でこれらを「仮採用 / confidence low / DIST-003〜008 / DIST-012」と書いている箇所(NFR 反映事項、ログ保管期間、テスト環境、サポート時間など)から仮採用注記を外し「利用者確定の既定値(適用側で上書き可)」とする。グレード値は変えない

## 解消済みの todo / 仮採用(注記を外す対象)

DIST-001(管理 DB の内外)、DIST-009(E-014 二重マッピング)、DIST-017(off 時の abort)、DIST-018(run_id 形式)、DIST-019(hang-detector.env の所有)、DIST-020(完了通知失敗)、DIST-003〜008 / DIST-012(NFR 7 項目)、rdra-feedback #1〜#8、#10〜#12。
**残す**もの: lease / poll の既定値(shared_rules.lease_and_poll の confidence low)、worker_id_default の仮採用、rdra-feedback #9(C2 図の破線)。

## USDM の今回追加分(「関連 USDM」表へ追記する対象)

| SPEC | 追加された受け入れ条件の要旨 | 反映先 UC |
|---|---|---|
| SPEC-001-01 | 元資料の 9 キーで書いた feature flag を検証して未知キー警告が出ない | feature flag を設定する |
| SPEC-004-04 | CSV 列名で読み替えなしに解決 / fixed_params セルの JSON 配列解析 / クロスチェックジョブマップと対象カタログも CSV | slot ごとのジョブマップを定義する、ジョブマップで JOB_ID から実行先を解決する、クロスチェックのジョブマップと比較定義を定義する |
| SPEC-005-01 | 完了通知失敗時の終了コード維持と警告 / 同一引数再送の冪等 / 自動検知しない | 速報クロスチェック runner へ完了通知を送信する |
| SPEC-005-03 | 比較結果の登録条件 | 比較ツールでジョブ単位比較を実行して結果を登録する |
| SPEC-005-04 | RAPID_CROSSCHECK_MODE=background / foreground で完了通知・DB 書き込み、off で何もしない | slot 実行モードを選択して runner を起動する、速報クロスチェック runner へ完了通知を送信する |
| SPEC-008-06 | ハング検知定期ジョブ設定(通知先・送信コマンドで送る / 所有者 / 認証情報なし) | ハング疑い・実行エラー・比較異常を通知する |
| SPEC-010-01 | off で abort-blue → aborted.txt → background-rerun 可 / aborted.txt の ABORTED 判定と監視終端 / background では DB も ABORTED | 実行を ABORTED へ遷移させる、リラン対象を検証する、background 実行の経過時間と終了状態を判定する |
| SPEC-011-04 | run_id の形式(ローカル TZ、Z 無し)/ 成果物と DB で同値 / off でも発行 | slot 実行モードを選択して runner を起動する、execution-spec.json を確定保存する |
| SPEC-011-05 | 管理 DB は内部データストア | (トレーサビリティ・cross-cutting のみ) |

USDM の正本は `docs/usdm/latest/requirements.yaml`。受け入れ条件の文言はそこから引く(推測で書かない)。

## 統一決定(第 1 回更新後にグループ間で食い違った点。契約 = cli-command-contract.yaml を正本にし、以下のとおり揃える)

### U1. slot runner が feature flag の値を得る経路(D1 補足)

- runner は feature-flag.env を **読まない**(既存契約を維持)。facade.sh / background-rerun.sh が feature-flag.env を読み、runner へ **環境変数** で渡す: 既存 4 つ(RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE)に加え、RAPID_CROSSCHECK_MODE が off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)、通常起動では `BLUE_IMPL` / `GREEN_IMPL`(自 slot の実装版。runner が execution-spec.json の slots.<role>.impl_version に転記)。復元起動(--execution-spec)では impl_version は spec から読むので BLUE_IMPL / GREEN_IMPL は渡さない
- 「runner が $RELAY_GATE_CONFIG_DIR/feature-flag.env を自分で読む」と書いた箇所はすべて上記へ直す

### U2. ジョブマップの host / user 列(D2 補足。USDM SPEC-004-04 の受け入れ条件「host と user の列を持たないローカル実行用の slot ジョブマップ … ローカル実行として解決される」に合わせる)

- 列は **ヘッダー名で対応付ける**(順序は元資料の並びを推奨するが検証は名前で行う)。必須列 5: `job_id` / `work_dir` / `script` / `fixed_params` / `hang_detect_limit_minutes`。任意列: `host` / `user`(両方あるか両方無いか。両方無い、または両方の値が空 = ローカル実行。片方だけある / 片方だけ空は違反)、`credential_ref` / `map_version`(末尾の任意列)。未知列は warn
- ヘッダー不一致のエラー文言: `error: job map header mismatch missing=<col,...> path: ...`(必須列の欠落、host / user の片方だけ)。旧「expected=… actual=…」は使わない
- execution-spec.json の slots.<role>.host / user は、列が無い・値が空のとき `null`

### U3. abort-blue / abort-green の管理 DB 更新の失敗と再適用(D4 補足)

- 順序: 成果物再確認 → aborted.txt を .tmp → mv で公開 → (off 以外)slot_executions / parallel_runs を条件付き UPDATE
- UPDATE が **0 件**(管理 DB 側が既に終端・中止済み): 実行ログに `WARN management db not updated ...` を残し終了コード 0(ファイル正本は成立)
- 管理 DB **接続・SQL 失敗**: 終了コード 6(aborted.txt は公開済みのまま残す。stderr `error: management db update failed ...`、`hint: rerun abort-<role>.sh --run-id ... to reapply`)
- **再適用(冪等)**: aborted.txt が既にあり、RAPID_CROSSCHECK_MODE が off 以外で管理 DB の slot_executions.status が RUNNING(または parallel_runs が STARTED / RUNNING)のままなら、プロンプト(または --yes)の後に aborted.txt を書き直さず管理 DB だけ更新し、stdout `status=ABORTED` / stderr `warn: aborted.txt already published; management db updated` で終了コード 0。aborted.txt があり管理 DB も更新済み(または off)なら従来どおり 3(`error: run is not abortable ... status=ABORTED`)

### U4. 文言・出力順は契約(cli-command-contract.yaml)に合わせる

- validate-config.sh --feature-flag の stdout キー順: `config_path, blue_mode, green_mode, blue_impl, green_impl, blue_runner, green_runner, rapid_crosscheck_mode, rapid_crosscheck_runner, rapid_crosscheck_worker, operation_mode, blue_job_map, green_job_map, blue_runner_if_version, green_runner_if_version`
- feature flag の検証エラー文言(契約に無ければ契約へ追加し UC はそれに従う): 必須キー欠落・空 `error: option required option=<KEY> path: ...`(既存定型文)、enum 外 `error: invalid value key=<KEY> value=...`、絶対パスでない `error: path is not absolute key=<KEY> path=...`、実体が無い / 実行不可 `error: file not executable key=<KEY> path=...`、未知キー `warn: unknown key key=<KEY> path: ...`、foreground 重複 / 無し `error: foreground slot must be exactly one blue_mode=... green_mode=...`
- ジョブマップ検証: `error: job map header mismatch missing=... path: ...` / `error: csv quote is invalid line=N path: ...` / `error: <column> is <reason> line=N job_id=... value=...` / `warn: unknown column column=<name> path: ...`
- 完了通知失敗の実行ログ: `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=...`
- UC spec / tier md の BDD で上記と異なる文言(`error: job map csv quote is malformed` / `error: host is empty`(host のみ空は `error: host is empty`、user のみ空は `error: user is empty` で可)/ `error: required key is empty` / `error: path not executable` / `error: path must be absolute` / `WARN unknown feature flag key` / `WARN unknown column in job map` 等)は契約の文言へ揃える

## 第 2 回統一決定(第 1 回更新の完了報告で挙がった食い違い。契約 = cli-command-contract.yaml を正本にし、以下のとおり揃える)

### U5. slot runner の終端 UPDATE 0 件と中止済み slot の再起動(G1 / 契約)

- 終端 UPDATE(`UPDATE slot_executions ... WHERE ... AND status='RUNNING'`)が 0 件のときの実行ログは `WARN management db not updated run_id=... role=...`(U3 と同文。ERROR ではない)。終了コードは exitcode.txt の値のまま
- exitcode.txt が無く aborted.txt がある slot で runner が再起動された場合: 実装を再実行せず、実行ログ `WARN slot already aborted run_id=... role=...` を残して exitcode.txt を書かずに終了コード 6(中止済み slot の再実行は background-rerun.sh で新 run_id を発行して行う)
- 既存の二重起動規則(exitcode.txt あり → 既存値で終了 / started-at.txt だけ → 通常起動は上書き再実行・復元起動は 2)は変えない

### U6. ローカル実行の形式と実行ログ(G1 / 契約)

- host / user が null(列なし・両方空)の slot は、runner のプロセスユーザーで `cd {work_dir} && {script} {fixed_params...} {PARAM...}` を直接起動する(stdin は `/dev/null`。SSH しない)
- 実行ログ: `INFO local exec started run_id=... role=... work_dir=... script=...` / `INFO local exec finished run_id=... role=... exit_code=N`(SSH 実行の `ssh exec started / finished` と対をなす。SSH 実行のログ文言が契約に無ければ同形で `INFO ssh exec started ... host=... user=...` とする)
- 契約 slot runner IF 節にこの形式を追記する。external_interfaces には追加しない(ローカル実行は外部 IF ではない)

### U7. validate-config.sh の補助出力(G2 / 契約)

- `--job-map --verbose` の stderr `info:` 行は 1 行 1 job_id: `info: resolved job_id=... host=<host|-> user=<user|-> exec=<ssh|local> work_dir=... script=... fixed_params=[...] hang_detect_limit_minutes=N`。契約の validate-config.sh stderr に追加する
- `RAPID_CROSSCHECK_MODE` / `BLUE_MODE` / `GREEN_MODE` の enum 外エラーには `hint: use foreground, background or off` を続ける(契約 error_messages に追記)
- CSV クォート不正は全 CSV 共通で `error: csv quote is invalid line=N path: ...`(契約 983 行に既にある。UC はこれに揃える)

### U8. rapid-crosscheck-worker の COMPLETED 遷移ログ(G3 / 契約)

- 実行ログは契約の `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=...`(UC 側の `INFO parallel run completed ...` は契約文言へ揃える)。SQL 条件は `UPDATE parallel_runs SET status='COMPLETED', completed_at=? WHERE run_id=? AND status='RUNNING'`
- 完了通知は「$RAPID_CROSSCHECK_RUNNER を起動できなかった場合」も通知失敗に含める(契約 375 行「起動失敗を含む」のとおり。exit_code は起動失敗時 127)

### U9. background-rerun --role blue|green は管理 DB を事前検証に使わない(G5 / 契約)

- 契約から `error: run not found run_id=... role=...`(slot_executions 行なし)と `warn: mode mismatch spec=... db=...` は削除済み。UC「リラン対象を検証する」の spec.md / tier-ops.md / _api-summary.yaml から slot_executions の SELECT・照合・これら 2 文言・対応する BDD シナリオを削除する(元状態はファイル正本だけで導出)
- abort-blue / abort-green の `error: run not found run_id=... role=...`(3)は「facade/<run_id>/execution-spec.json が無い」場合の文言として残す(契約 739 行)

### U10. operation_mode の英字コード(uxui / 契約)

- `validate-config.sh --feature-flag` の stdout `operation_mode=` と facade.sh 実行ログの値は英字コード: `parallel`(並行稼働 = blue foreground / green background / 速報 background)、`green_only`(新実装の単独本番 = blue off / green foreground / 速報 off)、`next_gen_parallel`(次世代実装との並行稼働 = blue background / green foreground / 速報 background)、`custom`(その他)。契約 config_files.feature-flag.env.derived と ui-design.md の例に書く(RDRA バリエーション「運用モード」の日本語名との対応表を添える)

### U11. その他

- 契約 1114 行の「RDB 列名は exec_user(rdb-schema.yaml)」は削除する(RDB にジョブマップ由来の user 列は無い)
- UC「hang_detect_limit_minutes をジョブごとに調整する」の `_model-summary.yaml` にある `rapid-crosscheck.env` の `rdra_info: 管理 DB 接続設定` は RDRA 情報に存在しないため `rdra_info` を外す(設定ファイル名だけ残す)
- USDM SPEC-008-05 の追加受け入れ条件(調整記録は適用構成文書)に対応する BDD は掲載対象(「USDM の今回追加分」表の漏れ。G4 の追加を採用)
- クロスチェックジョブマップ / 対象カタログのヘッダー検証は列順固定のまま `error: header mismatch expected=... actual=... path: ...`(契約 982 行)。slot ジョブマップだけが `job map header mismatch missing=...`
