---
schema_version: distillery.feedback-request/v1
feedback_id: 20261123_175902_impl_feedback_7c41c7cd
created_at: 2026-11-23T17:59:02+09:00
source: distillery-impl
uc_id: 7c41c7cd
---

# 実装からの変更要求

## CR-7c41c7cd-001: 入力の複製の作業名を、どの mktemp でもプロセスごとに分かれる形に定める

- severity: spec-gap
- related_ids: [SPEC-004-01, REQ-004]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

設定ファイルを読む処理(検証コマンド、ジョブを起動する入口、slot runner)は、入力を一時ファイルへ 1 回複製してから読む。複製の作業名は、CLI 契約の例のとおり `mktemp "${TMPDIR:-/tmp}/relay-gate-XXXXXX.part"` で作っていた。

| 環境 | 起きたこと |
|---|---|
| 開発機(macOS。BSD 系の mktemp) | 作業名が毎回 `relay-gate-XXXXXX.part` のままになった。X の並びが名前の末尾に無いと、置き換えられない |
| 同じ開発機で、blue と green の slot runner がほぼ同時に動いたとき | 2 つのプロセスが同じ作業名を取り合い、後から来たほうの複製が失敗した。機能をまたぐシナリオテスト 1 件が、約半分の確率で失敗した |
| 同じ開発機で、同じテンプレートを 2 回続けて実行したとき | 1 回目は `relay-gate-XXXXXX.part` を作り、2 回目は「File exists」で失敗した(手元で再現) |
| 実行環境の Linux(GNU の mktemp) | この実装の作業では実行していない。X の並びが置き換わるかどうかは未確認 |

実装は、テンプレートを `relay-gate-<プロセスの番号>-XXXXXX.part` に変えて回避した。回避後は、同じシナリオを 20 回流して失敗 0 回だった。

自動のセキュリティ点検は、次の点を指摘した。macOS では作業名が予測できる。同じ一時ディレクトリを使える別の利用者が、先に同じ名前のファイルを置くと、複製を失敗させられる。複製の内容を読まれたり、すり替えられたりはしない(作成は「既にあれば失敗」で、権限は所有者だけの 0600)。

### 現在の仕様と問題

CLI 契約の「入力の複製」の規則は、次のように定める。

- 複製のファイル名は `relay-gate-` で始まる
- 作業名は「最終名 + `.part`」で、書き終えてから最終名へ名前を変える
- 作業名は mktemp で作る(例 `mktemp "${TMPDIR:-/tmp}/relay-gate-XXXXXX.part"`)
- 最終名を先に mktemp で確保しない

問題は 2 点ある。

- 例のテンプレートは、X の並びが名前の末尾に無い。mktemp の種類によっては名前が固定になり、同時に動くプロセスの作業名がぶつかる。開発機ではテストがこの形で動く
- 「最終名を先に確保しない」定めのため、X を末尾に置いたテンプレートで最終名を作り、それに `.part` を付ける、という素直な回避ができない。`relay-gate-` と `.part` の間の名前の決め方は書かれておらず、実装者が決めることになった

元の方針資料は「一時ファイルへ出力してから確定名へリネームできる」と書くだけで、名前の決め方の記載は無い。どの案も方針と食い違わない。

### 変更してほしいこと

入力の複製の作業名の決め方を、同時に動く複数のプロセスで名前が分かれる形に定める。選択肢は次のとおり。推奨は案 A。

| 案 | 内容 | 利点 | 欠点 |
|---|---|---|---|
| A(推奨) | 例と定めを、いまの実装の形に直す。作業名は `relay-gate-<プロセスの番号>-XXXXXX.part` を mktemp に渡して作る。名前の確保は mktemp の 1 回の操作のまま | 実装とテストが変わらない。どの mktemp でも、同時に動くプロセスの名前が分かれる | X を置き換えない mktemp では、名前がプロセスの番号だけで決まる(予測できる。影響は複製の失敗まで) |
| B | 一時ディレクトリを mktemp で作り(テンプレートの末尾に X を置く)、その中に作業名と最終名を置く | どの mktemp でも名前が乱数で分かれ、予測できない | 実装とテストの変更が要る。「ファイル名が `relay-gate-` で始まる」「最終名が現れたら複製済み」というテストの待ち方も見直しになる |
| C | 名前の決め方は実装に任せ、満たす条件だけを書く(同時に動くプロセスで名前が分かれる、名前の確保は「既にあれば失敗」の 1 回の操作、書き込み途中の複製を読ませない)。例は条件を満たすものに差し替える | 実装の自由度が高い | 条件を満たすかどうかの確認が、読み手ごとに要る |

