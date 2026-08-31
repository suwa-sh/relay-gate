# Step4-Review(データストア系)

- レビュー対象: `_cross-cutting/datastore/rdb-schema.yaml`(7 テーブル)
- KVS / Object Storage: 未使用のため `kvs-schema.yaml` / `object-storage-schema.yaml` が無いのは正常
- 照合元: 全 32 UC の `_model-summary.yaml`、`docs/rdra/latest/情報.tsv` / `状態.tsv` / `バリエーション.tsv`、`_inference.md` 採用値 #3 / #7 / #8 / #9 / #11、`datastore-rules.md`

## 検証結果サマリ

| 観点 | 結果 |
|---|---|
| 1. _model-summary の tables / columns / operations 反映 | 32 UC の全 tables・全 operation 列を機械照合。テーブル欠落 0、列欠落 1(`finished_at`。schema 側で `completed_at` に統一済み、UC 側が未追従)。used_by の UC・operations は全テーブルで一致 |
| 2. description / index name / snake_case | 全テーブル・全 71 列に description あり。全 11 インデックスに name あり(`uq_` / `idx_` 規約準拠)。snake_case 違反なし |
| 3. ユニーク制約 | rapid_crosscheck_requests(run_id PK)、comparison_results(run_id, comparison_type)、slot_executions(run_id, slot)PK、monitor_records(run_id, role)PK、claim 用 worker_id / lease_until の 2 依頼テーブル完備。final の (business_date, catalog_version) は不採用理由が `_review_notes` に記録済み |
| 4. FK と 情報.tsv 関連情報 / 速報・確報分離 | 情報.tsv の関連どおり。final_crosscheck_requests は FK なし(分離維持)。monitor_records / comparison_results→parallel_runs の FK 不採用は理由記録済み |
| 5. 状態 enum | parallel_runs / slot_executions / 依頼 2 種 / rapid_runs.completion_status / monitor_status の 6 系統すべて 状態.tsv と採用値 #11 の英字コードに一致。comparison_results.status(OK / NG / FAILED)はバリエーション「比較結果ステータス」と一致。terminal 判定用の `completed_at` / `alerted_at` / `judged_at` あり |
| 6. er_diagram | 7 テーブル・5 FK(自己参照含む)を全て含む。`npx md-mermaid-lint` で構文 OK |
| 7. validateRdbSchema.js | PASS(下記) |

### validateRdbSchema.js 実行結果

```
PASS: .../_cross-cutting/datastore/rdb-schema.yaml
  tables: 7
  - parallel_runs: 8 columns, 2 indexes
  - slot_executions: 9 columns, 1 indexes
  - rapid_runs: 8 columns, 0 indexes
  - rapid_crosscheck_requests: 12 columns, 2 indexes
  - comparison_results: 7 columns, 2 indexes
  - final_crosscheck_requests: 13 columns, 2 indexes
  - monitor_records: 12 columns, 2 indexes
```

## 指摘一覧

