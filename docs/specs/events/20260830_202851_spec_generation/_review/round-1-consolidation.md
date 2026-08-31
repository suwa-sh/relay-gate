# round-1 統合修正記録(Step6.5 consolidation)

> UC 側 4 担当(G1〜G4)と契約側担当の並行修正で残った相互追従要求・deferred を閉じる。入力: `round-1-resolution-G1.md` 〜 `G4.md`、`round-1-resolution-cross-cutting.md`。
> 略記: contract = `_cross-cutting/api/cli-command-contract.yaml`、ui = `_cross-cutting/ux-ui/ui-design.md`、fb = `_cross-cutting/rdra-feedback.md`。

## 確定決定 1〜11 の対応

| # | 項目 | 対応 | 変更ファイル |
|---|---|---|---|
| 1 | validate-config.sh の共通 stderr 形式 / 値必須 / tier=tier-facade / defined_in_uc 単一化の UC 追従 | 契約の文言を正として追従。JM: `job map header mismatch missing=` → `header mismatch expected=... actual=... path: ...`、duplicate の `lines=<n1,n2,...>`、`config file not found path: `、_api-summary を uses に変更(定義元 = feature flag UC)。FF: synopsis に `[--help]`、stderr に共通形式を注記。クロスチェック定義 UC: tier-rapid / tier-final の冒頭を「validate-config.sh(tier-facade 定義)のオプションを利用する」に、_api-summary を単一エントリ `validate-config.sh`(tier-facade / uses / default 削除・値必須)に書き換え、検証表の文言(file not found / header mismatch path: / column count line= expected= actual= / duplicate lines= / declaration not found)を共通形式に統一。uc-dependencies.md の UC-31 / UC-32 行を uses に修正。契約側はヘッダー不一致の注記を「どれを違反とするかは検証種別の列定義に従う(slot ジョブマップは順序違いを受け付け、未知列は warn:)」に精緻化 | JM/tier-facade.md, JM/spec.md, JM/_api-summary.yaml, FF/_api-summary.yaml, FF/tier-facade.md, CD/tier-rapid-crosscheck.md, CD/tier-final-crosscheck.md, CD/spec.md, CD/_api-summary.yaml, _cross-cutting/uc-dependencies.md, contract |
| 2 | 管理 DB 障害の定型文統一(`management db unavailable` 廃止) | 確報 claim UC(spec / tier)を `connection failed worker_id=`、登録 UC・中継 UC の polling / SELECT 失敗を `query failed final_crosscheck_id=`、登録 UC の接続不能シナリオを `connection failed conn_ref=`、判定 UC spec を `connection failed conn_ref=` に修正。あわせて登録 UC の exit 2 文言を契約に統一(`option required option=FINAL_DB_CONN_REF path: ...` / `target_catalog_path declaration not found path: ...` / `catalog version not found catalog_version=v3 path: ...`) | 確報 claim/spec.md, tier-final-crosscheck.md / 登録/spec.md, tier-final-crosscheck.md / 中継/spec.md, tier-final-crosscheck.md / 判定/spec.md |
| 3 | final worker: 終端 UPDATE 0 件 = exit 0 `WARN request already terminal`、カタログ 0 行 = 6、polling は status のみ | UC 側(比較実行 / 登録 / 中継)は G3 で反映済みを grep で確認。契約側は速報 / 確報 worker の stderr にあった `warn: request already terminal` を「stderr に出さず実行ログ WARN のみ」に修正(UC 側と一致させた) | contract |
| 4 | background-rerun.sh: off 時 started-at.txt なし → hint + exit 3 未起動 | 契約に `hint: source run has not started; rerun the scheduler job instead`(error は `mode=background status=-`)と exit 3 condition「元 slot が未起動」を追加。事前検証順と artifact_layout started-at.txt readers を「background-rerun.sh --role blue|green が存在有無だけを読む」に修正(契約側 F-042 の「読まない」は G4 F-042 の UC 側決定と食い違っていたため UC 側に合わせた) | contract |
| 5 | abort-final-crosscheck.sh の DB 未設定文言 | 契約と ui を `error: management db is not configured run_id=...`(off 付記なし。final-crosscheck.env / FINAL_DB_CONN_REF の有無だけで判定)に修正。UC 側(G4)は同文で反映済み | contract, ui |
| 6 | RELAY_GATE_NOW の契約宣言と readers | 確認済み: contract `environment_variables.RELAY_GATE_NOW` の purpose に hang-detector / rapid・final worker / abort-* / background-rerun / facade / slot runner を列挙、runner_inheritance あり。ui 環境変数表にも同行あり。変更なし | — |
| 7 | 12 項目の両側反映確認 | すべて grep で両側に存在を確認(hang_judgement 6 値 11 ファイル / execution-spec 欠落 warn 4 / ABORTED → COMPLETED 終端 / slot_executions 起動前 INSERT pid=NULL 4 / 引き継ぎ env 4 つ / completion notice failed 実行ログのみ 5 / facade 実行ログ operation_mode= 6 / facade exit 6 限定 / rapid worker off=3・stdout `-`・ABORTED 4 / abort-final は RAPID_CROSSCHECK_MODE 非参照 4 / rerun rapid-crosscheck は execution-spec 不要 / slots 節なし=off 9)。判定 UC tier-ops の「既定 60 分で続行しない」は「既定値で判定しない」に言い換え | 判定/tier-ops.md |
| 8 | runner 起動失敗時の slot_executions FAILED ベストエフォート更新 | 契約 facade.sh exit 6 の meaning に 1 行反映(UPDATE 失敗は実行ログ ERROR のみ、終了コード 6 不変) | contract |
| 9 | F-043 buc-spec の STARTED → ABORTED | 実行中止フロー buc-spec の状態遷移図に `P_STARTED --> P_ABORTED: STARTED → ABORTED(仮採用。rdra-feedback #4。起動直後の中止)` を追加し、注記・本文を仮採用済みの表現に修正 | 実行復旧業務/実行中止フロー/buc-spec.md |
| 10 | rdra-feedback #11 | 「監視状態: 中止済み対象(ABORTED)の監視記録を COMPLETED で終端する遷移」「バリエーション『ハング検知判定結果』を hang_judgement 6 値に揃える」を #11 として追記。あわせて #8 の「stderr.log に warn:」を実行ログ WARN(F-003 後の正)に修正 | fb |
| 11 | rdb-schema `hang_suspected_at` = 送信成功日時、data-visualization current_limit_minutes の出所 | 反映済みを確認(rdb-schema.yaml L530、data-visualization.md L64)。変更なし | — |