どの案でも、X の並びが末尾に無いテンプレートだけに頼る例は残さない。

### 完了条件

- 入力の複製の作業名の決め方(または満たす条件)が、仕様から 1 つに決まる
- 仕様に書かれた例をそのまま使っても、X を置き換えない mktemp で、同時に動く 2 つのプロセスの作業名が別々になる
- 「最終名を先に確保しない」定めと、名前を分ける方法が、両立する形で書かれている

## CR-7c41c7cd-002: 自作の runner が共通ライブラリを呼ぶときの呼び方を定める

- severity: spec-gap
- related_ids: [SPEC-004-01, SPEC-004-02, SPEC-001-04, REQ-004]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/tier-facade.md, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md]

### 観測した事実

slot runner の「解決」(ジョブマップから JOB_ID の実行先を決め、実装へ渡す引数の並びを組み立てる)を、共通ライブラリ `lib/runner-resolve.sh` に実装した。標準の slot runner は、このライブラリを読み込んで使う。

呼び方は仕様に無かったため、実装者が次のように決めた。

| 項目 | 実装者が決めた内容 |
|---|---|
| 解決の入口 | 関数 `resolve_execution_target <script> <run_id> <job_id> <role> [PARAM...]` |
| 結果の受け取り方 | シェルの変数(`EXECUTION_TARGET_HOST` など 9 個と、引数の並びの配列 `ARGUMENT_LIST`) |
| 値が無い項目(host / user / credential_ref / map_version) | 空文字で表す |
| 解決できなかったとき | 戻り値が 0 以外。runner が終える値は、別の変数 `RUNNER_RESOLVE_EXIT_CODE` で受け取る |
| 補助の関数 | `parse_csv_row <1 行>`(結果は配列 `CSV_CELLS`)、`build_argument_list <固定引数の JSON 配列> [PARAM...]`(結果は配列 `ARGUMENT_LIST`) |
| 二重起動の判定 | 関数 `runner_resolve_guard_existing_result <run_id> <role>` |
| 呼ぶ前に要る環境変数 | 設定ファイル置き場、成果物ルート、ログ置き場の 3 つ |

独立した検証は、この 4 つの判断(入口、値が無い項目の表し方、補助の関数、二重起動の判定)を、どれも「仕様に記載なし(矛盾なし)」と判定した。

統合テストと受け入れテストは、この呼び方に頼っている。解決結果のうち、実行ログの行に出ない項目(user / script / work_dir / 上限 / credential_ref / 固定引数 / 引数の並び)を確かめるために、テストが共通ライブラリを直接呼ぶ。テストの該当箇所には「暫定。呼び方が仕様で決まったら見直す」という注記を付けた。

### 現在の仕様と問題

- CLI 契約は、利用者が runner を自作できると定める。自作の runner は「relay-gate が提供する共通ライブラリ 4 ファイルを読み込んで使える」と書く
- この機能の仕様は「自作の runner も同じライブラリを読み込めば、同じ解決になる」と書く
- 機能の完了条件のシナリオは「CSV 行分解関数を呼ぶ」「引数連結関数を呼ぶ」と、関数を呼ぶ前提で書く。関数の名前(`resolve_execution_target` / `parse_csv_row` / `build_argument_list`)は仕様の表に出てくる
- 一方、関数の引数、結果の受け取り方、解決できなかったときの知らせ方、呼ぶ前に要る環境変数は、どこにも書かれていない

このため、runner を自作する利用者は、ライブラリのソースを読まないと使えない。実装者が決めた呼び方を後で変えると、自作の runner が動かなくなるが、変えてよい範囲も決まっていない。

元の方針資料は、runner を適用ごとに割り当てること、起動方式の違いを runner に閉じ込めることを書く。共通ライブラリの記載は無い。どちらの案も方針と食い違わない。

### 変更してほしいこと

