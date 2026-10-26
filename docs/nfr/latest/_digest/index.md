# nfr digest index

- source: `nfr/latest/nfr-grade.yaml`
- source_sha256: `0283ce5aa1c4ada1b8836ec191174c23e526e329f29bc266dcc8d2137ea3accf`
- generated_by: `buildDigest.js`（派生物。正本の sha256 と各 file の sha256 が一致するときだけ有効。不一致なら再生成する）

| section | file | name | lines | bytes | status | file_sha256 |
|---|---|---|---:|---:|---|---|
| `model_system` | `_digest/model_system.yaml` | - | 3 | 424 | ok | `a5338513604458ed372e1507aa9ef6c7d8338bf2c8082bc291f23a038b9c5501` |
| `categories[id=A]` | `_digest/category-A.yaml` | 可用性 | 171 | 9615 | ok | `89658326431d731a520afe715cc2a300ab598908f2fea7a8ccff4de15df55d50` |
| `categories[id=B]` | `_digest/category-B.yaml` | 性能・拡張性 | 179 | 12390 | ok | `b20866ab3b51f348ef2477e7ccf6a12df39a53146994809ce16706dfb34f1bb7` |
| `categories[id=C]` | `_digest/category-C.yaml` | 運用・保守性 | 241 | 16846 | ok | `9cd81484ac48d63a4a79286771248d7515e6c4d27de729a24509c568c6d5c11d` |
| `categories[id=D]` | `_digest/category-D.yaml` | 移行性 | 118 | 5495 | ok | `5e4a84deaac0f7f330f1a9485ef33fb74af6ed8753554364e132289b14df788c` |
| `categories[id=E]` | `_digest/category-E.yaml` | セキュリティ | 272 | 13121 | ok | `15d28f4b380c97d5ee01e6fc3f639b494b8de206f297b7a33cde8860ab660274` |
| `categories[id=F]` | `_digest/category-F.yaml` | システム環境・エコロジー | 158 | 7892 | ok | `b6f252c029b3e90fb3bd8f1132f0b3934f3952fe5fb5afaf6c09dd23f7815ac9` |

読み方: 必要な section の file だけを読む。`not_applicable` は正本にセクションが無い（元ファイルを読みに行かない）。
nfr の `name` 列はカテゴリ名（id ↔ 名前の対応はここで確認する）。
