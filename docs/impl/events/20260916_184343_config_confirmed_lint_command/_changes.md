# config_confirmed: lint コマンドの訂正

外部レビュー(Codex、review-refute-loop ラウンド 1)の指摘を受理。GNU xargs は空入力でも `shellcheck -x` を起動して exit 3 になるため、`.sh` が無い tier で Linux CI の lint が失敗する。

| 項目 | before | after |
|---|---|---|
| commands.lint(全 tier) | `find src test -name '*.sh' -print0 \| xargs -0 shellcheck -x` | `find src test -name '*.sh' -exec shellcheck -x {} +` |

同期先: docs/impl/latest/impl-config.yaml、.github/workflows/ci.yml、CLAUDE.md。
