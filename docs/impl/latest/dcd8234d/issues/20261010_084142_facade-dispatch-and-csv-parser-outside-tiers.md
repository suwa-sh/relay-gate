# validate-config.sh の委譲先登録と CSV 解析関数が本 UC の tier の外(tier-facade)にある(S2 test-scaffold 起票)

- uc_id: dcd8234d(クロスチェックのジョブマップと比較定義を定義する / define-crosscheck-job-map-and-comparison-definitions)
- 起票 stage: S2 test-scaffold
- 種別: 仕様どおりに実装すると本 UC の write-set では動かない事実(S2 の blocker ではない。S3 contracts / S4 tier-impl の着手前に扱いを決める必要がある)

## 仕様の記載

- tier-rapid-crosscheck.md「変更概要」: validate-config.sh の本体は tier-facade が所有し、`--crosscheck-job-map` サブ検証の関数 `validate_crosscheck_job_map` を本 tier が提供する(bash の source で直接依存。CLP-003)
- tier-final-crosscheck.md「変更概要」: 同様に `--target-catalog` の検証ロジック `validate_target_catalog` を本 tier が提供する(契約では uses)
- spec.md「E2E 完了条件」Scenario「…同じ CSV 形式である(SPEC-004-04)」Then: slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われる
- uc-map.yaml(dcd8234d)の tiers: tier-final-crosscheck / tier-rapid-crosscheck のみ(tier-facade を含まない)
- impl-config.yaml の contracts[]: management-db(rdb-schema)のみ。tier-facade と rapid / final 間の関数共有は契約として宣言されていない
- docs/dev-rules/tier-rules.md: 契約に無い tier 間依存が必要になったら実装で直接依存せず issues → feedback で契約宣言を要求する

## 実装で判明した事実

- `facade/src/presentation/validate-config.sh`(UC fd678b04 / eff24f55 の成果物)は、検証種別ごとに `validate_config_<kind>` 関数へ委譲し、関数が未定義なら `error: validation kind is not implemented option=--<kind>`(終了コード 6)を返す。`--crosscheck-job-map` / `--target-catalog` のオプション受理は既に実装されているが、委譲先の関数は未定義である
- 同スクリプトが `source` するファイルは facade/src 配下の固定リストであり、rapid-crosscheck/ / final-crosscheck/ 配下のファイルを読む仕組みは無い。本 UC の tier が関数を提供しても、facade 側の source 行(または拡張フック)を追加しない限り validate-config.sh から呼ばれない
- facade/ は本 UC の tier ではなく、S4 の write-set に含まれない。したがって仕様どおり「本 tier が関数を提供し facade が source する」形は、本 UC の write-set だけでは完結しない
- CSV クォート解析関数(slot ジョブマップの読み込み)も facade/src 配下にある。本 UC の tier から直接 source すると、contracts[] に無い tier 間依存になる
- S2 で置いた TDD(`rapid-crosscheck/test/presentation/validate_config_crosscheck_job_map.bats` / `final-crosscheck/test/presentation/validate_config_target_catalog.bats`)は facade のエントリポイント `facade/bin/validate-config.sh` を実プロセスとして起動する。現時点の fail 理由は上記の終了コード 6(未実装)であり、red baseline として妥当

## 提案

- S3(contracts)またはオーケストレータの判断で、次のいずれかを確定する
  1. 本 UC の S4 write-set に tier-facade の `facade/src/presentation/validate-config.sh` の委譲先登録(source 行の追加)だけを例外的に含める(関数の実体は rapid / final 側に置く。仕様の記述どおり)
  2. facade 側に「`$RELAY_GATE_HOME` 配下の他 tier の検証関数を探索して source する」拡張フックを tier-facade の別 UC(または保守)で先に入れる
  3. uc-map の dcd8234d の tiers に tier-facade を追加する(S1 からやり直し)
- CSV クォート解析関数の共有は、impl-config の contracts[] か S1 の shared_spec_refs に「tier-facade 提供 / rapid・final 消費」として宣言するよう S8 feedback で仕様側へ要求する。宣言されるまで S4 は直接 source せず、本 issue を根拠に暫定の依存(注入箇所にコメント)として扱う
