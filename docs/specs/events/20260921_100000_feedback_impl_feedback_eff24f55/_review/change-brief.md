# 変更の正本(change-brief): event 20260921_100000_feedback_impl_feedback_eff24f55

- feedback request: 2026-09-19 の実装フィードバック(CR-eff24f55-001〜005。direct = 001#1 / 002#1 / 003#1 / 004#2、causal = 001#1 / 002#1 / 003#1 / 004#1 / 004#2 / 005#1。実装フェーズ UC eff24f55「slot ごとのジョブマップを定義する」からの blocker 1 / spec-gap 3 / improvement 1。ID / SHA は spec-event.yaml の feedback_request と source.txt)
- 利用者決定(2026-09-22。第 1 段階の質問 4 問への回答): 問 1 A(形式から外れた入力は拒否。例外は最終行の改行なしとデータ行 0 件の受理)/ 問 2 A(実装済みの単一スナップショット・内部障害 6・制御文字の可視表記をそのまま確定)/ 問 3 A(原因ごとの専用文言)/ 問 4 A(work_dir / script の絶対パス検査をやめ、空でなければ受理。根拠「ジョブマップでの定義なら Windows / Linux 両対応のフルパス / 相対パス指定を受け取れる必要がある」)。一覧表への異議なし
- trigger_event: rdra:20260921_084000(no-change), arch:20260921_092000(no-change)。related: usdm:20260921_084000(SPEC-008-05 の受け入れ基準分割)、nfr:20260921_090000(B.1.1.2 / B.2.1.1 の CSV 設定ファイル共通前提: 1 ファイル最大 5,000 行・最悪条件でも 10 秒以内・行数比例)、infra:20260921_094000(no-change。shell: bash 5)
- 性質: 設定ファイル共通の守備範囲・出力規約・実行前提の追加と、work_dir / script のパス形式検査の撤回。UC ツリー・ティア構成・状態遷移・RDRA 要素・値集合は不変。usdm[] は UC-31 の SPEC-004-04 に Scenario 3 件追加(211 → 214)

## D1: 入力の守備範囲の正本を CLI 契約に置く(CR-eff24f55-001)

- `_cross-cutting/api/cli-command-contract.yaml` にトップレベル `config_input_rules` を追加(scope / principle / rules[13 論点] / snapshot(guarantee・validate_config・runtime_readers・out_of_scope)/ internal_failure / env_files)。config_files の 7 ファイルの format から参照。<slot>-job-map.csv の csv_rules に「形式の制約で行単位の外部コマンド利用は禁じない」「制御文字は値として受理し出力時に可視表記」を追記。edit_rule に snapshot との両立を追記。runner 契約 notes に守備範囲の適用を追記
- 現行実装との差(実装の修正が必要): コメント行の NUL の拒否 / BOM の専用文言 / CR の拒否(現状は末尾列で `v1<CR>` を受理) / ヘッダー列名の重複の拒否(現状は黙って受理) / 複製失敗の専用文言 / feature flag の読み込みに CR の拒否とバイト点検を追加
- 判断記録: decisions/spec-decision-011.yaml

## D2: 原因ごとの専用 error 行と終了コード 6 の条件(CR-eff24f55-002)

- 契約 commands[validate-config.sh].stderr に「入力の守備範囲」「検証器の内部障害」の 2 項目を追加(nul byte is not allowed / encoding is not utf-8 / byte order mark is not allowed / carriage return is not allowed + hint: use LF line endings / duplicate column / internal command failed commands=<name,...> / config snapshot failed + hint: check TMPDIR is writable)。文字コードの検査はコメント行を含む
- exit_codes: 0 にデータ行 0 件、2 に守備範囲の違反・列名の重複、6 に内部障害(stdout なし)を追加。idempotency に一時ファイルの扱い
- ui-design.md「メッセージ表現規約」に「設定ファイルの入力の守備範囲の定型文」を追加
- 判断記録: decisions/spec-decision-012.yaml(D3 と合同)

## D3: 制御文字の可視表記(CR-eff24f55-003)

- `_cross-cutting/ux-ui/ui-design.md`「出力フォーマット」に「制御文字の表記」(範囲 / 表記 / バックスラッシュは置き換えない / 不正バイトはそのまま / key=value の選択は元の値 / --verbose の JSON 表記は例外 / 全コマンドへ適用)を追加。TSV の「半角空白へ置換」を可視表記へ改める。パス・URI の項に補足
- 契約 conventions.output_format に control_chars(要約と参照)を追加。tsv / color を追従。validate-config.sh の stderr に「任意入力の表示」を追加
- UC「feature flag を設定する」tier-facade.md の出力契約 stderr に可視表記の参照と例を追加。ティア完了条件に Scenario「値に含まれる制御文字を可視表記で出力する」「CRLF 改行の設定を拒否する」を追加。spec.md 統合契約に出力規約への参照を追加
- 判断記録: decisions/spec-decision-012.yaml

## D4: work_dir / script のパス形式検査の撤回(CR-eff24f55-001 の制約「方針資料の CSV 例が検証 OK」)

- 第 1 段階で現行の検証コマンドに方針資料の 2 例(`G:\scripts` / `./beam-batches`)を通し、`is not absolute` で拒否されることを実測。規則は USDM / RDRA / 方針資料に無い spec 側の追加
- 契約 config_files[<slot>-job-map.csv].columns の work_dir / script を「非空のみ。形式は検査しない(Linux / Windows / 相対)。理由: 利用者決定 2026-09-22」に変更。stderr の `is not absolute` 2 種を `is empty` に置換。exit_codes 2 の条件から絶対パス違反(ジョブマップ)を除去(feature flag の runner パスは維持)
- UC「slot ごとのジョブマップを定義する」tier-facade.md 列表・spec.md データフロー表・_api-summary.yaml、UC「ジョブマップで JOB_ID から実行先を解決する」tier-facade.md(終了コード 2 の条件・エラーメッセージ表・バリデーション (9))を追従。ui-design.md の例も差し替え
- 方針資料の 2 例をサンプルと Scenario(E2E 2 件 + ティア 2 件)で固定し SPEC-004-04 に登録
- 判断記録: decisions/spec-decision-013.yaml

## D5: 実装の前提(bash 5.0・性能の参照・外部コマンド)(CR-eff24f55-004#2、004#1 の追従)

- 契約 conventions に `runtime_prerequisites`(bash_minimum_version 5.0 / bash_note / external_commands)を追加。UC「slot ごとのジョブマップを定義する」tier-facade.md に「実装の前提」節(bash 5.0 / NFR B.1.1.2・B.2.1.1 の参照 / 外部コマンドの許容)。UC「ジョブマップで JOB_ID から実行先を解決する」tier-facade.md / spec.md に候補行の絞り込みと bash 5.0 の参照
- 「セルは bash 単独で解析する」は形式の制約であり、行単位の外部コマンド利用を禁じる記述は現行 spec に無いことを確認(誤読防止の 1 文を追加)

## D6: 守備範囲の適用先 UC と SPEC-008-05 分割への追従(CR-eff24f55-005#1 の追従)

- 参照行を追加した tier md(9 ファイル。UC ロジック節の先頭に 1 項目): slot 実行モードを選択して runner を起動する / 速報クロスチェック runner へ完了通知を送信する(facade・rapid の 2 tier)/ 両系成功時に速報比較依頼を作成する / 速報比較依頼を claim する / 確報比較依頼を登録して終端状態まで待機する / 確報比較依頼を claim する / background 実行の経過時間と終了状態を判定する / ハング疑い・実行エラー・比較異常を通知する。設定契約節を持つ tier(クロスチェックのジョブマップと比較定義を定義する の rapid / final、feature flag を設定する、ジョブマップで JOB_ID から実行先を解決する)は設定契約節に追記。合計 12 UC
- UC「hang_detect_limit_minutes をジョブごとに調整する」spec.md「関連 USDM」表: 分割後の基準 1 / 2 / 3 と Scenario の対応、基準 3「[自動判定の対象外: 運用文書の記載]」は BDD を持たないことを注記。usdm-acceptance-matrix.md の SPEC-008-05 行・SPEC-004-04 行・前提節・受け入れ条件総数(122 → 123)を追従。traceability-matrix.md の生成元注記を更新(分母・分子・網羅率 380 / 380 = 100% は不変)

## 検証・レビュー

- 機械検証: validateAllYaml / validateSpecEvent / validateApiSummary・validateModelSummary(変更 UC)/ validateSpecProse(変更 UC)/ validateRdbSchema / md-mermaid-lint / generateSpecEventMd。結果は本ファイル末尾と spec-event.yaml の review に記録
- 第三者レビュー: 観点 5(CR-001〜004 の完了条件 / 方針資料の CSV 例が検証 OK / 契約・UC・出力規約の三者一致(二重定義・矛盾なし)/ Scenario 名の一致(spec.md ↔ spec-event.yaml usdm[])/ 実装・テスト可能性(推測なしに書けるか))、閾値 medium、3 ラウンド。round 1 = オーケストレータの自己反証(fresh context のレビュアーが期限内に返さなかったため): major 2 / minor 1(runner 契約の終了コード条件、差し替え Scenario のタイミング制御と一時ファイル名接頭辞、CR の hint の回数)→ fixed。round 2 = fresh context のサブエージェント: major 3 / minor 3(補助コマンド失敗 Scenario の実装依存、一時ファイル出現と複製完了の窓(.part → rename)、JSON 配列解析の bash 単独と sed・awk の矛盾、fixed_params 文言、mktemp 失敗の分類、feature flag 終了コード 6)→ fixed。round 3 = 別の fresh context サブエージェント(検証パス): R-004〜R-009 全件 fixed、新規 medium 1(mktemp が作るのは作業名)→ fixed。収束(blocker 0 / 未解決 major 0)。記録: _review/round-{1,2,3}.yaml
- 機械検証の結果(最終): validateAllYaml 84 YAML OK / validateSpecEvent PASS / validateApiSummary・validateModelSummary(変更 5 UC)PASS / validateSpecProse(変更 5 UC)findings 0 / validateRdbSchema PASS / md-mermaid-lint OK / generateSpecEventMd・generateDatastoreMd 再生成。docs/todo.md への新規登録なし(全決定が利用者確定)
