# 実 PostgreSQL の実体テストはテストファイルごとの一時インスタンスで行う

## 何が起きたか

独立検証で「正本は実 PostgreSQL なのに SQLite 経路しか実行できず、`SELECT ... FOR UPDATE` が検証されていない」と blocker 判定された(attempt 5 F-001)。モックや SQLite では行ロック・単一リクエストの rollback 挙動を検証できない。

## 原因

PostgreSQL を常駐サービスとして前提にするとローカル・CI で再現性が無く、逆に SQLite へ寄せると仕様の契約(FOR UPDATE、transaction 規則)を検証できない。

## 回避方法

bats の `setup_file` で `initdb` + `pg_ctl` による一時インスタンス(`127.0.0.1` の空きポート、`log_statement=all`)を起動し、`teardown_file` で `pg_ctl -m immediate stop` する。`RELAYGATE_TEST_PG_BACKEND=docker` で `postgres:16-alpine` に切り替えられるようにする。DDL は rdb-schema.yaml から生成器(`facade/test/fixtures/generate-postgresql-schema.py`)で作り、fixture の冒頭に正本を明記する。statement ログを読んで `FOR UPDATE` の発行と単一リクエスト性を assert する。環境不足時は skip ではなく fail にし、明示 skip(`RELAYGATE_TEST_SKIP_PG=1`)だけを許す(暗黙 skip は「通った」と誤認される)。

## 次回の対応

- datastore 所有 tier が migration を整備したら、fixture 生成を migration 適用へ切り替える
- CI の tdd job で PostgreSQL バイナリ(ubuntu runner は `/usr/lib/postgresql/<ver>/bin`)を PATH に載せる
- 他 tier(worker)の実体テストでも同じ setup_file パターンを共有する
