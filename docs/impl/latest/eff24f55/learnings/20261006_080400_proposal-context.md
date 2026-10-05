# CLAUDE.md / dev-rules への提案(relay-gate)

既存の CLAUDE.md と `docs/dev-rules/` は変更していない。取り込むかどうかは保守者が判断する。

## 提案 1: 「変更完了チェックリスト」に Linux コンテナでの bats 実行を追加する

- 現状: CLAUDE.md の変更完了チェックリストは lint / doc link / mermaid のゲートだけを挙げる。実行環境(オンプレ Linux)相当での実行は書かれていない。
- 問題: 開発機(macOS)で全ゲート green の実装が、PR の Linux CI で 5 件失敗した。
- 提案: チェックリストに次の 1 項を追加する。
  - 「bash 実装を変更したら、PR を出す前に Linux コンテナで bats を実行する: `docker run --rm -e LANG=C.UTF-8 -v "$PWD:/work" -w /work/<tier> relay-gate-ci:ubuntu24 bats -r test`」
  - イメージ `relay-gate-ci:ubuntu24` のビルド手順を `docs/development/` に置く(独立検証が同じイメージを使った)。

## 提案 2: `docs/dev-rules/coding-rules.md` にロケールとパイプラインの規約を追加する

- 現状: 実装規約は「エアーギャップ」「Runner Result Contract」「コメントは日本語」などで、ロケールと SIGPIPE の扱いは無い。
- 問題: 同じ落とし穴が他の tier(rapid-crosscheck / final-crosscheck / ops)でも再現し得る。
- 提案(3 行):
  1. 外部入力(設定ファイル・コマンド出力)を読む `read` / `[[:space:]]` / `tr` / `sed` は `LC_ALL=C` で実行する。バイト単位の仕様はバイト単位で実装する。
  2. パイプラインの失敗判定は `PIPESTATUS` を後段から見る。後段が失敗したら前段の終了状態(141 / 1)は見ない。
  3. 行数に比例する処理は線形の実装を選ぶ。性能テストの閾値は Linux runner で目標の 50% 以下を目安にする。

## 提案 3: CLAUDE.md の実装規約に「出力の空白判定は ASCII 固定」を追記する(A-058 が承認された場合)

- 現状: CLI 契約は「値に空白を含めば `key: value`」と書くが、空白の範囲を定義しない。
- 提案: A-058 が S9 で承認されたら、CLAUDE.md の「実装規約」に「stdout の `key=value` / `key: value` の空白判定は ASCII 6 種(半角空白・タブ・LF・VT・FF・CR)をバイト単位で判定する(全 tier 共通)」を 1 行追加する。他の tier が同じ判定を共有する根拠になる。
- `spec_change` で却下された場合は、この提案ではなく cross-cutting の出力規約への変更要求にする。
