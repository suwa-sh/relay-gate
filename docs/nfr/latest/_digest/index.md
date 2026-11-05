# nfr digest index

- source: `nfr/latest/nfr-grade.yaml`
- source_sha256: `71b7a2b971a9c5b57f2bbe1cfc360f3662d928ea9bb4be34af9396d49d74ac37`
- generated_by: `buildDigest.js`（派生物。正本の sha256 と各 file の sha256 が一致するときだけ有効。不一致なら再生成する）

| section | file | name | lines | bytes | status | file_sha256 |
|---|---|---|---:|---:|---|---|
| `model_system` | `_digest/model_system.yaml` | - | 3 | 424 | ok | `49a6295dc3676470eaae808775de6032f2a72cdfbb9d7d248b323a87ffb6e7ff` |
| `categories[id=A]` | `_digest/category-A.yaml` | 可用性 | 171 | 9615 | ok | `dd4b77e3a8195c8da4809865b71307b6a45791e35070cd5f206b40e6c13d9324` |
| `categories[id=B]` | `_digest/category-B.yaml` | 性能・拡張性 | 179 | 14584 | ok | `50cb26c0c2dd96e0815486fc3324656f478c0fa78e4c658acfbe012e5b25141e` |
| `categories[id=C]` | `_digest/category-C.yaml` | 運用・保守性 | 241 | 18520 | ok | `b48b23384317c1c327f8af12a0e56b8884f3233d754f80891753988085274a34` |
| `categories[id=D]` | `_digest/category-D.yaml` | 移行性 | 118 | 5495 | ok | `fb93127a7f5c45e487058967fa7a6bbf64cb06446bf0990a3b47a4f1eddca315` |
| `categories[id=E]` | `_digest/category-E.yaml` | セキュリティ | 272 | 14369 | ok | `9b764e54a459004efbaf67aa746a3b82d858948da42e404012cbc359d912d155` |
| `categories[id=F]` | `_digest/category-F.yaml` | システム環境・エコロジー | 158 | 8774 | ok | `b27c095f111fda336c40a080ff84bb464658c3b799c8bda88ea7c185ceb3244f` |

読み方: 必要な section の file だけを読む。`not_applicable` は正本にセクションが無い（元ファイルを読みに行かない）。
nfr の `name` 列はカテゴリ名（id ↔ 名前の対応はここで確認する）。
