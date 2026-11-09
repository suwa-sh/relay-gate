---
schema_version: distillery.feedback-request/v1
feedback_id: 20261103_housekeeping_followups
created_at: 2026-11-03T10:00:00+09:00
source: distillery-impl
uc_id: f3b8a1d0
---

# 利用者からの変更要求(ハウスキープの受け入れ基準・env のキーが空の行・実行ログの整理)

## CR-f3b8a1d0-001: 管理 DB に接続しないハウスキープの振る舞いを、要求の受け入れ基準で判定できるようにする

- severity: spec-gap
- related_ids: [REQ-014, SPEC-014-01, SPEC-014-04, SPEC-014-07]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/条件.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- 前回の変更(20261101_mail_removal_housekeeping)で、仕様(CLI 契約の housekeep.sh)は、RAPID_CROSSCHECK_MODE=off で HOUSEKEEP_DB_CONN_REF が無い・空のときの振る舞いを次のように定めた。
  - 管理 DB に接続しない。起動のたびに `warn: management db is not configured; database rows are not deleted (HOUSEKEEP_DB_CONN_REF not set)` を 1 行出し、確報比較依頼と管理 DB の行を削除しない。
  - execution-spec.json の rapid_crosscheck_mode が off でない実行(off 以外の期間に作られ、管理 DB に終わっていない構成要素があり得る実行)は判定できないものとして単位ごと残し、`warn: run kept rapid crosscheck mode run_id=... mode=...` を出す。
- 要求(USDM の REQ-014 配下)には、この 2 つの振る舞いを書いた仕様文も受け入れ基準も無い。前回の仕様の段階が、この隙間を確認推奨として報告した。
- 利用者は、この隙間を次の変更へ持ち越さず、今回の変更に含めると決めた(2026-11-03)。

### 現在の仕様と問題

- 仕様にだけある振る舞いは、要求の受け入れ基準から ATDD のテストを作るときに抜け落ちる。管理 DB に接続しない設定で、終わっていないかもしれない実行や確報比較依頼を消してしまう実装を、受け入れテストで止められない。

### 変更してほしいこと

- REQ-014 配下に、管理 DB に接続しないとき(RAPID_CROSSCHECK_MODE=off で管理 DB の接続参照名が無い・空)の振る舞いを仕様文と受け入れ基準で加える。どの SPEC に置くか、新しい SPEC にするかは要求の段階で決める。
  - 管理 DB に接続せず、確報比較依頼と管理 DB の行を消さない。起動のたびに標準エラーへ warn を 1 行出す。
  - off 以外の期間に作られた実行(execution-spec.json の速報クロスチェックのモードが off でない実行)は、日数にかかわらず単位ごと残し、標準エラーへ warn を出す。
  - off の期間に作られた成果物だけの実行は、今の規則どおり成果物だけで判定して消す・残す。
- 仕様(CLI 契約)の振る舞いは変えない。要求に合わせて表現を揃える必要があれば、仕様の段階で直す。

### 完了条件

- 要求の受け入れ基準で、次を判定できる。
  - 管理 DB に接続しない設定で、保持日数を過ぎた終端の確報比較依頼が残り、warn が出る
  - 管理 DB に接続しない設定で、off 以外の期間に作られた保持日数超過の実行が残り、warn が出る
  - 管理 DB に接続しない設定で、off の期間に作られた保持日数超過の終了済みの実行は消える
- 要求の受け入れ基準と CLI 契約の housekeep.sh の記述が矛盾しない。

## CR-f3b8a1d0-002: env 形式の設定で、キーが空の行を全設定ファイルで不正な行として拒否する

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/todo.md]

### 観測した事実

- CLI 契約の env 形式の入力規則(config_input_rules.env_files)は、キーと値の取り出し方を順序つき規則で定めている(最初の `=` で分ける → キーの前後の空白を除く → 値の前後の空白を除く → 引用符を外す)。キーの前後の空白を除いた結果キーが空になる行(例: ` =abc`、`=abc`)の扱いは書いていない。
- 同じ規則は、`=` を含まない非空・非コメント行(空白だけの行を含む)を `error: invalid line line=N path: ...`(終了コード 2)とする。
- 実装の 2 か所は、キーが空の行の扱いが違う。
  - 速報クロスチェック設定の読み込み(facade/src/repository/rapid_crosscheck_env.sh)は、不正な行(invalid line)として扱う。
  - feature flag 設定の読み込み(facade/src/repository/feature_flag_config.sh)は、何も出さずに読み飛ばす。
- feature flag 設定の読み込みは、ほかにも契約と違う扱いをしている。
  - `=` を含まない行を、キーだけで値が空の行として扱う(契約は invalid line)。
  - 空白だけの行を、行全体の前後の空白を除いたうえで空行として読み飛ばす(契約は invalid line)。
