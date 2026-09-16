# contract: management-db(rdb-schema)

contract-codegen: from rdb-schema.yaml scope={parallel_runs, slot_executions, rapid_runs, rapid_crosscheck_requests, comparison_results, final_crosscheck_requests, monitor_records}

- source: `specs/latest/_cross-cutting/datastore/rdb-schema.yaml`(specs_root 相対)
- provider: `tier-ops` / consumers: `tier-facade`, `tier-rapid-crosscheck`, `tier-final-crosscheck`
- 生成物(直接編集禁止。再生成は bootstrap P4 / S3):
  - `management-db.sh`: テーブル名(`RG_TABLE_*`)・主キー(`RG_PK_*`)・列名(`RG_COL_*`)・列挙値(`RG_ENUM_*` / `RG_{TABLE}_{COL}_{VALUE}`)の bash 定数
  - `schema.json`: scope 範囲のテーブル定義の機械可読コピー(step 定義 JS / テスト用)
- DDL / migration は生成しない。正本は datastore_owner(tier-ops)の `ops/migrations/`
