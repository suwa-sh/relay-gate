# nfr digest index

- source: `nfr/latest/nfr-grade.yaml`
- source_sha256: `69cca2e1c16f18ab4178b5a0e5af690acc7a82338c64a37176767e860a06693f`
- generated_by: `buildDigest.js`（派生物。正本の sha256 と各 file の sha256 が一致するときだけ有効。不一致なら再生成する）

| section | file | name | lines | bytes | status | file_sha256 |
|---|---|---|---:|---:|---|---|
| `model_system` | `_digest/model_system.yaml` | - | 3 | 424 | ok | `bca56d4ca7bb285d7e9d9282c931c854dd9c16858caa1b999edd170dde3d86ab` |
| `categories[id=A]` | `_digest/category-A.yaml` | 可用性 | 171 | 9615 | ok | `698c00f1353d15f6244cb399c54eafda5df95e83c92dbb90aba5cf2b57061961` |
| `categories[id=B]` | `_digest/category-B.yaml` | 性能・拡張性 | 179 | 9900 | ok | `bfeb42ff30f62c86257390c3fa7ac23eb58a77e4a227baf695b6966270655b78` |
| `categories[id=C]` | `_digest/category-C.yaml` | 運用・保守性 | 241 | 16925 | ok | `6e15d83c9b4b238d5a53203c0b5a55db42ea021e0bb695324da3412080024c29` |
| `categories[id=D]` | `_digest/category-D.yaml` | 移行性 | 118 | 5495 | ok | `0fa5bed6197b410ffd1996a783c9ba02954313640a071960db7e1322e5810cce` |
| `categories[id=E]` | `_digest/category-E.yaml` | セキュリティ | 272 | 13121 | ok | `a18a5e3c3bb87a586e6a2149fcc55fe62ec0a1122c720b6e143c94bbc9b42846` |
| `categories[id=F]` | `_digest/category-F.yaml` | システム環境・エコロジー | 158 | 7913 | ok | `ee53c52ec8ea89d76bba61af2c7f2d3ff76624fdab4cfba7b871b76cc4531b34` |

読み方: 必要な section の file だけを読む。`not_applicable` は正本にセクションが無い（元ファイルを読みに行かない）。
nfr の `name` 列はカテゴリ名（id ↔ 名前の対応はここで確認する）。