## 各 resolution の要求・deferred の確認

| 出所 | 要求 / deferred | 状態 |
|---|---|---|
| G1 契約要求 1(F-015 derived) | 反映済み(contract L1010) | 確認済み |
| G1 契約要求 2(F-005 exit 6 限定) | 反映済み(contract facade.sh exit 6 condition) | 確認済み |
| G1 契約要求 3(F-004 起動前 INSERT / 終端 0 件 ERROR) | 反映済み(facade.sh idempotency / slot runner idempotency) | 確認済み |
| G1 契約要求 4(F-006 env 4 つ / exit 2) | 反映済み(contract notes L227 / config_files.rapid-crosscheck.env.on_missing)。UC 側の文言 `RAPID_DB_CONN_REF required path=` は契約の `option required option=RAPID_DB_CONN_REF path: ...` に追従(S / R tier md) | 対応 |
| G1 契約要求 5 / F-032 deferred(共通 stderr 形式) | 契約で決定済み。JM / CD tier md を追従(本記録 #1) | 対応 |
| G1 F-033 対象外 | G2 が CD/spec.md に header mismatch シナリオ追加済み。文言を共通形式(path: 付き)に揃えた | 対応 |
| G2 契約要求 1(F-003 notes) | 反映済み | 確認済み |
| G2 契約要求 2(F-018 worker exit 3) | 反映済み(contract L384) | 確認済み |
| G2 契約要求 3(F-019 stdout `-` / ABORTED) | 反映済み | 確認済み |
| G2 契約要求 4(RELAY_GATE_NOW) | 反映済み | 確認済み |
| G2 契約要求 5(ui 出力例 FAILED) | 反映済み(cross-cutting F-035) | 確認済み |
| G2 契約要求 6 / F-032 deferred(値省略可否) | 値必須で確定。CD/_api-summary から default を削除し値必須を明記 | 対応 |
| G3 契約要求 1(RELAY_GATE_NOW) | 反映済み | 確認済み |
| G3 契約要求 2(hang_judgement 6 値) | 反映済み(contract L169 / ui) | 確認済み |
| G3 契約要求 3(execution-spec 欠落 warn) | 反映済み(contract L532 / L1260) | 確認済み |
| G3 契約要求 4(ABORTED の SELECT を readers / used_by に) | 反映済み(contract L535 / rdb slot_executions.used_by) | 確認済み |
| G3 契約要求 5(80 桁は 1〜13 行目のみ) | ui は反映済み。asyncapi.yaml HangAlertMail description と ux-design.md が「1 行 80 桁以内」のままだったため追従(冪等判定も monitor_status 遷移有無に修正) | 対応 |
| G3 契約要求 6(final worker WARN / カタログ 0 行 6) | 反映済み(contract L501 / L512)。stderr の warn を実行ログ WARN に訂正 | 対応 |
| G3 契約要求 7(final runner stderr 定型文 / polling ログ) | 反映済み(contract L462、ui L433)。登録 UC tier の文言を契約に追従 | 対応 |
| G3 契約要求 8 / F-038 deferred(DB 失敗文言統一) | `connection failed` / `query failed` に統一(本記録 #2) | 対応 |
| G3 契約要求 9 / F-041 deferred | 反映済み(本記録 #11) | 確認済み |
| G3 契約要求 10(rdra-feedback) | #11 として追記(本記録 #10) | 対応 |
| G3 F-039 deferred(依頼再作成 UC の artifact_uri 欠落 Given) | 依頼再作成 UC の tier-ops L119 / spec L214 に `missing=blue_artifact_uri` / `green_artifact_uri` の Given / Then が既にある | 確認済み |
| G4 契約要求 1(hint 追加 / exit 3 未起動) | 追加(本記録 #4) | 対応 |
| G4 契約要求 2(exit 3 の role 分岐 / readers 付記) | 反映済み(contract L660 / L1260) | 確認済み |
| G4 契約要求 3(abort-final 文言) | 修正(本記録 #5) | 対応 |
| G4 契約要求 4(RELAY_GATE_NOW readers に abort-*) | 反映済み | 確認済み |
| G4 F-043 deferred | 反映(本記録 #9) | 対応 |
| G4 F-029 deferred(所有範囲外) | G1 が対応済み | 確認済み |
| 契約側「UC 側に追従が必要」18 行 | 各 UC 担当の resolution で対応済みを grep で確認。未対応だった 3 点(validate-config 文言の JM / CD 追従、`management db unavailable` の確報 claim / 登録 / 中継 / 判定 UC、facade.sh オプション位置「JOB_ID より前のみ」を S UC 引数表 PARAM... 行に追記)を本記録で処理 | 対応(S/tier-facade.md) |
| 契約側 F-042(started-at.txt readers から background-rerun を削除) | G4 F-042 の決定(started-at.txt なし = 未起動)と矛盾するため、契約を UC 側に合わせて戻した(本記録 #4) | 対応(契約を修正) |
| 契約側 SR-001 / SR-002 | fb「後工程・スキルへの変更要求」に記録済み。本イベントでは変更しない | 見送り(スキル要求) |

## 最終 grep(E 配下、_review 除く)

| パターン | 残件 | 判断 |
|---|---|---|
| `management db unavailable` | 0 | — |
| `stderr.log の末尾に` | 2(復元起動 UC tier-facade L97 / L102) | runner 検証エラー(`error:`)を stderr.log に書く正当な記述。warn 追記ではないため残す |
| `既定 60 分` | 0 | — |
| `NOT_TARGET(正常終了` | 0 | — |
| `RELAY_GATE_HOME` | contract `environment_variables`(L72 / 既定値 3 箇所 / L227「引き継がない」注記)、ui 環境変数表、ux-design の配置図のみ | 環境変数そのものの定義。UC 側からは消去(完了通知 UC tier-facade の書式、slot runner 割当 UC の配置・共通ライブラリ記述を「配置ディレクトリ」表現に変更) |
| `missing option` | 1(ui L121「`missing option` は使わない」) | 禁止の宣言。残す |
| `error: --[a-z-]* required` | 0 | — |

## 検証

| 検証 | 結果 |
|---|---|
| `validateAllYaml.js E` | PASS(73 ファイル、error 0) |
| `validateRdbSchema.js rdb-schema.yaml` | PASS(7 tables) |
| `validateApiSummary.js` / `validateModelSummary.js`(全 UC dir 23 件、for ループ) | error 0 |
| `@asyncapi/cli validate asyncapi.yaml` | valid(0 errors, 0 warnings, 1 info = asyncapi-latest-version。既存) |
| `md-mermaid-lint`(変更 md 23 ファイル、1 ファイルずつ) | すべて PASS |

## 残った未解決事項

- なし(SR-001 / SR-002 はスキル側要求として fb に記録済み。RDRA 反映待ちは fb #4 / #7 / #11 の仮採用として Spec 側で確定)
