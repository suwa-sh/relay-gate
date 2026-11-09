---
schema_version: distillery.feedback-request/v1
feedback_id: 20261103_housekeeping_db_required
created_at: 2026-11-03T11:00:00+09:00
source: distillery-impl
uc_id: 9d2e6c41
---

# 利用者からの変更要求(ハウスキープの管理 DB 接続の要否・字下げしたコメント行)

## CR-9d2e6c41-001: 管理 DB を使う機能が 1 つでもあれば、ハウスキープの管理 DB 接続参照名を必須にする

- severity: spec-gap
- related_ids: [REQ-014, SPEC-014-07, SPEC-014-08]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/情報.tsv, docs/rdra/latest/条件.tsv, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- 今の要求(SPEC-014-08)と仕様(CLI 契約の housekeep.sh)は、ハウスキープ設定の管理 DB 接続参照名の要否を、feature flag の RAPID_CROSSCHECK_MODE だけで決めている。off 以外では必須、off では省略でき、省略すると管理 DB に接続せず、確報比較依頼と管理 DB の行を削除しない。
- 確報クロスチェックは、速報クロスチェックのモードにかかわらず管理 DB を使う(CLI 契約: 確報系は確報クロスチェック設定 final-crosscheck.env の FINAL_DB_CONN_REF で常に接続する。abort-final-crosscheck.sh は「final-crosscheck.env 不在または FINAL_DB_CONN_REF 欠落」を管理 DB なしとして扱う)。
- このため、速報クロスチェックを off にして確報クロスチェックを使う設置では、確報比較依頼(確報クロスチェック runner の起動ごとに 1 件。日次なら 1 日 1 件程度)が管理 DB から削除されず、増え続ける。前回の変更(2026-11-03)の NFR の段階がこの点を指摘した。
- 利用者は、管理 DB を使う機能が 1 つでもあれば接続参照名を必須にし、管理 DB を一切使わない設置だけ省略を許すと決めた(2026-11-03)。

### 現在の仕様と問題

- ハウスキープを登録していても、確報比較依頼が保持日数を過ぎても消えない設置がありうる。容量が保持日数で頭打ちになるという前提が崩れる。

### 変更してほしいこと

- ハウスキープ設定の管理 DB 接続参照名は、次のどちらかに当てはまる設置では必須とする。欠落・空なら設定エラーで終える(今の off 以外での欠落・空と同じ扱い)。
  - RAPID_CROSSCHECK_MODE が off 以外
  - 確報クロスチェックを使う設置(確報クロスチェック設定がある)。何をもって「確報クロスチェック設定がある」とするか(ファイルの有無か、接続参照名の有無か)は、既存の確報系コマンドの判定と揃えて仕様で確定する。
- 管理 DB に接続しない振る舞い(確報比較依頼と管理 DB の行を削除せず warn、off 以外の期間に作られた実行を残して warn、off の期間の成果物だけの実行は成果物で判定)は、両方に当てはまらない設置(管理 DB を一切使わない設置)で接続参照名が無い・空のときだけに絞る。
- 要求の SPEC-014-08 の条件と受け入れ基準、SPEC-014-07 など接続参照名の要否に触れる箇所を、この条件に揃える。

### 完了条件

- 要求の受け入れ基準で、次を判定できる。
  - RAPID_CROSSCHECK_MODE=off で確報クロスチェックを使う設置で、接続参照名が無い・空なら、ハウスキープは設定エラーで終わり、何も削除しない
  - RAPID_CROSSCHECK_MODE=off で確報クロスチェックを使わない設置で、接続参照名が無い・空なら、今の管理 DB に接続しない振る舞いになる
  - RAPID_CROSSCHECK_MODE=off で確報クロスチェックを使う設置で接続参照名があれば、保持日数を過ぎた終端の確報比較依頼が消える
- 仕様(CLI 契約の housekeep.sh の起動条件・エラー一覧・判定手順)が、要求と同じ条件になっている。

## CR-9d2e6c41-002: env 形式の設定で、前後の空白を除いて `#` で始まる行をコメントとする

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- CLI 契約の env 形式の入力規則(config_input_rules.env_files)は、コメントを「行頭 `#`」の行と定めている。先頭に空白がある `#` 行(例: `  # メモ`)は、`=` を含まなければ invalid line(終了コード 2)になる。
- 実装の feature flag 設定の読み込み(facade/src/repository/feature_flag_config.sh)は、行全体の前後の空白を除いてから判定するため、この行をコメントとして扱う。速報クロスチェック設定の読み込み(facade/src/repository/rapid_crosscheck_env.sh)は、行頭の `#` だけをコメントとし、この行を invalid line にする。
- 前回の仕様の段階が、この違いを判断記録(2026-11-03)に参考として記録した。
- 利用者は、契約を「前後の空白を除いて `#` で始まる行はコメント」に改めると決めた(2026-11-03)。字下げしたコメントは書かれやすく、エラーにすると不便なため。

### 現在の仕様と問題

- 同じ行が、設定ファイルによってコメントになったりエラーになったりする。

### 変更してほしいこと

- config_input_rules.env_files のコメントの定義を、「前後の空白(半角空白とタブ)を除いた結果が `#` で始まる行はコメント」に改める。例を添える(`# x` / `  # x` / `\t# x` はいずれもコメント)。
- 空白だけの行(invalid line)、キーが空の行(invalid line)、`=` を含まない行(invalid line)の今の規則は変えない。`KEY=#abc` のように値が `#` で始まる行は、コメントではなく値 `#abc` のままとする。
- env 形式の全設定ファイルに共通で適用する。各設定契約や UC spec に独自の記述があれば揃える。
- 速報クロスチェック設定の読み込みが新しい契約と違うことを、実装との差分として仕様の判断記録に残す(実装を契約に合わせる対象として扱う)。

### 完了条件

- env 形式の入力規則が、字下げしたコメント行をコメントとして扱うことを例つきで書いている。
- 字下げしたコメント行の結果が、どの env 設定ファイルでも同じ 1 つに決まる。
- 実装との差分が仕様の判断記録に残っている。