- 前回の仕様の段階が、キーが空の行の扱いを未決として docs/todo.md の DIST-031 に記録した。
- 利用者は、キーが空の行を「不正な行として拒否する」に揃え、今回の変更に含めると決めた(2026-11-03)。

### 現在の仕様と問題

- 同じ形式の行が、設定ファイルによってエラーになったり無視されたりする。feature flag 設定では、書き損じた行が何も知らされずに無視され、意図しない設定で動きうる。

### 変更してほしいこと

- config_input_rules.env_files に、キーの前後の空白を除いた結果キーが空になる行を `error: invalid line line=N path: ...`(終了コード 2)とする規則を、取り出し方の順序つき規則と同じ節に書く。例を添える(` =abc` / `=abc` / ` = ` はいずれも invalid line)。
- この規則は env 形式の全設定ファイル(feature-flag.env / rapid-crosscheck.env / hang-detector.env / final-crosscheck.env / housekeep.env)に共通で適用する。shared_rules.compare_command_argv.split の再掲にも反映する。
- `=` を含まない行と空白だけの行を invalid line とする今の契約は変えない。feature flag 設定の読み込みがこの契約と違うことを、実装との差分として仕様の判断記録に残す(実装を契約に合わせる対象として扱う)。
- docs/todo.md の DIST-031 を、この変更で解決したものとして閉じる。

### 完了条件

- env 形式の入力規則が、キーが空の行を invalid line として扱うことを例つきで書いている。
- キーが空の行・`=` の無い行・空白だけの行の結果が、どの env 設定ファイルでも同じ 1 つに決まる。
- feature flag 設定の読み込みと契約の差分が、仕様の判断記録に残っている。
- DIST-031 が閉じている。

## CR-f3b8a1d0-003: 実行ログの整理は relay-gate が行わず、設置環境の logrotate に任せると正本に書く

- severity: spec-gap
- related_ids: [REQ-014]
- related_files: [docs/arch/latest/arch-design.yaml, docs/infra/latest/infra-event.yaml, docs/infra/latest/docs/mcl/product/output/product-mapping-onprem.yaml, docs/infra/latest/docs/mcl/product/output/product-observability.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md]

### 観測した事実

- 実行ログは、スクリプト 1 本につき 1 ファイル(`$RELAY_GATE_LOG_DIR/{script}.log`)に全実行分を追記する。
- インフラ設計は、OS 標準の logrotate を「日次ローテーション・90 世代保持・圧縮」で配置する(relay-gate-runtime ロールの /etc/logrotate.d/relay-gate。product-mapping-onprem.yaml・product-observability.yaml)。実行ログは約 3 か月で自動的に消える。
- 一方で、次の正本は実行ログの整理を「手動」と書いている。
  - アーキテクチャ設計の CTR-006: 「実行ログはファイル領域での手動ローテーション(3 ヶ月保管)とする。運用手順書に…実行ログのローテーションの手動手順…を明記し」。arch-decision-023 も「実行ログの手動ローテーション(3 ヶ月)は残す」と書く。
  - CLI 契約の実行ログの出力先: 「ローテーションは手動」。housekeep.sh の記述: 「実行ログ自体はハウスキープの対象外(手動ローテーション)」。
  - 仕様の出力規約(ui-design.md)の実行ログの出力先: 「ローテーションは手動。arch CTR-006」。
- 意図は「relay-gate 自身はログを整理せず、設置環境の logrotate に任せる」である。利用者は、実行ログをハウスキープの対象にせず logrotate に任せることを確認した(2026-11-03)。ログの保管期間 3 か月(NFR C.6.1.1)は変えない。

### 現在の仕様と問題

- 「手動」の記述を読んだ実装者や運用者が、logrotate の設定と別に手作業の整理手順を作りうる。正本どうしで実行ログの整理方法が食い違っている。

### 変更してほしいこと

- アーキテクチャ設計の CTR-006 の実行ログの記述を、「relay-gate は実行ログを整理しない。設置環境の OS 標準のログ整理(logrotate)で 3 か月保管とする」趣旨に改める。運用手順書に書く手動手順の列挙から、実行ログのローテーションを外す。
- arch-decision-023 は過去の判断の記録なので書き換えない。必要なら新しい判断記録で改めたことを残す。
- インフラ設計は、logrotate の配置をそのまま残す。手動の整理を前提にした記述があれば揃える。
- CLI 契約と ui-design.md の「ローテーションは手動」「手動ローテーション」を、「relay-gate は整理しない(設置環境の logrotate に任せる)」に改める。
- 実行ログをハウスキープの対象にしない規則と、保管期間 3 か月は変えない。

### 完了条件

- アーキテクチャ設計・インフラ設計・仕様のどこにも、実行ログの整理を手動とする記述が無い(過去の判断記録と変更履歴の説明を除く)。
- 実行ログの整理を logrotate に任せることが、アーキテクチャ設計と仕様の両方に書かれている。
- 実行ログをハウスキープの対象にしない規則と、保管期間 3 か月は変わっていない。
