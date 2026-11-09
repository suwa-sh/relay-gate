# 変換推論根拠

## 入力

- arch フィードバックイベント: 20261010_202000_feedback_impl_feedback_dcd8234d(クロスチェック簡素化。E-006 を比較ツール起動コマンド 1 行化、E-007 / E-008 / E-018 削除、E-015 / E-016 / E-017 / E-019 / E-020 / E-027 追従、technology_context の設定契約列挙を更新)
- NFR フィードバックイベント: 20261010_201000_feedback_impl_feedback_dcd8234d
- feedback request: 20261010_104636_impl_feedback_dcd8234d の CR-dcd8234d-007 / 001 / 002 / 003

## どの arch/CR 項目からどう追従したか

- **設定ファイル集合**: arch data_architecture の E-007(クロスチェックジョブマップ)/ E-008(対象カタログ)削除と、CR-007(g) の「比較定義 CSV の行構造・対象カタログ・検証ルール群を廃止」から、config_store の entity_refs・説明・配置物(ansible)から `crosscheck-job-map.csv` / `target-catalog.csv` を除去した
- **比較ツール起動コマンドの置き場**: arch E-027(速報クロスチェック設定)の属性 `rapid_compare_command` 追加、context_map CM-007 / CM-008(速報・確報の起動コマンド)、E-006 の storage_mapping(速報クロスチェック設定・確報クロスチェック worker 設定)と、CR-007(b) の推奨「rapid-crosscheck.env と final-crosscheck.env にキーを 1 つずつ」から、物理設定ファイルを rapid-crosscheck.env(既存。起動コマンド 1 行を追加)と final-crosscheck.env(新規。確報 worker 設定)にマッピングした
- **比較結果テーブルの廃止**: arch E-018(比較結果)削除と CR-007(e) から、management_db の entity_refs・説明・worker_start_update の comparison_result 文言を除去した
- **ネットワークセグメント前提**: CR-007(a) の「runner と worker は別ネットワークセグメント、worker はファイルパスを読めない」から、確報 worker の connection_resolution を final-crosscheck.env ベースに変え、runner 側成果物パスを読まない前提を明記した。既存 artifact_store(Runner Result)の参照者には worker が元々含まれないため、成果物ストア設計自体は不変

## env キー名の扱い(spec 委譲)

- CR-007(b) は「設定の置き場(ファイル名・キー名)は仕様側で決める」とする。arch が名付けたのは rapid の属性 `rapid_compare_command` のみで、final の起動コマンドキー・DB 接続参照キーの正式名は未確定
- インフラ設計は物理ファイル(rapid-crosscheck.env / final-crosscheck.env)と役割(起動コマンド 1 行・DB 接続参照)の粒度で記述し、起動コマンドの内容検証(コマンド部分が絶対パスで実行可能・速報は {job_id} を含む)は validate-config.sh(spec)が所有すると明記した。exact キー名は確認推奨項目として返す

## MCL 再実行を行わない根拠

- translation(workload_type / availability_tier / latency / data_classification / traffic_pattern_type / consistency_model / cost_posture / target_clouds)は無変更
- 影響は設定ファイル集合・管理 DB の 1 テーブル廃止・確報 worker の接続解決に限られ、サーバ構成・ストレージ・トラフィック・復旧目標を変えない
- 前回(20260907_124000 / 20260921_094000)と同じく差分更新(skipped_targeted_update)で該当箇所のみ修正した
