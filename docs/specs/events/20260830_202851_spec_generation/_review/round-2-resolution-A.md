# round-2 resolution(担当 A: 実装切替業務 / 適用構成業務 / 実行復旧業務 / 調整 UC)

所有範囲: `実装切替業務/` `適用構成業務/` `実行復旧業務/` `実行監視業務/background 実行監視フロー/hang_detect_limit_minutes をジョブごとに調整する/`。契約(`_cross-cutting/`)は別担当のため未編集。契約側への要求は末尾にまとめる。

略称: S = slot 実行モードを選択して runner を起動する / M = foreground slot の結果をジョブスケジューラへ中継する / R = 実装スクリプトを実行して Runner Result を出力する / J = ジョブマップで JOB_ID から実行先を解決する / X = execution-spec.json を確定保存する / C = クロスチェックのジョブマップと比較定義を定義する / SR = slot runner の実体スクリプトを割り当てる / JM = slot ごとのジョブマップを定義する / OM = 切り替えた運用モードで業務ジョブを実行する / RS = 元の execution-spec.json から復元して新しい run_id で起動する / RQ = 速報比較依頼だけを新規作成する / V = リラン対象を検証する / L = リラン結果を parent_run_id で追跡する / AB = 実行を ABORTED へ遷移させる / A = hang_detect_limit_minutes をジョブごとに調整する

| finding id | severity | resolution | 変更ファイル |
|---|---|---|---|
| F-032 | major | fixed。C の tier 2 ファイルの引数表を「必須 Yes(値必須)/ 既定値 —」、spec レイヤー表を「引数のパスをそのまま使う」に統一。行の値不正を契約の `error: <column> is <reason> line=N job_id=... value=...` 形に(compare_command / comparison_type / compare_options / target_type / empty column)、header mismatch の Then に `path:` 追加。SR 3 ファイルの warn を `warn: runner does not respond to --help slot=... runner=...` に | C/tier-rapid-crosscheck.md, C/tier-final-crosscheck.md, C/spec.md, C/_api-summary.yaml, SR/tier-facade.md, SR/spec.md, SR/_api-summary.yaml |
| F-031 | minor | fixed。S tier 実行ログ一覧に `INFO parallel_run status changed from=STARTED to=RUNNING` 等を契約 execution_log と同順で追加、J tier に `INFO job map resolved ...` 等の実行ログ宣言を追加、R spec の SSH 形式を契約 `ssh -n {exec_user}@{host} '...'` に、M spec / tier の error 行 + artifact_dir 行を 2 行に統一 | S/tier-facade.md, J/tier-facade.md, R/spec.md, R/tier-facade.md, M/spec.md, M/tier-facade.md |
| F-041 | minor | fixed(所有範囲の A tier-ops のみ)。started_at / hang_detect_limit_minutes / hang_suspected_at の列説明を rdb-schema と同文に(rapid-crosscheck の RAPID_HANG_DETECT_LIMIT_MINUTES / 依頼の started_at / 通知送信成功日時)。記録 UC 側は担当外 | A/tier-ops.md |
| F-101 | major | fixed。RS を facade と同じ「spec 保存 → slot_executions INSERT(pid=NULL)→ runner 起動 → pid UPDATE → parallel_runs RUNNING」に改め、起動失敗は FAILED ベストエフォート UPDATE。spec(概要 / データフロー / レイヤー表 / sequence / 状態遷移 / E2E L222)、tier-ops(概要 / 手順 4〜8 / クラッシュ表 / 列説明 / tier BDD 追加)、_model-summary(pid=NULL INSERT + pid UPDATE + FAILED UPDATE)を更新 | RS/spec.md, RS/tier-ops.md, RS/_model-summary.yaml |
| F-102 | major | fixed。RQ の E2E を `{新 run_id}` + 正規表現 `^20260830T130000Z-JOB001-[0-9a-f]{8}$` 照合に書き換え、Given に RELAY_GATE_NOW を追加(系譜シナリオは 13:30:00Z で R3 を照合)。A は Given に RELAY_GATE_NOW=2026-08-30T02:00:00Z を置き Then を形式照合に。RQ tier-rapid-crosscheck の固定 run_id も R2 / R3 参照に | RQ/spec.md, RQ/tier-rapid-crosscheck.md, A/spec.md |
| F-104 | major | fixed。`ERROR management db update failed table=parallel_runs run_id=...` に統一(tier L33 / 実行ログ一覧 / tier BDD)。実行ログ一覧に `INFO parallel_run status changed from=RUNNING to=COMPLETED` を LEVEL 付きで明記 | M/tier-facade.md |
| F-105 | major | fixed。`ERROR slot_executions update affected 0 rows run_id=... role=...` に統一(tier L55 / tier BDD / _model-summary note) | R/tier-facade.md, R/_model-summary.yaml |
| F-108 | major | fixed。current_limit_minutes を「集計期間内で judged_at 最大の行」に統一(spec 計算ルール / tier-ops 集計手順 4) | A/spec.md, A/tier-ops.md |
| F-109 | major | fixed。validate-config.sh の終了コード 6 を削除し、ファイル不在・読み取り不可は 2(`error: config file is not readable path: ...`)に | A/tier-facade.md, A/_api-summary.yaml |
| F-118 | minor | fixed。S のエラーメッセージ表を「接続失敗 `error: management db connection failed run_id=... conn_ref=...`」と「INSERT / UPDATE 失敗 `error: management db insert failed table=... run_id=...` / `error: management db update failed table=parallel_runs run_id=...`」の 2 行に分け、spec の Then を接続失敗の定型文に | S/tier-facade.md, S/spec.md |
| F-119 | minor | fixed。`feature flag loaded` の key 順を契約(blue_mode 先頭・config_version 4 番目)に | S/tier-facade.md |
| F-120 | minor | fixed(所有範囲の buc-spec のみ)。CRUD 表の S 列を `C / U` に。rdb-schema used_by は契約側へ要求 | 実装切替業務/実装切替ジョブ実行フロー/buc-spec.md |
| F-121 | minor | fixed。OM _api-summary の `--feature-flag` を required: false + 排他注記、synopsis に `[--help]` | OM/_api-summary.yaml |
| F-122 | minor | fixed。3 箇所を `WARN stale execution-spec lock reclaimed run_id=... age_seconds=...` に | X/tier-facade.md, X/spec.md |
| F-123 | minor | deferred(契約側)。既存 execution-spec.json の解析失敗は「lock 取得後に読んだファイルが壊れている」実行時異常で、入力・設定検証エラー(2)ではなく 6 が妥当。UC 側を 2 に寄せると「JSON 不正 = 6」の V UC(`execution-spec is not readable` 6)と食い違う。契約 runner IF exit 6 condition への追記を要求する | — |
| F-137 | minor | fixed。RS / RQ の _model-summary から自 UC が使わない indexes_needed(parent_run_id / (status, mode) / (status, requested_at))を削除 | RS/_model-summary.yaml, RQ/_model-summary.yaml |
| F-138 | minor | fixed。RS tier-ops に設定契約節(引き継ぐ 4 変数 + RELAY_GATE_NOW、restored_at / run_id 時刻部 / requested_at / started_at の出所)、RQ tier-ops に同節(runner 起動なしのため引き継ぎ無し)を追加。spec 計算ルールにも RELAY_GATE_NOW を明記 | RS/tier-ops.md, RS/spec.md, RQ/tier-ops.md, RQ/spec.md, RS/_model-summary.yaml, RQ/_model-summary.yaml |
| F-139 | minor | fixed。RS off シナリオの Given に started-at.txt の存在、V RUNNING シナリオの Given に execution-spec.json(green.mode=background)を追加 | RS/spec.md, V/spec.md |
| F-140 | minor | fixed。実行中止フロー buc-spec のマッピング表に STARTED 行(仮採用)を追加、AB spec のデータフロー / 状態遷移 / 関連 RDRA を「STARTED / RUNNING → ABORTED」に | 実行復旧業務/実行中止フロー/buc-spec.md, AB/spec.md |
| F-141 | minor | fixed(UC 側)。V / L の tier-ops と _api-summary に `error: management db connection failed run_id=... conn_ref=...`(6)/ `error: management db query failed run_id=...`(6)を転記(L _api-summary には入力エラー 2 の定型文も転記)。契約 background-rerun.sh stderr への転記は契約側へ要求 | V/tier-ops.md, V/_api-summary.yaml, L/tier-ops.md, L/_api-summary.yaml |
| F-142 | minor | fixed。JM の行の値不正 8 文言を `error: <column> is <reason> line=N job_id=... value=...` 形に(`job_id is invalid` / `host is empty` / `script_path is not absolute` 等) | JM/tier-facade.md |
| F-132 | minor | fixed。A tier-ops に設定契約節(feature-flag.env の RAPID_CROSSCHECK_MODE、rapid-crosscheck.env の RAPID_DB_CONN_REF、不在・欠落の定型文と終了コード)を追加、_model-summary に 2 設定ファイルの repository record を追加 | A/tier-ops.md, A/_model-summary.yaml |

