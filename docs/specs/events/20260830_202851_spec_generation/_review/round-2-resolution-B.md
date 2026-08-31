# round-2 resolution(担当 B: クロスチェック業務 + 実行監視業務の 4 UC)

- 所有範囲: `クロスチェック業務/` 全部、`実行監視業務/background 実行監視フロー/` の受信・判定・通知・記録 UC と buc-spec.md
- 方針: 契約(cli-command-contract.yaml / ui-design.md / data-visualization.md / rdb-schema.yaml)を正とし UC 側を合わせる。契約に無い値は UC 側で暫定確定し「契約側への要求」に記す
- 検証: 変更 UC dir の validateApiSummary.js / validateModelSummary.js はすべて PASS、変更 md の md-mermaid-lint はすべて OK

| finding | severity | resolution | 変更ファイル |
|---|---|---|---|
| F-019 | minor | fixed: ABORTED 検出時 `exit_code=-` に統一。tier BDD / spec Then に `exit_code=-` 追加 | 比較実行(速報)/tier-rapid-crosscheck.md, spec.md |
| F-041 | minor | fixed(所有分): 記録 UC の hang_detect_limit_minutes / started_at 列説明を rdb-schema に揃えた。調整 UC の tier-ops.md L85-88 は所有範囲外(未対応) | 監視記録を保存する/tier-ops.md, _model-summary.yaml |
| F-103 | major | fixed: claim UC・完了通知 UC の exit 2 文言を `error: config file not found path: ...` / `error: option required option=RAPID_DB_CONN_REF path: ...` に統一(設定節・stderr 一覧・BDD・_api-summary)。env 不在シナリオを追加。`management db is not configured` は off(3)専用 | 速報比較依頼を claim する/tier-rapid-crosscheck.md, _api-summary.yaml; 完了通知/tier-rapid-crosscheck.md, _api-summary.yaml |
| F-106 | major | fixed: stderr を `error: compare tool launch failed final_crosscheck_id=20260830T210000Z-final-7b2c9e1f command=/opt/compare/missing.sh`、error_summary を速報と同じ `launch failed` に統一。_api-summary.stderr も契約文言に転記 | 比較実行(確報)/tier-final-crosscheck.md, spec.md, _api-summary.yaml |
| F-107 | major | fixed: `error: invalid value option=--business-date value=20260830`(tier は `hint: expected YYYY-MM-DD` 併記) | 登録 UC/tier-final-crosscheck.md, spec.md |
| F-108 | major | 報告のみ: 対象(hang_detect_limit_minutes をジョブごとに調整する)は所有範囲外。data-visualization.md(judged_at 最大)に揃える修正が必要 | — |
| F-111 | minor | fixed: `conn_ref=...` を追加(tier stderr / 実行ログ / _api-summary)。spec BDD の Given に RAPID_DB_CONN_REF=relaygate-db、Then に `conn_ref=relaygate-db` | claim UC/tier-rapid-crosscheck.md, _api-summary.yaml, spec.md |
| F-112 | minor | fixed(UC 側): tier BDD を `error: invalid value option=--run-id value=abc` に変更。契約 rapid-crosscheck-result.sh stderr への追記は契約担当へ要求 | 速報比較結果を参照する/tier-rapid-crosscheck.md |
| F-113 | minor | fixed: `--exit-code` を「0〜255 の整数(範囲外・非整数は 2)」に統一 | 完了通知/tier-rapid-crosscheck.md, _api-summary.yaml |
| F-114 | minor | fixed: 再通知シナリオの Given に parallel_runs 行と blue/green_status=SUCCEEDED を明記。FK 記述を parallel_runs のみに修正 | 依頼作成 UC/tier-rapid-crosscheck.md |
| F-115 | minor | fixed(UC 側で暫定確定): RUNNING 遷移 UPDATE 0 行は claim の 4 行のみ出し `request_status=` 以降は出さない。tier 出力契約・処理フロー・tier BDD Then に明記。契約 stdout への追記を要求 | 比較実行(速報)/tier-rapid-crosscheck.md |
| F-116 | minor | fixed(暫定): 条件名に「(spec 追加。RDRA 条件.tsv 未登録)」を付記。rdra-feedback.md への起票は cross-cutting 担当へ要求 | 比較実行(速報)/spec.md |
| F-117 | minor | fixed: sequenceDiagram の stdout に `job_id=` 追加 | 完了通知/spec.md |
| F-124 | minor | fixed: started_at / completed_at / requested_at を `:now(RELAY_GATE_NOW 設定時はその値)` 表記に統一 | 比較実行(確報)/tier-final-crosscheck.md, _model-summary.yaml; 登録 UC/_model-summary.yaml |
| F-125 | minor | fixed: 契約に合わせ `status=` を落とした(`error: polling limit exceeded final_crosscheck_id=... limit_sec=...`)。最後の status は実行ログ `INFO polling` に残す旨を付記 | 登録 UC/tier-final-crosscheck.md, spec.md |
| F-126 | minor | fixed: 判別規則を「`final_crosscheck_id=` または `conn_ref=` を含む」に改め、実行ログ `INFO request registered` による確認手順を追記 | 結果確認 UC/tier-final-crosscheck.md |
| F-127 | minor | fixed: _model-summary の where を `final_crosscheck_id = ?` のみに(終端判定は domain) | 中継 UC/_model-summary.yaml |
| F-128 | minor | fixed: Given に FINAL_POLL_INTERVAL_SEC=1 追加 | 結果確認 UC/tier-final-crosscheck.md |
| F-129 | minor | fixed: Given のスタブ stdout を `\n` 付きに統一 | 比較実行(確報)/tier-final-crosscheck.md |
| F-130 | minor | fixed: spec L36 / L172 を tier の全キー形式に書き換え(Given に started-at / RELAY_GATE_NOW を追加し judged_at を確定) | 監視記録を保存する/spec.md |
| F-131 | minor | fixed(UC 側): 通知 tier BDD を `error: option required option=ALERT_MAIL_TO path: ...`、判定 tier stderr / _api-summary に定型文 2 種(config file not found / option required HANG_DB_CONN_REF\|ALERT_MAIL_TO)と `management db connection failed conn_ref=` を追加。契約 hang-detector.sh stderr への追記を要求 | 通知 UC/tier-ops.md; 判定 UC/tier-ops.md, _api-summary.yaml |
| F-133 | minor | fixed(契約に合わせる): 判定表に「ABORTED で未終端の監視記録が無い role は走査対象外(判定・記録しない)」を追加。走査手順 3 と _model-summary where に同注記。tier BDD の Given に monitor_records MONITORING 行を追加(spec BDD は既に同形) | 判定 UC/tier-ops.md, _model-summary.yaml |
| F-134 | minor | fixed: `warn: execution-spec missing run_id=... path: ...`、`warn: started-at is invalid run_id=... role=... value=...`(stderr + 実行ログ WARN 同文)に統一 | 判定 UC/spec.md, tier-ops.md, _api-summary.yaml |
| F-135 | minor | fixed(所有分): 通知 tier BDD の 80 桁 Then に `artifact_dir` 行(11 行目)の例外を明記。asyncapi L564 / ui-design.md は所有範囲外 | 通知 UC/tier-ops.md |
| F-110 | minor | 対象外: 契約内の矛盾(契約担当)。UC 側は「実行ログ WARN のみ」で既に統一済み | — |
| F-136 | minor | 対象外: rdb-schema / ui-design(契約担当) | — |
| F-109 | major | 対象外: 調整 UC(所有範囲外) | — |

## 契約側への要求(契約担当へ)

1. rapid-crosscheck-runner.sh(F-103): stderr と exit 2 condition に `error: config file not found path: ...` / `error: option required option=RAPID_DB_CONN_REF path: ...` を追記
2. rapid-crosscheck-worker.sh stdout(F-115): 「RUNNING 遷移の UPDATE 0 件(他 worker に奪われた / 中止済み)は claim の 4 行のみで終わり `request_status=` 以降は出さない」を追記
3. final-crosscheck-worker.sh(F-106): 起動失敗時の error_summary の値 `launch failed`(速報 worker と同値)を明記
4. rapid-crosscheck-result.sh stderr(F-112): `error: invalid value option=--run-id value=...` / `error: option required option=--run-id` を追記
5. hang-detector.sh stderr(F-131): `error: config file not found path: ...` / `error: option required option=HANG_DB_CONN_REF|ALERT_MAIL_TO path: ...`(2)を追記
6. rdra-feedback.md(F-116): 条件「comparison_results の登録条件」を RDRA 条件.tsv への追加候補として起票
7. 所有範囲外の未対応: F-108(調整 UC を judged_at 最大に)、F-041 の調整 UC 分、F-135 の asyncapi / ui-design 分
