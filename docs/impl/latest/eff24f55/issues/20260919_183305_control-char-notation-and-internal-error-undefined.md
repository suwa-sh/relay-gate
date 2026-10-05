# 制御文字の表示表記と、検証器の内部障害の出力が仕様に定義されていない

- 起票: tier-facade Implementer(attempt 4)
- 種別: 仕様の不足(spec-gap)
- 対象: `validate-config.sh --job-map`(設定ファイルを検証する機能に共通する論点)
- 関連: `20260919_195500_malformed-input-policy-undefined.md`(方針の決定)。本 issue は、その方針で実装したときに実装側で決めた具体値の記録

## 仕様の記載

| 記載 | 出所 |
|---|---|
| ANSI エスケープを出さない。1 行 1 事実 | ui-design.md 出力フォーマット / cli-command-contract.yaml conventions.output_format |
| 文字コード UTF-8 | tier-facade.md 設定契約 |
| 終了コード 6 は実行エラー(内部エラーを含む) | cli-command-contract.yaml conventions.exit_codes |
| validate-config.sh の終了コード 6 の条件は runner --help 問い合わせの準備失敗だけ | cli-command-contract.yaml commands[validate-config.sh].exit_codes |

## 実装で判明した事実

### 1. 制御文字の置き換え表記を実装で決めた

任意入力(セルの値・列名・パス・引数)を出力する全経路で、次の表記へ置き換える。

| 対象 | 表記 |
|---|---|
| 改行(U+000A) | `\n` |
| タブ(U+0009) | `\t` |
| その他の U+0001〜U+001F と U+007F | `\u00XX`(16 進小文字 4 桁) |
| UTF-8 で符号化した C1 制御文字 U+0080〜U+009F | `\u0080`〜`\u009f` |

- `--verbose` の `fixed_params=` の JSON エスケープと同じ表記にした(同じ関数で作る)。
- バックスラッシュは置き換えない。制御文字を含まない値の表示を 1 バイトも変えないためである。
- その結果、生のタブと、文字としての `\t`(2 文字)は表示上区別できない。
- `key=value` と `key: value` の選択は、置き換え前の値に空白があるかで決める。
- パスに含まれる UTF-8 として不正なバイトは置き換えない(path_uri「そのまま出す」に従う)。

### 2. 不正な UTF-8 の拒否に既存の文言を流用した

- UTF-8 として不正なバイト列を含む行は `error: csv quote is invalid line=N path: <path>`、終了コード 2 で拒否する。
- 行頭 `#` のコメント行でも拒否する(文字コードはファイル全体の形式と解釈した)。
- NUL を含むコメント行は従来どおり無視する(U+0000 は UTF-8 として妥当)。
- 原因(文字コード)が文言から読み取れない。Shift_JIS のコメントを含むファイルで利用者が迷う可能性が高い。

### 3. 検証器の内部障害の出力を実装で決めた

検証に使う補助コマンド(tr / sed / sort)が失敗したとき、検証 OK にも検証違反にもせず、次のように終える。

| 障害 | stderr | 終了コード |
|---|---|---|
| 事前走査(NUL・不正な UTF-8)の tr / sed の失敗(走査完了の証跡が無い、総行数が読み込んだ行数と違う、を含む) | `error: internal command failed commands=tr,sed path: <path>` | 6 |
| job_id 重複検査の sort の失敗(行数の不一致、昇順に並んでいない、を含む) | `error: internal command failed commands=sort` | 6 |

- 文言は CLI 契約に無い。runner 問い合わせの準備失敗(`error: runner probe failed ...`、終了コード 6)と同じ区分に置いた。
- validate-config.sh の exit_codes[6].condition にこの条件が無い。

### 4. 先行 UC「feature flag を設定する」の stderr に同じ穴が残る

- 共通関数(`cli_field_line` / `cli_path_field_line`)を直したため、`--feature-flag` の stdout は制御文字を出さなくなった。
- `--feature-flag` の stderr(`error: invalid value key=... value=...`、`error: path is not absolute ... path=...`、`warn: unknown key key=...` など)は、値・キー名・パスをそのまま出す。
- これらは UC fd678b04 の domain / usecase の実装で、本 UC の対象外のため変更していない。

## 提案

1. 出力フォーマット規約(ui-design.md / conventions.output_format)に、任意入力の制御文字の表記規則を追加する。バックスラッシュを置き換えるかどうかも決める。
2. 設定契約に、文字コード違反の専用の error 行を追加する(例: 原因が文字コードだと分かる文言)。コメント行を対象に含めるかも明記する。
3. validate-config.sh の exit_codes[6].condition と stderr に、検証器の内部障害の行を追加する。
4. 表記規則を cross-cutting に置いたうえで、UC「feature flag を設定する」の stderr にも適用する変更を起こす。
