# nfr digest index

- source: `nfr/latest/nfr-grade.yaml`
- source_sha256: `02bb857be42015520e925f0386818e1515b6015abfe2e0df0bd34bbaaafbef2d`
- generated_by: `buildDigest.js`（派生物。正本の sha256 と各 file の sha256 が一致するときだけ有効。不一致なら再生成する）

| section | file | name | lines | bytes | status | file_sha256 |
|---|---|---|---:|---:|---|---|
| `model_system` | `_digest/model_system.yaml` | - | 3 | 424 | ok | `ff7038aaced4efd93bf73673a5c4af3b12a75116d2edd7d299f049afab79c727` |
| `categories[id=A]` | `_digest/category-A.yaml` | 可用性 | 171 | 9615 | ok | `407b262930fcae4922158240e271a12c5773b1ba47013eaf96a35a0012cab614` |
| `categories[id=B]` | `_digest/category-B.yaml` | 性能・拡張性 | 179 | 17486 | ok | `79f42bed23c8ccfadd52467ee2210ff644f85ed04c379a53ce6097e870c44f9c` |
| `categories[id=C]` | `_digest/category-C.yaml` | 運用・保守性 | 241 | 18520 | ok | `2702c392908759e182487fefc2240e0f6d06d3936121cc3226e7abe565f6ad48` |
| `categories[id=D]` | `_digest/category-D.yaml` | 移行性 | 118 | 5495 | ok | `0fda8a1e98303fa7bfe27117ab7b5944712d4159a176e2625f6e272fe5c16570` |
| `categories[id=E]` | `_digest/category-E.yaml` | セキュリティ | 272 | 14369 | ok | `a6ffbdf7ba466fddf8d98b810ba3c7ac5fbdc0e3656256e2827f333c2f3ef2b7` |
| `categories[id=F]` | `_digest/category-F.yaml` | システム環境・エコロジー | 158 | 8774 | ok | `599b9e651b1f2ec2a92646c43dbcb94e727bd4287e3a8396eda30dbf0fdc5acd` |

読み方: 必要な section の file だけを読む。`not_applicable` は正本にセクションが無い（元ファイルを読みに行かない）。
nfr の `name` 列はカテゴリ名（id ↔ 名前の対応はここで確認する）。
