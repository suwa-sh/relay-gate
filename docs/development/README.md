# 開発者マニュアル

## 前提(これだけ知っていれば読める)

- relay-gate は bash 中心のストラングラーファサード型実行基盤で、現在は実装フェーズ(仕様駆動・テスト先行)です
- 仕様の正本は `docs/specs/latest/`、開発プロセスの正本はリポ直下の `CLAUDE.md` と `docs/dev-rules/` です

## 開発環境セットアップ

```bash
git clone https://github.com/suwa-sh/relay-gate.git
cd relay-gate

# シェル系ツール(macOS の例。Linux は各ディストリのパッケージで同等品を導入)
brew install shfmt shellcheck bats-core

# BDD ランナー(cucumber-js。Node 22 系)
npm install
```

## テストの 4 段構成

正本は `docs/dev-rules/test-strategy.md`。上 3 段の Gherkin は仕様からの転写で、創作しません。

| 段 | 内容 | 置き場 | 実行 |
|---|---|---|---|
| ① ATDD | USDM の受け入れ基準(38 SPEC / 41 Scenario 生成済み) | `features/atdd/` | `npm run bdd:atdd` |
| ② UC BDD | UC spec の E2E 完了条件 | `features/uc/` | `npm run bdd:uc` |
| ③ tier BDD | tier 別完了条件 | `facade/features/` `worker/features/` | `npm run bdd:tier-facade` 等 |
| ④ TDD 単体 | 実装者が red→green→refactor で設計 | `facade/test/` `worker/test/` | `bats facade/test` 等 |

format / lint / 品質ゲートを含む検証コマンド一式は `CLAUDE.md` の「検証コマンド」を参照してください。CI(`.github/workflows/ci.yml`)も同じコマンドで 6 段ゲートを実行します。

## 実装ワークフロー(仕様駆動)

1. `docs/impl/latest/uc-map.yaml` の UC を単位に、`docs/specs/latest/` の該当 spec.md / tier-*.md を読む
2. 受け入れテスト(①〜③)が RED であることを確認してから実装する
3. `packages/contracts/`(契約生成物)と `packages/ui/`(取り込み資産)は直接編集しない
4. 仕様との矛盾はコードで曲げず、distillery の差分更新(feedback request)に戻す

詳細な規約(コーディング・tier 境界)は `docs/dev-rules/coding-rules.md` / `docs/dev-rules/tier-rules.md` を参照してください。

## コントリビュート

参加方法(Issue / PR の受け方)と問い合わせ先はリポ直下の [`CONTRIBUTING.md`](../../CONTRIBUTING.md) を参照してください。
