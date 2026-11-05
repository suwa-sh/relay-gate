---
schema_version: distillery.feedback-request/v1
feedback_id: 20261103_env_duplicate_key
created_at: 2026-11-03T15:00:00+09:00
source: distillery-impl
uc_id: b7c40e19
---

# 利用者からの変更要求(env 形式の設定で同じキーが複数行あるときの扱い)

## CR-b7c40e19-001: env 形式の設定で同じキーが 2 行以上あれば設定エラーにする

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- CLI 契約の env 形式の入力規則(config_input_rules.env_files)は、同じキーが複数行に書かれたときの扱いを定めていない。CSV 形式の設定には `error: duplicate job_id job_id=<v> lines=<n1,n2,...>` の規則があるが、env 形式には対応する規則が無い。
- 実装の feature flag 設定の読み込み(facade/src/repository/feature_flag_config.sh)と速報クロスチェック設定の読み込み(facade/src/repository/rapid_crosscheck_env.sh)は、どちらも後の行の値を使う。
- 前回の仕様の段階のレビューがこの欠落を見つけ、範囲外として残した(2026-11-03)。
- 利用者は、同じキーが 2 行以上ある設定を設定エラーとして拒否すると決めた(2026-11-03)。書き間違い(例: `BLUE_MODE=off` の後に `BLUE_MODE=foreground`)に気付けるようにするため。

### 現在の仕様と問題

- 同じキーが 2 行ある設定で、どちらの値が使われるかが仕様から決まらない。
- 書き間違いで同じキーを 2 回書いても、黙ってどちらかの値で動く。

### 変更してほしいこと

- config_input_rules.env_files に、同じキーの重複の規則を足す。
  - コメント行と空行を除いた行で、取り出し方の (2) でキーの前後の空白を除いた結果が同じキーになる行が 2 行以上あれば、設定エラー(終了コード 2)とし、その設定ファイルの値を使わない。
  - キーの比較は大文字と小文字を区別した完全一致とする(例: `BLUE_MODE` と ` BLUE_MODE ` は同じキー、`BLUE_MODE` と `blue_mode` は別のキー)。
  - 値が同じでも重複とする。値が空の行も数える。各設定契約で未知のキーとして warn になるキーも数える。
  - 文言は CSV の重複の規則に揃え、`error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...` を基本とする(lines= は初出行を含む全行番号を出現順に)。正確な文言、invalid line など他のエラーと同時に起きたときの報告の順序は、既存のエラー報告の規則と揃えて仕様で確定する。
- env 形式の全設定ファイル(feature-flag.env / rapid-crosscheck.env / hang-detector.env / final-crosscheck.env / housekeep.env)に共通で適用する。各設定契約や UC spec に独自の記述があれば揃え、validate-config.sh の検査と、各コマンドが設定を読む時点の両方で同じ結果になるようにする。
- 今の実装 2 か所(後の行の値を使う)が新しい契約と違うことを、実装との差分として仕様の判断記録に残す(実装を契約に合わせる対象として扱う)。

### 完了条件

- env 形式の入力規則が、同じキーが 2 行以上ある設定を設定エラーにすることを、文言と例つきで書いている。
- 同じキーが 2 行以上ある設定の結果が、どの env 設定ファイル・どのコマンドでも同じ 1 つに決まる。
- 実装との差分が仕様の判断記録に残っている。
