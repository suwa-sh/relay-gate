# 提案: プロジェクトの CLAUDE.md / dev-rules に書き足す内容

この提案は既存の CLAUDE.md と `docs/dev-rules/` を変更しない。採否は利用者が決める。`20261115_180737_proposal-context.md` までの提案に足すもので、置き換えではない。

## 背景

- 開発機(macOS)の ShellCheck 0.11.0 で通ったコードが、CI と同じ Ubuntu 24.04 の ShellCheck 0.9.0 で失敗した(詳細: `20261116_034712_linux-lint-version-gap.md`)
- Linux のコンテナのイメージに node と shfmt が無く、tier の BDD は Linux で実行できていない
- 層の間だけで使う戻り値の選択が、前提の記録から漏れていた(詳細: `20261116_034712_internal-return-code-missed-in-assumptions.md`)

## 提案内容

| 対象 | 書き足す内容(案) |
|---|---|
| CLAUDE.md の「distillery-impl 実装ハーネス規約」のコマンドの項 | lint・format・単体テストは、開発機に加えて CI と同じコンテナ(`relay-gate-ci:ubuntu24`)でも実行する。開発機の ShellCheck は CI の版(0.9.0)より新しく、開発機で通っても CI で落ちる診断がある |
| `docs/dev-rules/coding-rules.md` | 省略できる引数を持つ関数は、呼び出し側で既定と同じ値を明示して渡す(ShellCheck 0.9.0 の SC2120 / SC2119 を避ける)。診断の抑制と、引数の無条件の転送は使わない |
| `docs/dev-rules/test-strategy.md` | コンテナでは、リポジトリを読み取り専用でマウントし、コンテナ内の一時ディレクトリへ複製してから実行する。複製には `.editorconfig` などの設定ファイルを含める(落とすと format の結果が変わる) |
| CI のコンテナのイメージ | node と shfmt を入れ、4 つのゲートすべてを Linux で実行できるようにする |
| `docs/dev-rules/coding-rules.md` | 関数がコマンドの終了コードと違う値を返すときは、値の意味と、終了コードへ変える層をコメントに書く |

## 期待する効果

- CI でだけ落ちる lint の失敗を、取り込みの前に見つける
- 残りの機能でも、Linux で確認できる範囲を 4 つのゲートすべてに広げる
- 内部の戻り値の意味が、機能をまたいで食い違わない
