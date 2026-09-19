# As-built summary: feature flag を設定する(fd678b04)

- 対象 tier: tier-facade(`validate-config.sh --feature-flag`)
- current attempt: 3(spec event `20260917_100000_feedback_impl_feedback_fd678b04_cycle2` 反映後の再実行。3 サイクル目)
- 前サイクルまでの公開済み feedback 2 件は spec に反映済み。本 summary は反映後の実装(attempt-3)を対象にする
  - `20260917_014138_impl_feedback_fd678b04`(Scenario 分離、runner `--help` 問い合わせの契約一元化)→ spec event `20260917_050000_feedback_impl_feedback_fd678b04`
  - `20260917_081430_impl_feedback_fd678b04`(CR-fd678b04-001: 確報の制御キーの範囲 = `FINAL_` 接頭辞)→ spec event `20260917_100000_feedback_impl_feedback_fd678b04_cycle2`
- 入力: `issues/`(既存 2 件。新規なし)、`stages/attempt-3/S5_verify.tier-facade.findings.yaml`(blocker 0 / major 2 / minor 15)、`stages/attempt-3/S4_tier-impl.tier-facade.assumptions.yaml`(16 件)、`stages/S6_uc-bdd.done.yaml`(12/12、injections 0 / issues 0)、`stages/S7_atdd.done.yaml`(1/1、injections 0 / issues 0)、`review/review-notes.md`(前 2 サイクルの承認記録)
- `review/review-notes.md` は前 2 サイクルの承認対話の記録であり、本サイクルの前提 16 件に対する人の判断はまだ無い(S9 で行う)
- 本サイクルの仕様起因の未解決事項は 0 件。feedback draft は作らない
- この summary は dist-pipeline への入力ではない

## 1. 原因分類

| # | 事象 | 根拠 path | 分類 | 扱い |
|---|---|---|---|---|
| 1 | 前サイクルの CR-fd678b04-001(確報の制御キーの範囲が spec.md / tier-facade.md / 契約で不一致)| `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml#config_files.feature-flag.env.validation_rules`(範囲の正本 = `FINAL_` 接頭辞)、spec.md 分岐条件一覧「確報クロスチェック非起動」、tier-facade.md 組合せ検証 | 解消済み(仕様反映) | 3 ファイルが同じ表記(`FINAL_` で始まるキー。接頭辞判定。未知キー warn より先)。境界 Scenario「FINAL_ で始まる確報設定のキーは未知キーではなく拒否される」が spec.md と tier-facade.md に追加され、S4 tier BDD 9/9・S6 UC BDD 12/12 で通過。再要求しない |
| 2 | attempt-2(本サイクル)の S5 blocker F-005: 前提 A-007 の記述「9 キー以外は warn: unknown key」が契約の `FINAL_` 接頭辞優先と矛盾。実装の拒否動作は正しい | `stages/attempt-2/S5_verify.tier-facade.findings.yaml#F-005`、`stages/attempt-3/S4_tier-impl.tier-facade.done.yaml#findings_handling` | 実装起因(前提記録の記述が反映前の仕様のまま) | attempt-3 で A-007 の文面を契約と整合させ(FINAL_ 拒否 → 条件付き option required → 未知キー warn)、repository のコメントを同文にそろえ、等号なし `FINAL_` 行の TDD を repository / usecase に追加。ロジック変更なし。attempt-3 S5 で contradicts 0。要求に含めない |
| 3 | attempt-3 の major 2 件: F-005(A-010: 9 キー以外の値をプロセス変数に載せない)/ F-006(A-015: `--verbose` はキーとパスだけを出し値を出さない)。いずれも security の仕様未定義前提として回答必須 | `stages/attempt-3/S5_verify.tier-facade.findings.yaml#F-005,F-006`、`assumptions.yaml#A-010,A-015` | 前提(spec_absent) | S9 でユーザーが承認 / 却下。`spec_change` で却下された場合だけ refresh で要求化(前サイクルと同じ扱い) |
| 4 | attempt-3 の minor 15 件: spec_absent 14 件(F-001〜F-004、F-007〜F-016)と category_mismatch 1 件(F-017: A-015 を data_format → security) | `findings.yaml#assumption_verdicts` | 前提(spec_absent / 分類の差異) | S9 で判断。F-017 は次 attempt があれば AssumptionRecord の分類を Verifier 側(security)に寄せる。要求に含めない |
| 5 | attempt-2 の minor F-001(TDD 1 ケースに 3 Act)/ F-004・F-018(category_mismatch)/ F-015(A-023 は仕様の復唱) | `stages/attempt-3/S4_tier-impl.tier-facade.done.yaml#findings_handling.minor` | 実装起因 | attempt-3 で修正済み(ケース分割、A-006 / A-025 の再分類、A-023 を explicit として除外)。要求に含めない |
| 6 | 旧 issue の項目 1(運用モード切替 Scenario の When / Then が別 UC の責務) | `issues/20260917_074633_cross-uc-scenarios-resolution.md` | 解消済み(前々サイクルの CR-001 反映) | S6 のハーネス注入は撤去済み(injections 0)。再要求しない |
| 7 | 旧 issue の項目 2(正常系 Scenario の Given が runner スタブとジョブマップという別 UC 成果物を前提) | 同上「残存」行 | 環境起因(テストハーネス) | 一時ディレクトリのスタブ・CSV で解決済み。責務分担の記録のみで仕様変更不要 |
| 8 | A-020: 他 UC 所有の検証種別(--job-map 等)を終了コード 6 にする段階実装措置 | `assumptions.yaml#A-020` | 実装起因(段階実装) | 担当 UC の実装で自然に解消。要求に含めない |

