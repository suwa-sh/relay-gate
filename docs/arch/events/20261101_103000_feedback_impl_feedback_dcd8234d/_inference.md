# 推論根拠サマリ

- event_id: 20261101_103000_feedback_impl_feedback_dcd8234d
- trigger_event: usdm:20261101_101000_feedback_impl_feedback_dcd8234d, rdra:20261101_101000_feedback_impl_feedback_dcd8234d, nfr:20261101_102000_feedback_impl_feedback_dcd8234d

## causal work unit(CR-dcd8234d-009): 速報の起動コマンドの検証 3 点化

### 入力の確認

- 要求 SPEC-004-04(USDM latest): validate-config.sh が起動コマンドに対して行う検証は 3 点だけ。(1) コマンド部分(先頭の語)が絶対パスで存在し実行可能、(2) 速報の起動コマンドに {job_id} を含む、(3) 速報の起動コマンドで {params} を使うなら引数 1 つ全体がちょうど {params}。{job_id} の有無と {params} の位置のほかは引数部分を検査しない。受け入れ基準 10 の Given を絞り、{params} 位置違反の基準 12 を追加
- RDRA・NFR は変更なし(no-change manifest)

### arch latest の走査

- `validate-config` / `{params}` / `{job_id}` / `2 点` / `絶対パス` で arch-design.yaml と decisions/ を検索
- 該当: CTR-007 の説明の括弧書き「速報の検証は『起動コマンドが絶対パスで存在し実行可能』『{job_id} を含む』の 2 点で、CSV クォート解析を要さないため facade 単独で完結する」。要求と項目数が食い違う
- arch-decision-019 の context にも「2 点」があるが、2026-10-10 時点の決定の文脈記録であり書き換えない
- CLP-003(速報ティアのレイヤー間規則)、E-027 rapid_compare_command、CM-007、worker の SP 群は「{job_id} を含む」「facade 単独で完結」だけを書き、項目数・{params} の位置を前提にしていない

### 推論

- 3 点目({params} の位置)も CSV クォート解析を要さず、速報ティアの関数を共有する必要もないため、委譲撤廃(facade 単独で完結)の結論は維持できる。ティア構成・ティア間依存・レイヤリング・データモデルは変えない
- 食い違いの解消は CTR-007 の括弧書きの更新だけで足りる。再発防止として、検証項目の正本が要求と CLI 契約であり CTR-007 は構成だけを定める旨を明記した
- 方針資料(tmp/RelayGateのしくみ.md / tmp/RelayGateの利用イメージ.md)は validate-config.sh の内部構成・検証項目を定めておらず、本変更と矛盾しない
- 違反時の文言(error: placeholder {params} must be a whole argument ...)と終了コードは CLI 契約・UC ティア仕様の責務で、arch には複製しない