| # | severity | ファイルパス | 行 / 節 | 指摘内容 | 具体的な修正案 |
|---|---|---|---|---|---|
| 1 | major | `実装切替業務/実装切替ジョブ実行フロー/実装スクリプトを実行して Runner Result を出力する/_model-summary.yaml`(同 UC の `spec.md` / `tier-facade.md`)、`実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md` L120 | slot_executions の UPDATE 列 / データモデル変更表 | schema は `_review_notes` で終了時刻列を `completed_at` に統一したが、UC 側 4 ファイルは `finished_at` のまま。rdb-schema.yaml に存在しない列名を実装者が tier-facade.md から読むため、UC spec とデータストア正本が食い違う | UC 側の `finished_at` を `completed_at` に置換する(schema 側は変更不要)。Step4 の整合修正として UC spec 4 ファイルを更新する |
| 2 | minor | `_cross-cutting/datastore/rdb-schema.yaml` | slot_executions / `idx_slot_executions_status_mode`(L167-174) | `reason` は「hang-detector が未完了 background slot を走査」だが、UC「background 実行の経過時間と終了状態を判定する」の _model-summary / spec / tier-ops は slot_executions を参照しない(started-at.txt / exitcode.txt のファイル走査)。`used_by` の 3 UC(runner 起動 2 件は INSERT のみ、判定 UC はテーブル未使用)も実際の利用者ではなく、abort の条件付き UPDATE は主キーで賄える。利用者不在のインデックス | (a) hang-detector が on 時に slot_executions を走査する設計にするなら、判定 UC の _model-summary に SELECT(`status='RUNNING' AND mode='background'`)を追加して整合させる。(b) ファイル走査を正とするならインデックスを削除し、`_review_notes` に「不採用: 走査は成果物ファイル、abort は主キー」と記録する |
| 3 | minor | `_cross-cutting/datastore/rdb-schema.yaml` | parallel_runs / `idx_parallel_runs_job_id_requested_at`(L93-98) | `used_by` の「slot 実行モードを選択して runner を起動する」は INSERT / run_id 主キー UPDATE のみで、(job_id, requested_at) 検索を行う UC は 32 UC のどこにも無い。reason「運用者調査」は UC に紐付かない | 運用調査用途を残すなら `used_by` を空にし reason に「UC 由来ではない運用者アドホック検索」と明記する。datastore-rules の「不要なインデックスを防ぐ」に従うなら削除する |
| 4 | minor | `_cross-cutting/datastore/rdb-schema.yaml` | rapid_crosscheck_requests / `idx_rapid_crosscheck_requests_status_requested_at`(L316-319) | `used_by` の「速報比較依頼だけを新規作成する」は INSERT のみで当インデックスを使わない | used_by から当該 UC を外す(claim UC と hang-detector 判定 UC は正しい) |
| 5 | minor | `_cross-cutting/datastore/rdb-schema.yaml` | final_crosscheck_requests / `_review_notes` L24、`idx_final_crosscheck_requests_status_requested_at` reason | (business_date, catalog_version) を非ユニークとする理由は再実行経路として妥当だが、datastore-rules の「状態遷移の整合性(アクティブ状態の部分ユニーク)」の検討が記録されていない。同一 business_date + catalog_version の依頼が未終端(REQUESTED / CLAIMED / RUNNING)のまま 2 件並走すると全量比較が二重に走る | 不採用でもよいが、`_review_notes` に「未終端の部分ユニーク(status NOT IN 終端値)を検討し、正規ジョブ再実行はジョブスケジューラ側の重複起動抑止に委ねるため不採用」等の判断を追記する。採用する場合は UC「確報比較依頼を登録して終端状態まで待機する」の INSERT に重複時の終了コード契約を追加する |
| 6 | minor | `_cross-cutting/datastore/rdb-schema.yaml` | monitor_records / `target_type`(L513-516) | `target_type` は `role` から一意に決まる(blue / green → background_slot、rapid-crosscheck → rapid_request)ため、3NF 上は role への推移従属。情報.tsv の属性「監視対象種別」を写したものなので保持自体は許容 | 保持するなら description に「role から導出可能。集計・表示の可読性のため保持(非正規化)」と根拠を追記する。削減する場合は列を落とし、表示側で role から導出する |
| 7 | minor | `実行監視業務/background 実行監視フロー/監視記録を保存する/tier-ops.md` L72 / 同 `_model-summary.yaml` | インデックス記述 | schema は `(job_id, role, judged_at)` を採用し理由を `_review_notes` に記録済みだが、UC 側は `(job_id, role, alerted_at)` のまま | UC 側の記述を `(job_id, role, judged_at)` に更新する(#1 と同じ UC 側未追従) |

## 集計

| severity | 件数 |
|---|---|
| blocker | 0 |
| major | 1 |
| minor | 6 |

rdb-schema.yaml 単体は validator PASS・enum / FK / ユニーク制約 / ER 図とも入力と整合しており、正本として採用可能。major #1 と minor #7 は schema 側で解決済みの列名・インデックスの決定が UC spec 側に反映されていない「UC 側未追従」であり、修正先は UC ファイル。
