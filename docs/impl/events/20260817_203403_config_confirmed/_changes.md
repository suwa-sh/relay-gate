# config_confirmed: 実装構成の確定

- 実装 tier: tier-facade(facade/, cli, bash) / tier-worker(worker/, worker, bash)
- 非実装 tier: tier-datastore(共有資産 → datastore_owner: tier-worker) / tier-external-integration(各 tier 内の gateway として実装)
- 契約: relay-gate-db(rdb-schema, provider=tier-worker, consumers=[tier-facade], 全7テーブル)
- ツール: shfmt / shellcheck / bats-core / cucumber-js(JS steps から実 bash プロセスを起動)
- uc-map: 23UC, uc_id 8桁(衝突なし)
- ユーザー承認済み(2026-08-17)
