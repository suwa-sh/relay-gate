---
schema_version: distillery.feedback-request/v1
feedback_id: 20261110_080548_impl_feedback_dcd8234d
created_at: 2026-11-10T08:05:48+09:00
source: distillery-impl
uc_id: dcd8234d
---

# 実装からの変更要求

## CR-dcd8234d-011: 設定検証の --verbose で出す info 行の文言と、未知キーの warn 行・起動コマンドの error 行との順が決まっていない

- severity: spec-gap
- related_ids: [SPEC-004-04, SPEC-004-01]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/_api-summary.yaml]

### 観測した事実

- `validate-config.sh --rapid-crosscheck <path> --verbose` は、現在の実装で、読み取ったキーごとに `info: key loaded key=<KEY> path: <path>` を 1 行ずつ標準エラーへ出す。この文言は実装が補ったもので、仕様のどこにも書かれていない。
- キーごとの検査の段(env の検査の段の 3 段目)では、現在の実装は次の順に出す。
  1. info 行をすべて(キーがファイルに初めて出た順)
  2. 未知キーの `warn: unknown key key=<KEY> path: ...` 行をすべて(キーがファイルに初めて出た順)
  3. 起動コマンド(RAPID_COMPARE_COMMAND)の検証の error 行
- 例: 1 行目 `ZZ=x`、2 行目 `RAPID_COMPARE_COMMAND=relative`、3 行目 `AA=x` のファイルを `--verbose` で検証すると、info 3 行 → warn 2 行 → error 2 行の順に出て、終了コードは 2 になる(独立した検証で実走して確認した)。
- 実装の単体テスト・ティアの BDD・UC の BDD・受け入れテストはすべて通っている。この順と文言を判定するテストは、仕様に基準が無いため置いていない。

### 現在の仕様と問題

- CLI 契約の validate-config.sh は `--verbose` を「行ごとの解決結果を info: で stderr に出す」とだけ書いている。info 行の具体的な文言を決めているのは `--job-map` の `info: resolved job_id=...` だけで、`--rapid-crosscheck` の info 行の文言は無い。この UC の API 要約も「行ごとの info を stderr に出す」だけである。
- 設定ファイルの検査の段の規則(config_input_rules.env_files)は、3 段目で未知キーの warn を出すことを決めているが、3 段目の中で info・warn・error をどの順に出すかを決めていない。
- 一方、hang-detector.env については、未知キーの warn 行・info 行・error 行の順を契約で決め、「どの入力・状態の組み合わせでも標準エラーの行数と内容を 1 つに決める」(2026-11-05 利用者承認)としている。速報クロスチェック設定の検証だけ、この決め方が抜けている。
- 同じ env の検査の段は、確報クロスチェック worker 設定(`--final-crosscheck`)とハウスキープ設定(`--housekeep`)の検証も使う。仕様に決まりが無いままだと、まだ実装していない UC の検証で、別の文言や別の順が選ばれるおそれがある。

### 変更してほしいこと

次の 3 点を CLI 契約で決め、この UC の API 要約と tier-facade.md を揃えてほしい。

1. info 行の文言
   - 案 1(推奨。今の実装のまま): `info: key loaded key=<KEY> path: <path>` を、読み取ったキーごとに 1 行出す。key= と path: の任意入力は、制御文字の可視表記の規則に従う
   - 案 2: 値まで出す形にする(例: `info: key loaded key=<KEY> value=<VALUE> path: <path>`)。ただし接続の参照名など、値を出さない決まりのキーの扱いも併せて決める必要がある
2. キーごとの検査の段の中での順
   - 案 1(推奨。今の実装のまま): info 行をすべて → 未知キーの warn 行をすべて → キーごとの検査の error 行(と hint)。info と warn は、それぞれキーがファイルに初めて出た順
   - 案 2: info 行と warn 行を物理行番号の順に混ぜて出し、そのあとに error 行を出す
3. この決まりを適用する範囲
   - 範囲 A: `--rapid-crosscheck` だけ
   - 範囲 B(推奨): env の検査の段を使う検証種別すべて(`--rapid-crosscheck` / `--final-crosscheck` / `--housekeep`)。同じ段の規則を共有しているため、検証種別ごとに違う結果にならないようにする。`--feature-flag` の info 行を出すかどうかも、同じ機会に明記する

### 完了条件

- `--rapid-crosscheck --verbose` について、どの入力でも標準エラーに出る info・warn・error の行の文言と順が、仕様だけから 1 つに決まる。
- 範囲 B を選んだ場合は、`--final-crosscheck` と `--housekeep` の `--verbose` についても、同じ規則が仕様から読み取れる。
- この UC の API 要約と tier-facade.md の記述が CLI 契約と食い違わない。

## CR-dcd8234d-012: 設定検証を途中の段で止めた回に、--verbose の info 行を出すかどうかが決まっていない

- severity: spec-gap
- related_ids: [SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md]

### 観測した事実

- `validate-config.sh --rapid-crosscheck <path> --verbose` で、行の構造の検査(`=` の無い行やキーが空の行、同じキーの重複)で止めた回、現在の実装は info 行を出さず、その段の error 行だけを出す。
- 例: 1 行目 `ZZ=x`、2 行目 `broken`、3 行目に正しい RAPID_COMPARE_COMMAND を置いたファイルを `--verbose` で検証すると、標準エラーは `error: invalid line line=2 path: ...` の 1 行だけで、終了コードは 2 になる(独立した検証で実走して確認した)。
- バイト・改行の検査(NUL / UTF-8 / BOM / CR)で止めた回も、error 行と hint 行だけを出す。こちらは仕様の決まりどおりである。

### 現在の仕様と問題

- バイト・改行の検査(config_input_rules.byte_checks.stop)は「第 1 段の error 行(と hint)だけを出して止め」と決めており、info 行を出さないことが読み取れる。
- 行の構造の検査(config_input_rules.env_files の 2 段目)は「違反が 1 件以上あれば、そのファイルの値を使わず、3 段目を行わない」とだけ書いている。補助出力の info 行もこの段で出さないのかは書かれていない。2 段目で止めた回でもキーは読み取れているため、「読んだキーを info で示す」という読み方も成り立つ。
- hang-detector.env は「走査前の設定エラーで止まる回は未知キーの warn 行を出さない」と明記しているが、validate-config.sh の info 行には同じ種類の明記が無い。

### 変更してほしいこと

行の構造の検査で止めた回の info 行の扱いを、CLI 契約の env の検査の段の規則に明記してほしい。

- 案 1(推奨。今の実装のまま): 出さない。1 段目と同じく、止めた段の error 行だけを出す。値を使わない回に「読み込んだ」と示すと誤解を招くため
- 案 2: 読み取れたキーの info 行を、2 段目の error 行より前に出す

範囲は、CR-dcd8234d-011 の 3 点目で選んだ範囲と同じにしてほしい(推奨は env の検査の段を使う検証種別すべて)。

### 完了条件

- 1 段目・2 段目・3 段目のどこで止めた回でも、`--verbose` の info 行を出すかどうかが仕様だけから決まる。
- 決めた規則が、CR-dcd8234d-011 と同じ範囲の検証種別に、同じ書き方で適用されている。
