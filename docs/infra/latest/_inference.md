# 推論根拠

## 入力

- USDM イベント: 20261101_101000_feedback_impl_feedback_dcd8234d(SPEC-004-04 の設定検証を 3 点に。受け入れ基準 10 の Given を絞り、{params} 位置違反の基準を 1 件追加)
- arch フィードバックイベント: 20261101_103000_feedback_impl_feedback_dcd8234d(CTR-007 の説明文の検証項目列挙を 3 点に。ティア構成・依存・配置は不変)
- RDRA / NFR: 今回は no-change

## 影響の調べ方

`docs/infra/latest/` を `params` / `validate-config` / `job_id` / `起動コマンド` / `CTR-007` / `検証項目` で横断検索した。

| 箇所 | 内容 | 判断 |
|---|---|---|
| product-impl-onprem.yaml の rapid-crosscheck.env 検証規則の説明 | 内容検証を「絶対パスで実行可能・{job_id} を含む」の 2 点で列挙 | 3 点へ更新 |
| ansible config ロールのコメント(final-crosscheck.env 非空検査の直前) | 内容検証を「絶対パスで実行可能・速報は {job_id} を含む」の 2 点で列挙 | 3 点へ更新 |
| product-impl-onprem.yaml の final-crosscheck.env 検証規則の説明 | 内容検証は「絶対パスで実行可能」のみ | 不変(確報は {job_id} / {params} の検証対象外。要求の 3 点目は速報だけ) |
| _inference.md / _changes.md(前回イベントの履歴記述) | 2 点の列挙を含む | 当時の判断記録のため書き換えない(今回イベントの md で置き換わる) |
| product-input.yaml / workload-model / mapping / conformance | 起動コマンド 1 行の置き場だけを記述し、検証項目を列挙しない | 不変 |

## 判断

- 起動コマンドの内容検証は validate-config.sh(spec)が所有するという分担は変えない。インフラ側の検査は配置物の存在・非空・キー構成・平文認証情報の不在だけで、{params} の位置を検査する処理は追加しない
- translation のフィールドは変わらないため、MCL product-design の全量再実行と product-input の再生成は不要
- 検証項目の正本は要求と CLI 契約。インフラ設計の括弧書きは参照用の列挙なので、上流と食い違わないよう 3 点にそろえる