集計: fixed 21 / deferred 1(F-123)。

## 検証

- 変更 UC dir 15 件で `validateApiSummary.js` / `validateModelSummary.js` PASS
- 変更 md(spec / tier / buc-spec)を `npx md-mermaid-lint` 1 ファイルずつ実行し、すべて「All Mermaid diagrams are syntactically correct」

## 契約側への要求(別担当)

1. F-101: `rdb-schema.yaml` slot_executions.used_by の RS を `["INSERT", "UPDATE"]` に。`cli-command-contract.yaml` background-rerun.sh exit 6 meaning に「runner 起動失敗時は起動前に INSERT した slot_executions 行を FAILED / completed_at にベストエフォート UPDATE(UPDATE 失敗は実行ログ ERROR のみ)」を追記
2. F-120: `rdb-schema.yaml` slot_executions.used_by の S を `["INSERT", "UPDATE"]` に
3. F-123: runner IF exit 6 condition に「既存 execution-spec.json の解析失敗(通常起動)」を追記
4. F-141: background-rerun.sh stderr に `error: management db connection failed run_id=... conn_ref=...`(6)/ `error: management db query failed run_id=...`(6)を転記
5. F-032 補足: C の tier で `error: compare_options is missing {blue} or {green} line=N job_id=... value=...` / `error: job_id is not final-crosscheck for comparison_type=full ...` / `error: <column> is empty line=N ...` を共通形式の具体例として採用した。契約 validate-config.sh stderr の例示に矛盾しないが、契約に列挙したい場合は同文を使うこと
6. F-118 / F-104 補足: S / RS の pid UPDATE 失敗の実行ログを `ERROR management db update failed table=slot_executions run_id=...` とした。facade.sh execution_log に同行を追加すると整合が完全になる
