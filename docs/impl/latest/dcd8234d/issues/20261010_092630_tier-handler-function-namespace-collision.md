# validate-config.sh が source する tier handler の関数名が衝突する

- uc_id: dcd8234d
- 起票: tier-rapid-crosscheck S4 attempt 2(2026-10-10)
- 種別: 仕様どおりに実装すると動かない事実(dev-rules / 契約の不足)

## 仕様の記載

- tier-rapid-crosscheck.md / tier-final-crosscheck.md「変更概要」: validate-config.sh の本体は tier-facade が所有し、
  各 tier はサブ検証の関数を提供する(bash の source で直接依存。CLP-003)
- facade/src/presentation/validate-config.sh は `rapid-crosscheck/src/presentation/validate_config_crosscheck_job_map.sh` と
  `final-crosscheck/src/presentation/validate_config_target_catalog.sh` を**同じシェルに**順に source する
- docs/dev-rules/(coding-rules / tier-rules)と契約(cli-command-contract.yaml)には、tier が source されるときの
  関数名・グローバル変数名の名前空間(接頭辞)の規則が無い

## 実装で判明した事実

- tier-rapid-crosscheck(attempt 2)が repository に `target_catalog_repo_load` を定義したところ、
  tier-final-crosscheck の `final-crosscheck/src/repository/target_catalog_repo.sh` にも同名の関数があり、
  後から source される final-crosscheck 側の定義で上書きされた(戻り値の意味が異なるため、
  `--crosscheck-job-map` の対象カタログ参照の解決が終了コード 6 になった)
- 本 tier 側は関数名・定数名に tier の接頭辞(`crosscheck_target_catalog_repo_*` / `CROSSCHECK_TARGET_CATALOG_*`)を付けて回避した。
  両 tier のトップレベル名(関数・グローバル変数)に他の衝突が無いことは `comm` で確認した
- 衝突は bash が黙って上書きするため、lint(shellcheck)でも単体テスト(tier 単独で source)でも検出されない。
  実プロセス(facade/bin/validate-config.sh)経由のテストでだけ現れる

## 提案

1. dev-rules(tier-rules.md「全種別共通」または coding-rules)に、同じプロセスに source される tier 間で
   関数名・グローバル変数名に tier 固有の接頭辞を付ける規則を追加する
   (例: tier-rapid-crosscheck は `crosscheck_` / `CROSSCHECK_`、tier-final-crosscheck は `final_` / `FINAL_`。
   tier-facade の共有関数は `job_map_*` / `cli_field_*` / `csv_*` のまま)
2. facade の validate-config.sh が handler を source した後に、所有 tier ごとの関数名の衝突を検出する
   ゲート(例: 各 tier の `declare -F` の差集合を比較するスクリプト)を統合テストに加える
3. 当面は本 issue を根拠に、tier-rapid-crosscheck の新規の関数名・定数名に接頭辞を付ける
