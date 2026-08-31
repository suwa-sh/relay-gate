# Step3 Round 2 レビュー対応(G3: 確報クロスチェックフロー 5 UC + background 実行監視フロー 4 UC)

- 対象レビュー: `step3-round-2-G3.md`(major 4 / minor 12)+ `step4-review-datastore.md` #7 + `uc-dependencies.md` 暗黙参照 #1 + `traceability-matrix.md` パターン A + `usdm-acceptance-matrix.md` SPEC-011-03 partial + 実行ログ形式の参照追記
- 方針: 横断契約(cli-command-contract / asyncapi / rdb-schema / ui-design)の値を正として UC 側を合わせる。`_cross-cutting/` と所有範囲外 UC は編集しない
- 集計: fixed 18 / deferred 0 / out-of-scope 1(#14)

パスは E = `docs/specs/events/20260830_202851_spec_generation` からの相対。監視 = `E/実行監視業務/background 実行監視フロー/`、確報 = `E/クロスチェック業務/確報クロスチェックフロー/`。

## G3 指摘の対応

| # | severity | 対応 | 変更ファイル | 理由・内容 |
|---|---|---|---|---|
| 1 | major | fixed | 監視/判定/_model-summary.yaml, spec.md, tier-ops.md / 監視/通知/spec.md, tier-ops.md / 監視/記録/spec.md, tier-ops.md / 監視/buc-spec.md | 走査 SQL の除外リストから `HANG_SUSPECTED_NOTIFIED` を外し、判定 UC の走査手順・repository 説明・判定表前提に「HANG_SUSPECTED_NOTIFIED は未終端として再判定」を明記。通知 UC の冪等判定・処理フロー・遷移表に HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED を追加(状態.tsv に無い仮採用と注記)。判定 UC の HANG_SUSPECTED_NOTIFIED → COMPLETED の事前条件に「依頼が SUCCEEDED かつ OK」を追加。BDD を判定 UC(再判定)・通知 UC(別種別 1 回送信)に追加。buc-spec の状態遷移図・マッピング表を同期。rdra-feedback への記録は別担当 |
| 2 | major | fixed | 確報/比較ツール…/tier-final-crosscheck.md, spec.md | 起動形式を契約 `compare_command + compare_options`(`{catalog_path}` / `{catalog_version}` / `{business_date}` 置換、固定オプション追記なし)に統一。spec の処理フロー `G->>Tool` 行・計算ルール「比較ツール引数」・tier md「比較ツールの起動」の 3 箇所を揃え、BDD「対象一覧を成果物に記録する」で置換後の引数を検証 |
| 3 | major | fixed | 監視/判定/spec.md, tier-ops.md | 整数でない exitcode.txt は EXEC_ERROR、通知の `exit_code=-`(asyncapi `^([0-9]{1,3}\|-)$`)、実行ログ `WARN invalid exitcode run_id=... role=... value=...`。`-1` は使わない。判定表に行を追加し異常系 BDD「exitcode.txt が整数でない」を追加 |
| 4 | major | fixed | 確報/保存済み…/spec.md | 到達不能な正常系「ABORTED は保存済み 3 値だけを返す」を削除し、異常系「ABORTED で exit_code が NULL のとき終了コード 6 を返す」に統合(状態名を出さない Then を追加)。バリエーション「ABORTED」行・処理フロー alt・関連 USDM(SPEC-006-03)の記述を「常に NULL」に修正 |
| 5 | minor | fixed | 確報/claim/tier-final-crosscheck.md | `--worker-id` を `^[A-Za-z0-9_-]{1,64}$` に修正。既定値 `{hostname}-{pid}` はホスト名の `.` を `-` に置換して生成する(仮採用)と注記 |
| 6 | minor | fixed | 監視/記録/_model-summary.yaml, tier-ops.md | インデックスを `(job_id, role, judged_at)`(`idx_monitor_records_job_id_role_judged_at`)に修正(step4 datastore #7 と同一) |
| 7 | minor | fixed | 監視/判定/tier-ops.md | 実行ログ `judged` 行を契約の `--verbose` 説明に合わせ job_id なしに統一(spec.md / 契約 / tier md が一致) |
| 8 | minor | fixed | 監視/判定/spec.md | 関連 RDRA モデルに「比較結果(comparison_result)」「feature flag 設定」を追加 |
| 9 | minor | fixed | 確報/登録/spec.md | `final_crosscheck_id` の完全一致を形式一致(`^[0-9]{8}T[0-9]{6}Z-final-[0-9a-f]{8}$`)に緩和(正常系「SUCCEEDED まで待機」・異常系「polling 上限超過」) |
| 10 | minor | fixed | 確報/claim/spec.md | Given に「起動後に待機する compare_command スタブ」を置き、Then を実行ログ `claimed` 行 + worker_id / lease_until の記録に限定。status は CLAIMED または RUNNING とし、`--once` が同一プロセスで比較実行へ進む旨を注記 |
| 11 | minor | fixed | 確報/確認/tier-final-crosscheck.md | ABORTED で exit_code NULL の 6 は stderr 0 バイトのため、runner 実行ログ `WARN relay without stored exit_code` で確認する補足を追加 |
| 12 | minor | fixed | 確報/登録/tier-final-crosscheck.md, _api-summary.yaml | (a) `FINAL_POLL_LIMIT_SEC` の検証を契約の `integer(>=1)` に揃え、INTERVAL 未満は検証エラーにしない旨を注記。(b) `_api-summary` の stderr に終端到達後の無加工中継を追記 |
| 13 | minor | fixed | 確報/比較ツール…/tier-final-crosscheck.md | 根拠を cli-command-contract.yaml `hang-detector.sh` / asyncapi.yaml `hang-alert-mail` に変更し、方針資料 C2 図との差異を「runner の polling 上限で代替する仮採用(rdra-feedback で記録)」と注記。rdra-feedback への記録は別担当 |
| 14 | minor | out-of-scope | (E/_cross-cutting/ux-ui/ui-design.md) | 横断規約側の `COMPARE_ERROR` 欠落。UC 側の修正は不要。契約担当へ要求(下記) |
| 15 | minor | fixed | 監視/判定/_api-summary.yaml, tier-ops.md | 終了コード 2 の条件に `ALERT_MAIL_TO` 空 / `ALERT_MAIL_CMD` 実行不可を追記 |
| 16 | minor | fixed | 確報/buc-spec.md | 状態遷移図に `RUNNING --> ABORTED`(参考・別 BUC)と `ABORTED --> [*]` を追加し、終端 3 状態を明記 |

## 追加作業の対応

| 作業 | 対応 | 変更ファイル | 内容 |
|---|---|---|---|
| step4 datastore #7 | fixed | 監視/記録/_model-summary.yaml, tier-ops.md | G3 #6 と同一 |
| step4 datastore #2 確認 | 確認のみ | — | 判定 UC の spec.md / tier-ops.md / _model-summary.yaml に `slot_executions` への SELECT は無く、background slot は成果物ファイル走査に統一されている |
| uc-dependencies 暗黙参照 #1 | fixed | 監視/通知/_api-summary.yaml, tier-ops.md | `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `background-rerun.sh` / `rapid-crosscheck-result.sh` を `role: uses`(synopsis 参照のみ)で宣言。tier md に synopsis 依存を明記 |
| traceability パターン A | fixed | 監視/判定/spec.md | バリエーション一覧に「ジョブスケジューラ起動ジョブ種別 = ハング検知定期ジョブ」を追加。関連 RDRA モデルにも行を追加 |
| usdm SPEC-011-03 partial | fixed | 確報/比較ツール…/spec.md | BDD「対象一覧を成果物に記録する(SPEC-011-03)」を追加(`input/target-catalog.tsv` に catalog_version の対象一覧が残ることを Then で検証)。関連 USDM に REQ-011 / SPEC-011-03 行を追加 |
| 実行ログ形式の参照 | fixed | 監視/判定/tier-ops.md, 監視/通知/tier-ops.md, 監視/記録/tier-ops.md, 確報/claim/tier-final-crosscheck.md, 確報/比較ツール…/tier-final-crosscheck.md, 確報/保存済み…/tier-final-crosscheck.md | 実行ログ出力の記述がある 6 tier md に、ログ行形式は `ui-design.md`(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」がこの UTC 時刻列に対応する旨を追記。受信 UC / 登録 UC / 確認 UC の tier md には実行ログ出力の記述が無いため対象外 |

## 契約側への要求(別担当)

1. `ui-design.md`「ハング検知判定結果」の状態表示に `COMPARE_ERROR`(速報クロスチェック異常)を追加する(G3 #14)
2. `cli-command-contract.yaml` の `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `background-rerun.sh` / `rapid-crosscheck-result.sh` の `used_by_ucs` に UC「ハング疑い・実行エラー・比較異常を通知する」を追加する(uc-dependencies #1)
3. `rdra-feedback.md` に以下を記録する: (a) 監視状態の HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED(および速報比較依頼の HANG_SUSPECTED_NOTIFIED → COMPLETED)が状態.tsv に無い(G3 #1)、(b) 確報依頼のハング監視は runner の polling 上限で代替する仮採用で、方針資料 C2 図の HangDetector → FinalQueue と差異がある(G3 #13)
4. `worker_id_default`(`{hostname}-{pid}`)でホスト名に `.` が含まれる場合の扱い(UC 側は `.` を `-` に置換して生成する仮採用)を契約に明記する(G3 #5)

## 検証

- `validateApiSummary.js` / `validateModelSummary.js`: 変更した 8 UC ディレクトリすべて PASS
- `npx md-mermaid-lint`: 変更した md(確報 5 UC + buc-spec、監視 3 UC + buc-spec)すべて OK