共通ライブラリ `lib/runner-resolve.sh` を、自作の runner へ約束する入口として扱うかどうかを定める。選択肢は次のとおり。推奨は案 A。

| 案 | 内容 | 利点 | 欠点 |
|---|---|---|---|
| A(推奨) | 約束する入口として、呼び方を仕様に書く。書くのは、解決の入口と補助の関数 2 つの、名前・引数・結果の受け取り方・値が無い項目の表し方・解決できなかったときの知らせ方・呼ぶ前に要る環境変数。内容は、上の表(いまの実装)のとおりとする | 実装とテストが変わらない。自作の runner が、ソースを読まずに同じ解決を使える。テストの暫定の注記を外せる | 書いた呼び方は、後で変えにくくなる |
| B | 約束しないと仕様に書く。共通ライブラリの関数は relay-gate の内部のもので、自作の runner が満たすのは runner の起動の引数と成果物の約束だけ、とする。「読み込んで使える」「同じ解決になる」の記述は外す | 仕様が軽い。内部を自由に変えられる | 自作の runner は、ジョブマップの解決を自分で作ることになる。完了条件のシナリオの「関数を呼ぶ」という書き方も見直しになる |

案 A の場合、二重起動の判定の関数を約束に含めるかどうかも、あわせて決める。残りの共通ライブラリ 3 ファイル(実行の指示書の保存、結果の出力、完了の通知)は、まだ実装していない。この要求の対象は `lib/runner-resolve.sh` だけとする。

### 完了条件

- 共通ライブラリ `lib/runner-resolve.sh` の関数が、自作の runner へ約束する入口かどうかが、仕様から 1 つに決まる
- 案 A の場合、解決の入口と補助の関数の、名前・引数・結果の受け取り方・値が無い項目の表し方・解決できなかったときの知らせ方・呼ぶ前に要る環境変数が、仕様から読み取れる
- 案 B の場合、約束しないことが仕様から読み取れ、「読み込んで使える」「同じ解決になる」の記述と完了条件のシナリオが、それと食い違わない

## CR-7c41c7cd-003: 読めないジョブマップの報告の文言をそろえる

- severity: spec-gap
- related_ids: [SPEC-004-01, REQ-004]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md]

### 観測した事実

ジョブマップが「あるが読めない」とき、読み手によって報告の文言が違う。どの読み手も終了コードは 2 で同じである。

| 読み手 | ジョブマップが無い | ジョブマップがあるが読めない |
|---|---|---|
| feature flag の検証(`validate-config.sh --feature-flag`) | `error: job map not found slot=<slot> map=<場所>` | `error: job map not found slot=<slot> map=<場所>`(無いときと同じ) |
| ジョブマップの検証(`validate-config.sh --job-map`) | `error: config file not found path: <パス>` | `error: config file is not readable path: <パス>` |
| slot runner(stderr.log に書く) | `error: job map not found slot=<slot> map=<場所>` | `error: config file is not readable path: <場所>` |

実装とテストで確かめたことは次のとおり。

- feature flag の検証は、「通常のファイルでない」と「読み取り権限が無い」を 1 つの条件で判定し、どちらも `job map not found` を出す(`facade/src/domain/feature_flag.sh` の `validate_slot_runner_assignment`)
- ジョブマップの検証と slot runner は、存在と読み取りを分けて判定する。読めない場合の文言は、単体テストが固定している(ジョブマップの検証 2 件、slot runner 3 件)
- feature flag の検証で「あるが読めない」場合を確かめるテストは無い。いまのテストが固定しているのは、無い場合の文言だけである
- slot runner は、この機能の 1 回目の実装では、読めないジョブマップも `job map not found` と報告していた。独立した検証が「全コマンド共通のエラー表示の規約と食い違う」と指摘し、`config file is not readable` へ直した

### 現在の仕様と問題

仕様の記述は次のとおり。

