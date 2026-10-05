# 変更の正本(change-brief): event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2

- feedback request: 2026-09-22 の実装フィードバック cycle 2(CR-eff24f55-006 / CR-eff24f55-007。direct = causal = CR-eff24f55-006#1, CR-eff24f55-007#1。実装フェーズ UC eff24f55「slot ごとのジョブマップを定義する」からの spec-gap 2 件。ID / SHA は spec-event.yaml の feedback_request と source.txt)
- 利用者決定(事前指定。confidence にかかわらず採用):
  - CR-007: 案 A(2026-09-22 のレビューで承認)。正規表現に合わない credential_ref は理由を問わず同じ warn で受理。拒否しない理由を契約に書く。値は診断行に一切出さない
  - CR-006: 要求本文の推奨「初出行を含める(出現順に全部)」を ⭐推奨として採用
- trigger_event: rdra:20260921_084000_feedback_impl_feedback_eff24f55, arch:20260921_092000_feedback_impl_feedback_eff24f55(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- 性質: 仕様内の矛盾の解消(CR-006)と未指定の境界の確定(CR-007)。UC ツリー・ティア構成・状態遷移・RDRA 要素は不変。usdm[] は UC「slot ごとのジョブマップを定義する」の SPEC-004-03 に Scenario 1 件追加(Scenario 参照 214 → 215 件)
- 処理方式: 影響 UC が少数(本文を変えた UC 4 件)のため、UC 単位の並列 subagent は起動せずオーケストレータが順次処理した

## D1: 重複報告の lines= の規則を 1 つにする(CR-eff24f55-006)

- 規則: そのキーが現れた全行の物理行番号を、初出行を含めて出現順(昇順)にカンマ区切り・空白なしで並べる。重複したキー 1 つにつき error 行は 1 行。例 `lines=2,5` / `lines=2,3,4`
- `_cross-cutting/api/cli-command-contract.yaml`: commands[validate-config.sh].stderr の重複キーの項(旧「2 回目以降の行番号をカンマ区切りで全部」を置き換え。検証種別を問わず共通と明記、対象カタログの重複も同じ規則)、config_files[<slot>-job-map.csv].columns.job_id の説明
- UC「slot ごとのジョブマップを定義する」: tier-facade.md 列検証表の job_id 行、spec.md 分岐条件一覧「ジョブマップ解決条件」(旧「行内で一意」の誤記も「ファイル内で一意」に)、処理フロー図の重複検査。BDD は `lines=2,5` を維持し「(初出行 2 を含む)」と error 行が 1 行だけであることを追加。ティア完了条件に 3 行重複 `lines=2,3,4` の Scenario を追加。`_api-summary.yaml` の stderr 説明
- UC「クロスチェックのジョブマップと比較定義を定義する」: tier-rapid-crosscheck.md 検証ルール #4、tier-final-crosscheck.md 検証ルール #5 に規則を注記。spec.md の BDD `lines=6` → `lines=5,6`(宣言 3 行 + ヘッダーの後の 5 行目と 6 行目)、tier-final-crosscheck.md の BDD `lines=3` → `lines=2,3`(Given に行番号を明示)
- UC「ジョブマップで JOB_ID から実行先を解決する」: tier-facade.md の実行ログ `WARN duplicate job_id in job map ... lines=` に同じ規則を注記(同じキー名の表記を 1 つの意味にそろえる)

## D2: credential_ref の形式の扱いと値の非出力(CR-eff24f55-007)

- `_cross-cutting/api/cli-command-contract.yaml`:
  - config_files[<slot>-job-map.csv].columns.credential_ref に format / on_format_violation / output_rule を追加(正規表現に合わない値と `BEGIN` を含む値は同じ warn で受理、拒否しない理由 = 参照名の形式は認証情報ストアの運用に依存、値は診断行に出さない)
  - conventions.credentials に「credential_ref の値は診断行に一切出さない。対象は validate-config.sh の stdout と stderr(validate-config.sh は実行ログを持たない)と、ジョブマップを読む slot runner の stderr と実行ログ。value= を付けない」を追加
  - commands[validate-config.sh].stderr の warn 一覧の「credential_ref のパス形式」を形式の扱いの全体に置き換え
- UC「slot ごとのジョブマップを定義する」:
  - spec.md 分岐条件一覧「認証情報の非保存」: 「仮採用」を削除し確定内容へ置換(正規表現を tier と同じ `*`(空も可)に修正)。処理フロー図の「仮採用」も削除
  - tier-facade.md: 列検証表の credential_ref 行を表「credential_ref の形式の扱い」参照に変更し、値の種類ごとの表(空 / 正規 / `/` / `BEGIN` / その他の形式違反)と「warn は 1 行」「値を出さない」を追加。ビジネスルールに追記
  - BDD: E2E に Scenario「参照名の形式に合わない credential_ref は同じ警告で受理され値は出力されない」(値 `ssh key green`、--verbose、warn 1 行・error なし・値が出ない)を追加し SPEC-004-03 に登録。既存「認証情報らしい値は警告される」に値が出ない Then を追加。ティア完了条件に同旨の Scenario と `BEGIN_KEY` の Scenario を追加
  - `_api-summary.yaml`: stderr 説明と credential_ref 列の説明
- 範囲の注記: 「仮採用」注記の解消の対象は、UC「slot ごとのジョブマップを定義する」の credential_ref の形式の扱いだけ。UC「実装スクリプトを実行して Runner Result を出力する」の「credential_ref を SSH 設定の Host 別名や鍵の参照名として runner 実体が解釈する(仮採用)」は実行時の解釈の話で本 CR の範囲外(契約の拒否しない理由はこの解釈に依存しない書き方にした)
- 受理した値の保存: warn して受理した値も execution-spec.json へそのまま転記される(転記規則は不変)ことを契約・tier・判断記録に明記(第三者レビュー R-001)。転記側 UC「execution-spec.json を確定保存する」の分岐条件「認証情報の非保存」を『credential_ref 列の値を加工せずに転記する(形式の検査・除去はしない)。relay-gate は鍵ファイルの中身などを自ら読んで書かない』に改め、tier-facade.md の SlotSpec 表・ビジネスルールを追従、ティア完了条件に Scenario「save_slot_spec_once は形式に合わない credential_ref も加工せずに転記する」を追加(第三者レビュー round 2 の R-001)
- `spec-event.yaml` use_cases[slot ごとのジョブマップを定義する].usdm SPEC-004-03 に新 Scenario。usdm-acceptance-matrix.md(前提節の注記と UC-31 の対応 Scenario 列)、traceability-matrix.md(生成元の注記)を追従

## D3: 横断文書・記録

- decisions/spec-decision-014.yaml(lines= の規則)/ spec-decision-015.yaml(credential_ref の形式の扱い)を追加
- _inference.md に差分更新履歴を追記。_inputs-digest.md は event_id ヘッダーのみ更新(arch / nfr latest は前イベントから変更なし)。README.md は最新イベントと本文を変えた UC の最終更新イベントを更新。docs/todo.md: 新規の仮採用は無い(登録なし)
- 方針資料との照合: 方針資料は「1 行 1 job_id」「認証情報そのものは保存せず、認証情報の参照名だけを保存する」を定めるだけで、重複の報告形式・参照名の形式の扱いの記載は無い。本イベントの決定はどちらとも矛盾しない
