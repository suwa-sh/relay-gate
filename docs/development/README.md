# 開発者マニュアル

## 前提(これだけ知っていれば読める)

- relay-gate は bash 中心のストラングラーファサード型実行基盤で、現在は**仕様策定フェーズ**です
- 実装フェーズの成果物は 2026-08-30 に一度破棄しました(復旧用タグ `archive/impl-6078c4ed-20260830`)。仕様を元の方針資料へ戻す還流のあと、distillery-impl の bootstrap から再開します
- 仕様の正本は `docs/specs/latest/`、開発プロセスの正本はリポ直下の `CLAUDE.md` と `docs/dev-rules/` です

## いま読むべきもの

| 目的 | 場所 |
|---|---|
| 仕様全体のナビゲーション | [`docs/README.md`](../README.md)(自動生成) |
| UC 別の仕様 | `docs/specs/latest/{業務}/{BUC}/{UC}/spec.md` と `tier-*.md` |
| CLI コマンド契約 | `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml` |
| DB スキーマ | `docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml` |
| 実装フェーズ再開時の規約 | `docs/dev-rules/`(coding-rules / test-strategy / tier-rules) |

## 実装ワークフロー(再開時)

1. distillery-impl の `dist-impl-run` を bootstrap(S0)から実行し、tier 構成・契約・コマンドを再確定する
2. 受け入れテスト(ATDD → UC BDD → tier BDD)が RED であることを確認してから実装する
3. 契約生成物は直接編集しない
4. 仕様との矛盾はコードで曲げず、distillery の差分更新(feedback request)に戻す。変更要求は元の方針資料(`tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md`)と照合する

## コントリビュート

参加方法(Issue / PR の受け方)と問い合わせ先はリポ直下の [`CONTRIBUTING.md`](../../CONTRIBUTING.md) を参照してください。
