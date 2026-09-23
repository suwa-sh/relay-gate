# nfr digest index

- source: `nfr/latest/nfr-grade.yaml`
- source_sha256: `5a7c72400cfc8c65de278dc284e656a73d60b643a91f69ecfa44688a0824b653`
- generated_by: `buildDigest.js`（派生物。正本の sha256 と各 file の sha256 が一致するときだけ有効。不一致なら再生成する）

| section | file | name | lines | bytes | status | file_sha256 |
|---|---|---|---:|---:|---|---|
| `model_system` | `_digest/model_system.yaml` | - | 3 | 424 | ok | `1547245e2f47c8205d2418b9354e73cd65f5aba2a6eabdb2c4e7a5a89b2b19ec` |
| `categories[id=A]` | `_digest/category-A.yaml` | 可用性 | 171 | 9615 | ok | `58786e5e213111cb8aa4ed18f5a91328c1b98c04e6a57daba04e491f151ac30a` |
| `categories[id=B]` | `_digest/category-B.yaml` | 性能・拡張性 | 179 | 12197 | ok | `8e67538c894df340bf9e06a1c3d754c9f1e70644cca73ca30483acf75cbec6b6` |
| `categories[id=C]` | `_digest/category-C.yaml` | 運用・保守性 | 241 | 16925 | ok | `724df9e8484138af6eba8b18e0c9f06ff9e8c5d01942a0f3e474d9fca5fba31f` |
| `categories[id=D]` | `_digest/category-D.yaml` | 移行性 | 118 | 5495 | ok | `2b5422e45e8c1280500acddde6aea8e805b77b9532d69b9062809b8eae29a124` |
| `categories[id=E]` | `_digest/category-E.yaml` | セキュリティ | 272 | 13121 | ok | `6a7e4be5d1b9514ef750f979d6b4609a49fc7b2e54d4f8bde99f93c7deed8c50` |
| `categories[id=F]` | `_digest/category-F.yaml` | システム環境・エコロジー | 158 | 7913 | ok | `c068278ba48a97daae2712bfae4a0cd5cd35fba78ecb89ab962a9a81022ce639` |

読み方: 必要な section の file だけを読む。`not_applicable` は正本にセクションが無い（元ファイルを読みに行かない）。
nfr の `name` 列はカテゴリ名（id ↔ 名前の対応はここで確認する）。
