# サンドボックス検証環境では PostgreSQL の実体テストが環境失敗になる

## 何が起きたか

attempt 6 の初回独立検証(codex サンドボックス)で、`bats facade/test` が 3 回とも `facade/test/6078c4ed_select_slot_postgresql.bats` の setup_file で `IO::Socket::INET: Operation not permitted` となり exit 1 になった。`initdb` 単体も `could not create shared memory segment: Operation not permitted` で起動できなかった。実装起因ではないが、TDD gate が赤のため S5 が fail と記録された(後に環境起因として invalidated)。

## 原因

サンドボックスが loopback TCP socket の作成と SysV shared memory を禁止している。PostgreSQL の起動にはその両方(または Unix socket + shm)が必要であり、テストは環境不足を skip ではなく fail にする設計だった。

## 回避方法

- verifier の gate 再実行は、loopback socket と shared memory を許可する環境(ローカル、docker 可の runner)で行う
- 環境失敗と実装失敗を findings 上で区別する(`environment_failures` 節、`not_verified_environment` ステータス)。環境失敗を blocker に数えない
- PostgreSQL テストに `docker` backend を用意しておくと、サンドボックスでも docker が使えれば回避できる

## 次回の対応

- verifier 起動時に検証環境の前提(socket / shm / docker の可否)を事前 probe し、満たさない場合は最初から環境外で実行する
- 環境起因で fail した done / findings は `invalidated/` に退避し、環境を変えた再検証の結果だけを正として残す