仕様起因: 0 件 / 実装起因: 4 件(#2, #5, #8 と F-017)/ 環境起因: 1 件(#7)/ 前サイクルの feedback で解消: 2 件(#1, #6)。

## 2. 実装済み外部 IF の仕様照合

HTTP endpoint は無い。CLI コマンドと設定ファイル契約を対象にする。

| 対象 | 仕様どおり | 不足(仕様に無く実装で判断) | 矛盾 |
|---|---|---|---|
| `validate-config.sh --feature-flag <path> [--verbose]` の引数・排他 | 検証種別 4 つのうち 1 つ、0 個 / 2 個以上は終了コード 2 | 0 個・2 個以上・値欠落・位置引数の error 文言(A-017 / A-018 / A-019) | なし |
| stdout 15 キー固定順・`key=value` / `key: value` 切替・off slot の `-` | 27 モード組合せで一致(S5 attempt-3 spec_conformance) | なし(旧 A-023 は契約 `conventions.output_format.stdout` の復唱として除外) | なし |
| stderr の error / warn / hint 文言 | 契約 `config_files.feature-flag.env.error_messages` と同文 | 違反行の出力順(A-016)、`--verbose` の info 行形式(A-015) | なし |
| 終了コード | 0 / 2 / 6(準備失敗)は仕様どおり | 検証違反と準備失敗が同時のとき 6 を優先(A-026) | なし |
| feature-flag.env の読取(KEY=value、# コメント、空行、source 禁止) | 仕様どおり | 前後空白(A-005)、CRLF・最終改行なし(A-006)、= の無い行(A-007)、重複キー(A-008)、空キー行(A-021)、未知キー値の非取込(A-010) | なし |
| 確報の制御キーの拒否 | キー名が `FINAL_` で始まるキーを接頭辞判定で拒否(大文字小文字区別)。該当キーごとに `error: final crosscheck key is not allowed key=<KEY>`、終了コード 2。未知キー warn より先に判定し、同じキーに `warn: unknown key` を出さない。`FINAL_DB_CONN_REF` の誤配置も拒否。S5 attempt-3 で境界 7 ケース成功 | 等号なしの `FINAL_` 行も同じ規則で拒否する(A-007。等号なし行を空値へ写像する規則自体は未定義) | なし(前サイクルの矛盾は解消) |
| runner `--help` 問い合わせ(契約 `runner_help_probe`) | 待機上限 4 秒・blue → green 逐次・TERM → 0.2 秒後 KILL・版 ≠ 1 は未応答・版行の前後空白除去・準備失敗は終了コード 6 で stdout なし。両 runner 未応答は 9.029 秒で終了 0(NFR B.2.1.1 の 10 秒以内) | 生存確認の間隔 0.1 秒(A-024)、準備失敗の reason 語彙(A-025)、既出診断の残置と 6 優先(A-026)、起動失敗と exec 失敗の切り分け(A-027) | なし |
| 管理 DB | 接続しない(tables: []) | なし | なし |

## 3. 実装者が補った前提の一覧(AssumptionRecord)

Verifier 判定は attempt-3 の S5 findings `assumption_verdicts`(record sha256 `9a99cef7…`、verdicts sha256 `f4b777fb…`)。人の判断は本サイクルの S9 で行う(未実施)。前サイクル(cycle 2)の S9 では A-005〜A-027 の同文の前提がすべて承認されている(却下 0 件)が、spec event 後の再走のため本サイクルで改めて判断する。

| id | カテゴリ(実装者 / 検証者) | 前提(要約) | Verifier 判定 | 人の判断 | 本サイクルでの扱い |
|---|---|---|---|---|---|
| A-005 | input_validation / input_validation | env の KEY・value の前後空白を無視 | spec_absent(F-001 minor) | 未 | 要求に含めない(spec_change 却下時に refresh で追加) |
| A-006 | input_validation / input_validation | CRLF の CR 除去、最終行改行なしも読む | spec_absent(F-002 minor) | 未 | 同上 |
| A-007 | input_validation / input_validation | = の無い行は行全体をキー・値空として読み、キー名は = のある行と同じ規則(FINAL_ 拒否 → 条件付き option required → 未知キー warn)で評価 | spec_absent(F-003 minor。attempt-2 の contradicts は文面修正で解消) | 未 | 同上 |
| A-008 | input_validation / input_validation | 重複キーは後勝ち、warn なし | spec_absent(F-004 minor) | 未 | 同上 |
| A-010 | security / security | 9 キー以外の値をプロセス変数に載せない | spec_absent(F-005 major、要回答) | 未 | 同上 |
| A-015 | data_format / security | `--verbose` は key と path のみ、値を出さない | spec_absent(F-006 major、要回答)+ category_mismatch(F-017) | 未 | 同上 |
| A-016 | data_format / data_format | 違反行の出力順 | spec_absent(F-007 minor) | 未 | 同上 |
| A-017 | error_handling / error_handling | 検証種別 0 個の error / hint 文言 | spec_absent(F-008 minor) | 未 | 同上 |
| A-018 | error_handling / error_handling | 検証種別 2 個以上の error / hint 文言 | spec_absent(F-009 minor) | 未 | 同上 |
| A-019 | input_validation / input_validation | 値欠落・位置引数の判定と文言 | spec_absent(F-010 minor) | 未 | 同上 |
| A-020 | error_handling / error_handling | 未実装の検証種別は終了コード 6 | spec_absent(F-011 minor) | 未 | 含めない(段階実装措置) |
| A-021 | input_validation / input_validation | 空キー行は無視 | spec_absent(F-012 minor) | 未 | 含めない |
| A-024 | performance / performance | 待機上限の監視は 0.1 秒間隔 | spec_absent(F-013 minor) | 未 | 含めない |
| A-025 | error_handling / error_handling | 準備失敗の reason 値の語彙 | spec_absent(F-014 minor) | 未 | 含めない |
| A-026 | error_handling / error_handling | 検証違反と準備失敗の同時発生は 6 を優先 | spec_absent(F-015 minor) | 未 | 含めない |
| A-027 | error_handling / error_handling | 起動失敗は set -m / pid 取得失敗に限り、exec 失敗は未応答 | spec_absent(F-016 minor) | 未 | 含めない |

attempt-2(cycle 2)の 17 件からの差分: A-023(stdout の `key=value` / `key: value` 切替)は契約に明示された規則の復唱として explicit に除外(16 件)。旧 A-012 / A-013 / A-022(runner 問い合わせ)と cycle 2 で明記された `FINAL_` 接頭辞範囲も explicit として除外されている。consistent 0 / contradicts 0 / unlisted 0。

## 4. 方針資料との照合

- `tmp/RelayGateのしくみ.md`: 「`RAPID_CROSSCHECK_MODE` は facade が起動する速報クロスチェックの制御に限る。確報クロスチェックは runner をジョブスケジューラから直接起動するため facade の設定には含めない」。反映済みの `FINAL_` 接頭辞範囲はこの意図(確報の制御を feature flag に置かない)を維持する。方針資料にキー名・接頭辞の記述は無く、本サイクルの実装事実と矛盾する記述も無い
- `tmp/RelayGateの利用イメージ.md`: feature flag の確報関連キーに関する記述は無い。矛盾なし
