# 推論根拠サマリ

- event_id: 20260819_110531_arch_comparison_definition_exitcode
- 入力: docs/rdra/latest/（20260819_104301_slot_config_comparison_def_exitcode 反映後）, docs/nfr/latest/nfr-grade.yaml（20260817_144844_initial_nfr）, docs/arch/latest/arch-design.yaml（20260818_135504_arch_slot_config_attempt_identity）

## work unit ごとの判定

### CR-6078c4ed-008#1（slot別実行設定の分離・attempt identity・実行状態 6 値）

- RDRA 情報.tsv / 状態.tsv の更新内容（execution-spec.json の run 共通化、slot別実行設定の独立、attempt_id / attempt_no / accepted_at、実行状態 STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED、STARTING/UNKNOWN 遷移）は、arch イベント 20260818_135504 の定義そのものであり、BC-001 ユビキタス言語・AG-001 / AG-002 不変条件・E-001 / E-002 / E-007 の属性は既に同一内容で整合していた。
- ただし RDRA 側で「slot別実行設定」が独立した情報エンティティとして立ったため、E-007 の source_info が旧 RDRA 名（execution-spec.json）を指したままだと RDRA 情報の網羅判定で未カバー扱いになる。設計内容は変えず、source_info の参照先のみを「情報: slot別実行設定」へ整合させた。

### CR-6078c4ed-009#1（比較定義エンティティの追加）

- RDRA 情報.tsv に新コンテキスト「クロスチェック定義管理」の情報「比較定義」（JOB_ID / 比較対象テーブル / 比較対象ファイル / 比較実装識別子 / 有効期間）が追加された。arch には対応するエンティティ・BC が存在せず、データアーキテクチャ・ドメインアーキテクチャの両方に追加が必要だった。
- BC 分離の根拠: 比較定義は世代（有効期間）で管理されるマスタ定義であり、実行トランザクションである速報比較依頼（BC-002）・確報比較依頼（BC-003）とはライフサイクルも変更契機も異なる。速報・確報の双方が同じ定義を参照するため、どちらか一方に所有させると他方が内部モデルへ依存する。両者の上流に置き OHS + Published Language で公開する形（CM-005 / CM-006）とした。
- サブドメインは新設せず SD-002（クロスチェック検証）に所属させた。RDRA に対応する BUC が無く、独立した業務フローを持たない参照専用コンテキストであるため（owned_buc_ids は空）。
- model_type は resource_scd2。同一 JOB_ID に複数世代を持ち、実行時点で 1 件を解決する要件が有効期間そのものであるため。PK は job_id + valid_from。
- storage は rdb。有効期間の重複禁止（AG-006 不変条件）をトランザクション整合性で担保する必要があり、RDB を管理 DB とする既定方針とも合致する。

### CR-6078c4ed-010#1（終了コード透過と relay-gate エラーの退避終了コード）

- RDRA 条件.tsv に「relay-gateエラーの退避終了コード」（未確定・取得不能・中止済み = 125、バリデーションエラー = 124、bash 予約 126/127 と非衝突、foreground の exitcode.txt は 0 を含む全値を透過）が追加された。arch 側は SP-002 が「終了コードのみを応答」とだけ述べており、透過の範囲と relay-gate 自身のエラーの表現方法が未定義だった。
- 応答契約は facade ティアの責務であるため、tier-facade に規則 SR-006 を追加し、SP-002 に透過方針を明記した。UNKNOWN を推測で FAILED 相当へ変換しない点は AG-002（timeout 後は UNKNOWN、推測で FAILED を確定しない）と同一方針であり、退避コード 125 に UNKNOWN / ABORTED を含める形で整合させた。
- relay-gate エラー時の stderr は、取得可能な場合の foreground stderr.log と relay-gate 自身のエラー内容（原因・次アクション）を併記する。障害調査担当者が応答だけで一次切り分けできることを優先した。

## 網羅率

- RDRA 網羅率: 25/25（100%）。追加された情報 2 件（slot別実行設定・比較定義）と条件 1 件（relay-gateエラーの退避終了コード）を含む
- NFR 網羅率（重要メトリクスのみ）: 44/44（100%）
