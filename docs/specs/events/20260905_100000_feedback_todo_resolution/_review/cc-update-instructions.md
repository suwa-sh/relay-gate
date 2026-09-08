# Cross-cutting 差分更新 subagent の固定指示(feedback 20260905_todo_resolution)

あなたは全体横断 Spec(`_cross-cutting/`)の差分更新担当です。担当ファイルだけを、変更の正本に従って Edit します。
ゼロから再生成しない。

## 読み込むファイル(読む順)

1. `docs/specs/events/20260905_100000_feedback_todo_resolution/_review/change-brief.md`(**変更の正本**。D1〜D12 / U1〜U4。必ず全文読む)
2. `docs/rdra/events/20260905_083000_feedback_todo_resolution/_changes.md` と `docs/arch/events/20260905_091000_feedback_todo_resolution/_changes.md`
3. 担当ファイル(変数ブロック)
4. 必要な範囲だけ: `docs/rdra/latest/*.tsv`(該当行を grep)、`docs/usdm/latest/requirements.yaml`(該当 SPEC を grep)、
   `docs/specs/events/20260905_100000_feedback_todo_resolution/_inputs-digest.md`(該当セクションのみ)

読まないもの: `docs/specs/latest/`、arch-design.yaml / nfr-grade.yaml の丸読み、UC ディレクトリ(UC 側は別 subagent が同時更新中)。

## 担当別の更新内容

### 担当 contract: `_cross-cutting/api/cli-command-contract.yaml`(契約の正本。UC 側はこれに従う)

- `config_files[feature-flag.env]`: 9 キー(D1 の表)。`CONFIG_VERSION` 削除。`RAPID_CROSSCHECK_MODE` は foreground / background / off。validation_rules を D1 のとおり。未知キー warn の列挙から元資料キーを除去
- `config_files[<role>-job-map.csv]` / `crosscheck-job-map.csv` / `target-catalog.csv`: CSV 形式・クォート解析規則(D2)・列(U2: ヘッダー名で対応付け、必須 5 列、host / user 任意で両方揃える、credential_ref / map_version 末尾任意、impl_version なし・未知列 warn)。ファイル名は `blue-job-map.csv` / `green-job-map.csv`
- `config_files[hang-detector.env]`: owner と `ALERT_SUBJECT_PREFIX`(D10)
- `shared_rules.run_id` / `final_crosscheck_id`: D3(ローカル TZ、Z 無し、confidence low 注記を外す、RELAY_GATE_NOW との関係 1 行)
- `shared_rules.exitcode_to_status.slot_execution`: D4 の状態導出規則。成果物レイアウトに `aborted.txt` を追加(writer = abort-blue / abort-green)
- コマンド: `facade.sh`(feature flag ロード行・runner へ渡す環境変数 U1)、slot runner IF(完了通知先 = RAPID_CROSSCHECK_RUNNER、impl_version 転記、fixed_params、host / user null、リラン由来 run の COMPLETED D9)、`validate-config.sh`(stdout キー順 U4、エラー文言 U4)、`abort-blue.sh` / `abort-green.sh`(D4 / U3。「off では管理 DB が無い旨を出して終了」を除去)、`background-rerun.sh`(ファイル正本での事前検証、COMPLETED 到達)、`hang-detector.sh`(aborted.txt の終端、hang_judgement 6 値、monitor_status 6 値と遷移、ALERT_SUBJECT_PREFIX)、`rapid-crosscheck-worker.sh`(「比較結果の登録条件」D11、リラン由来 run の COMPLETED D9)
- 「完了通知失敗の扱い」(D5)条件名で統一、「(spec 追加)」注記を外す。「外部システム: 管理 DB(RDB)」→ 内部データストア表記(D6)
- `shared_rules.state_codes`: monitor_status 6 値 / hang_judgement 6 値 / parallel_run 遷移(D8 / D9)
- 仮採用注記の除去は change-brief.md「解消済み」一覧の範囲だけ。lease / poll / worker_id_default の low は残す
- YAML 構文を壊さない(編集後に `node -e "require('js-yaml')"` は使えない前提。インデントとクォートを慎重に)