| 場所 | 記述 |
|---|---|
| 機能「feature flag を設定する」の tier-facade.md | 決めた場所にジョブマップが「存在しない / 読めない」は `error: job map not found slot=<slot> map=<決めた場所>`(2 か所に明記) |
| 機能「slot runner の実体スクリプトを割り当てる」の tier-facade.md | 検証項目は「存在し読める」。違反の文言は `job map not found` の 1 つだけ |
| CLI 契約の feature flag の検証 | 「存在し読めることを検査する(無ければ `job map not found`)」。読めない場合の文言は書いていない |
| CLI 契約の検証コマンドの共通形式 | 「ファイル無し・読めない」は `config file not found` / `config file is not readable`。検証の種類を問わず共通の形式にし、各機能の tier md はこれにそろえる、と書く |
| 全コマンド共通のエラー表示の規約(ui-design.md) | 読めないときは `error: config file is not readable path: ...`(終了コード 2。runner は exitcode.txt=2) |

問題は 2 点ある。

- 同じ「あるが読めないジョブマップ」に 2 通りの文言がある。feature flag の検証は「見つからない」と報告するため、運用者はファイルを置き直そうとする。実際に直すべきなのは権限である
- 共通の規約は「読めない場合は読めないと報告する」と定め、機能の tier md は「読めない場合も見つからないと報告する」と定める。どちらが優先かは書かれていない。slot runner では、実装者が tier md と同じ考えで実装し、検証で差し戻された

元の方針資料は、slot runner がジョブマップで実行先を解決することを書く。エラーの文言と、読めない場合の報告のしかたの記載は無い。どの案も方針と食い違わない。

### 変更してほしいこと

「あるが読めないジョブマップ」の報告を、読み手によらず 1 つの考え方にそろえる。選択肢は次のとおり。推奨は案 A。

| 案 | 内容 | 利点 | 欠点 |
|---|---|---|---|
| A(推奨) | 共通のエラー表示の規約にそろえる。feature flag の検証でも、あるが読めないジョブマップは `error: config file is not readable path: <決めた場所>` と報告する。無いときの `job map not found` は変えない | ジョブマップの検証・slot runner と同じ文言になる。運用者が権限の問題だと分かる。新しい文言を足さない | feature flag の検証の実装と仕様の 2 機能の記述を直す。読めない場合の行には `slot=` が付かない(場所で見分ける) |
| B | いまの書き分けを残し、例外として明記する。共通の規約に「feature flag の検証の所在の検査だけは、読めない場合も `job map not found`」と書く | 実装とテストが変わらない | 同じ状態に 2 通りの文言が残る。運用者が原因を取り違える点は直らない |
| C | ジョブマップ専用の文言を新しく定める(例 `error: job map is not readable slot=<slot> map=<場所>`)。feature flag の検証と slot runner が使う | `slot=` が付き、無い場合の文言と形がそろう | 文言が 1 つ増える。直したばかりの slot runner とそのテストも変える。ジョブマップの検証(`--job-map`)とは文言が分かれたままになる |

案 A を採った場合に変わる箇所(事実)は次のとおり。

- 実装: `facade/src/domain/feature_flag.sh` の `validate_slot_runner_assignment`(存在の判定と読み取りの判定を分ける)。ジョブマップの検証と slot runner は変わらない
- テスト: いまあるテストの期待値は変わらない(無い場合の `job map not found` だけを固定している)。読めない場合のテストを足す。足す先は、関数の単体テスト(`facade/test/domain/feature_flag.bats`)、検証コマンドの単体テスト(`facade/test/usecase/validate_feature_flag.bats`)、機能のシナリオ(`facade/features/configure-feature-flags.feature`)
- 仕様: 2 機能の tier-facade.md の該当行、CLI 契約の feature flag の検証の stderr の一覧と error 行の順の記述

案 A の場合、次の 2 点もあわせて決める。

- error 行の順: 読めない場合の行を、いまの `job map not found` と同じ位置(対応ジョブマップ。blue → green の順)に出すかどうか
- 決めた場所にディレクトリなど通常のファイルでないものがあるときの扱い。slot runner は「読めない」、feature flag の検証は「見つからない」と報告している

### 完了条件

- 「あるが読めないジョブマップ」を、feature flag の検証・ジョブマップの検証・slot runner がそれぞれどの文言で報告するかが、仕様から 1 つに決まる
- 機能の tier md と、全コマンド共通のエラー表示の規約が、同じ状態に別々の文言を定めていない(例外を残す場合は、例外であることが共通の規約から読み取れる)
- 案 A の場合、feature flag の検証で、読めないジョブマップの行の文言と、ほかの error 行との順が、仕様から読み取れる
