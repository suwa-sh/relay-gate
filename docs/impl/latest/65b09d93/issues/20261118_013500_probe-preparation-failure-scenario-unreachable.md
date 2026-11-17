# 問い合わせの準備失敗の Scenario は、書かれた Given のままでは Then に届かない

- uc_id: 65b09d93(slot runner の実体スクリプトを割り当てる / assign-slot-runner-scripts)
- 起票 stage: S4 tier-impl(tier-facade, attempt 1)
- 種別: 仕様どうしの食い違い(Scenario の Given と、契約の入力の複製の規則)
- blocker: false(step で起こし方を変えて判定した。下記)

## 仕様の記載

tier-facade.md「ティア完了条件(BDD)」の Scenario「validate-config_sh_feature-flag は --help 問い合わせの準備に失敗すると終了コード 6 で止まる」:

- Given: 有効な並行稼働設定の ff.env があり、一時ファイルの作成先(環境変数 TMPDIR)が存在しないディレクトリ /nonexistent/tmp を指す
- Then: 終了コード 6 で stderr に "error: runner probe failed slot=blue reason=" で始まる行が出る
- And: stderr に "warn: runner does not respond to --help" で始まる行は出ず、stdout は 0 行である

一方、cli-command-contract.yaml の `config_input_rules.snapshot.validate_config` は、validate-config.sh が検証開始時に入力を TMPDIR 配下の一時ファイルへ 1 回だけ複製すると定め、`config_input_rules.internal_failure` は複製の失敗を `error: config snapshot failed ...`(終了コード 6)とする。runner への `--help` の問い合わせは、キーごとの検査の後に行う(`runner_help_probe`)。

## 実装で判明した事実

- TMPDIR を存在しないディレクトリにすると、問い合わせより先に入力の複製が失敗する。現行の validate-config.sh(契約どおり)は stderr に `error: config snapshot failed path: ff.env` と `hint: check TMPDIR is writable` を出して終了コード 6 で終わり、`error: runner probe failed slot=blue reason=...` には届かない
- 2026-11-18 に、有効な並行稼働設定(両 runner が --help に応答、両ジョブマップあり)で `TMPDIR=/nonexistent/tmp validate-config.sh --feature-flag ff.env` を実行して確認した(終了コード 6、上の 2 行)
- 同じ食い違いは 2026-11-13 の S2 再実行で単体テスト側でも見つかっていて、`facade/test/presentation/validate_config.bats` は PATH の先頭に代替の mktemp を置いて問い合わせの一時ファイルだけを失敗させている(`snapshot.out_of_scope` が代替コマンドの利用を認める)

## この UC での扱い(実装は変えていない)

- validate-config.sh の振る舞いは変えていない(問い合わせを入力の複製より前に動かすことはできず、既存の出力も変わる)
- tier BDD の step は Given の文言どおり TMPDIR を /nonexistent/tmp にしたうえで、PATH の先頭に代替の mktemp を置く。代替の mktemp は、入力の複製の作業名(テンプレートの末尾が `.part`)だけを Scenario 専用の書けるディレクトリへ向けて本物の mktemp に渡し、それ以外(問い合わせの応答を受ける一時ファイル)は TMPDIR のまま本物の mktemp に渡す。問い合わせの一時ファイルの作成は実際に失敗する
- step: `facade/features/steps/assign-slot-runner-scripts.steps.js`(Given「有効な並行稼働設定の ff.env があり、一時ファイルの作成先…」)

## 提案(S8 で仕様へ)

Scenario の Given を、問い合わせの一時ファイルの作成だけが失敗する起こし方に書き換える。例:

- 「有効な並行稼働設定の ff.env があり、入力の複製は成功するが、runner の問い合わせの応答を受ける一時ファイルの作成に失敗する(テストは PATH の先頭に代替の mktemp を置いて起こす。config_input_rules.snapshot.out_of_scope)」

あわせて、TMPDIR に書けないときは入力の複製の失敗(`config snapshot failed`)が先に出ることを、`runner_help_probe.preparation_failure` の注記に書くとよい。