### 担当 datastore: `_cross-cutting/datastore/rdb-schema.yaml` と `_cross-cutting/api/asyncapi.yaml`

- rdb-schema.yaml: 列挙値(status / monitor_status 6 値 / hang_judgement / mode 3 値 / rapid_crosscheck_mode 3 値)、列の説明(run_id 形式 D3、impl_version の出所 = BLUE_IMPL / GREEN_IMPL、map_version nullable、fixed_params、host / user nullable、aborted.txt との二重マッピング D4)、parallel_runs の遷移説明(D9)、「外部システム: 管理 DB」表記の除去(D6)、「仮採用 / DIST / rdra-feedback / confidence low」注記の除去(解消済み一覧の範囲)。
  **注意**: 機械置換で列名 `exec_user` → `user` に変わっている。RDB 列名として `user` は SQL 予約語なので、RDB 列は `exec_user` に戻し、description に「CSV 列 `user` に対応」と書く(CSV 列名と RDB 列名は別物)。`script_path` → `script`、`fixed_args_json` → `fixed_params` の RDB 列は置換後の名前でよいが、テーブル・列名は snake_case、全列 description 必須を維持
- asyncapi.yaml: 完了通知(RAPID_CROSSCHECK_RUNNER)、RAPID_CROSSCHECK_MODE の値、run_id 形式、monitor_status / hang_judgement 6 値、通知メール件名(ALERT_SUBJECT_PREFIX)、管理 DB の内部データストア表記、`.csv` 名、「仮採用」注記の除去。payload の title / enum を壊さない
- `datastore-schema.md` は編集しない(スクリプトで再生成する)

### 担当 uxui: `_cross-cutting/ux-ui/ui-design.md` / `ux-design.md` / `data-visualization.md` と `_inference.md`、`decisions/spec-decision-00[1-4].yaml`

- ui-design.md(出力規約): feature flag 検証 / ジョブマップ検証のエラー・警告文言を U4 に統一、validate-config.sh の stdout キー順 U4、通知メール件名の `ALERT_SUBJECT_PREFIX`(D10)、abort-* の off 時の出力(D4 / U3)、run_id 形式(D3)、`.csv`、外部システム表記(D6)
- ux-design.md: 操作フロー(設定ファイル 9 キー / CSV / aborted.txt / off でも中止・リラン可 / 完了通知失敗時の復旧手順 D5)、外部システム 6 種(D6)
- data-visualization.md: 集計・表形式に列名・値の変更があれば追従(monitor_status 6 値、`.csv`)
- _inference.md: 確認推奨項目のうち解消済み(#9 run_id 形式、#10 hang-detector.env、#11 監視状態、管理 DB 内外、DIST-*)に「2026-09-05 利用者決定で解消(feedback 20260905_todo_resolution)」を追記(削除はしない)。UC-ティアマッピングは変えない
- decisions/spec-decision-001〜004.yaml: 内容に `CONFIG_VERSION` / TSV / `on` / UTC run_id / 外部システム 管理 DB が残っていれば追従(status は approved のまま。新規 decision は書かない。必要なら完了報告で提案)
- 固有システム名・製品名を書かない。Bash にヒアドキュメントを渡さない。編集は Edit / Write ツールで行う

## 完了報告

「CC 更新 完了({担当}): 変更 {n} ファイル / 要確認 {q} 件」の 1 行 + 変更ファイルのパス一覧(1 行 1 パス)。
要確認項目がある場合だけ、その下に箇条書き(1 件 1〜2 行)。本文の再掲・所感は書かない。

## 変数ブロック(オーケストレータが埋める)

```text
担当: contract | datastore | uxui
担当ファイル: (一覧)
```
