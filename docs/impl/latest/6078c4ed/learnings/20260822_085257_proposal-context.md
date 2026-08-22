# CLAUDE.md / dev-rules への提案(実体テストの環境前提と契約の共有値)

## 何が起きたか

- 実 PostgreSQL の実体テストを追加した結果、ローカルと CI で PostgreSQL バイナリ(initdb / pg_ctl / psql)または docker が前提になったが、その前提がリポジトリの開発ルールに無い
- lint gate(`find facade -name '*.sh'`)が拡張子無しの `facade/bin/relaygate` を対象外にしたままで、実装側が手動で shellcheck を補っている
- tier をまたいで同じ値を算出する契約(監査 hash、引数のシリアライズ、時刻精度)が、実装時点で未定義だった

## 原因

dev-rules の test-strategy は 4 段テストの階層を定めるが、I/O 境界を実体で検証するための環境前提(必要バイナリ、起動方法、skip 方針)を定めていない。impl-config の lint コマンドは拡張子ベースで、CLI エントリポイントの命名規約と一致していない。

## 回避方法

- `docs/dev-rules/test-strategy.md` に「実体テストの環境前提」節を追加する: 実 PostgreSQL は一時インスタンス(pg_ctl / docker)で起動する、環境不足は fail(暗黙 skip 禁止、明示 skip の環境変数名)、CI の PATH 設定
- `docs/impl/latest/impl-config.yaml` の lint を拡張子無し実行ファイルも対象にする(`facade/bin/*` の明示追加、または shebang 検出)
- `docs/dev-rules/coding-rules.md` に「複数 tier が共有する算出規則(hash / シリアライズ / 時刻精度 / 識別子形式)は契約側に定義されるまで実装で確定しない。仮置きする場合は関数を 1 箇所に集約し、as-built と issue に記録する」を追加する

## 次回の対応

設定所有者が impl-config と dev-rules を更新し、次の UC(tier-worker を含む c3c7ab31)の着手前に適用する。

## 反映記録(2026-08-22)

- `docs/dev-rules/test-strategy.md` に「実体テストの環境前提(I/O 境界)」節を追加
- `docs/dev-rules/coding-rules.md` 推奨に「複数 tier が共有する算出規則」を追加
- `docs/impl/latest/impl-config.yaml` と `.github/workflows/ci.yml` の lint を `bin/*` 対象に拡張
- `.github/workflows/ci.yml` tdd ジョブに PostgreSQL バイナリの PATH 配線を追加
- `CLAUDE.md` テスト規約・検証コマンドに同内容を反映
