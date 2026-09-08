# 変更の正本(change-brief): event 20260908_024000_feedback_slot_status_wording

- feedback request: 20260908_slot_status_wording(CR-c770d8f0-019。causal work unit CR-c770d8f0-019#1。direct なし)
- 利用者決定: 2026-09-08 DIST-029 A(CR 本文に明記。そのまま採用)
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording, arch:20260908_015000_feedback_slot_status_wording
- 性質: 文言追従のみ。実装挙動は不変

## D1: RDRA 条件「slot 実行の状態導出規則」の管理 DB 側文言への参照統一

- 旧文言「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」の引用を除去し、新文言(管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort 後に実装が走り切って exitcode.txt を公開しても ABORTED のまま残し再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料)に揃える
- 用語: 「判定キー」→「判定材料」、「終端値を書く」→「公開時点の状態を書く」、USDM 参照は SPEC-005-02 AC6 / AC9
- 反映先: rdb-schema.yaml(slot_executions / status)、cli-command-contract.yaml(shared_rules.exitcode_to_status.slot_execution)、ui-design.md、buc-spec(実装切替ジョブ実行フロー)、UC「実装スクリプトを実行して Runner Result を出力する」(spec / tier-facade / _model-summary)、UC「両系成功時に速報比較依頼を作成する」(spec / tier-rapid-crosscheck)、UC「実行を ABORTED へ遷移させる」(spec)
- 「仮採用」「rdra-feedback #16」注記は除去(RDRA へ反映済みのため確定規則として記載)

## D2: USDM SPEC-005-02 AC9 の BDD シナリオ追加

- UC「両系成功時に速報比較依頼を作成する」spec.md に「abort-blue で ABORTED にした slot の実装が走り切って exitcode.txt を公開しても slot_executions.status は ABORTED のままである(SPEC-005-02)」を追加
- 関連 RDRA モデル表に条件「slot 実行の状態導出規則」(参照のみ)を追加

## D3: マトリクスと rdra-feedback の再計算

- usdm-acceptance-matrix: 受け入れ条件 121 → 122(SPEC-005-02 が 8 → 9)。振る舞い SPEC の対応率 49 / 49 = 100% 維持
- traceability-matrix: 380 / 380 = 100.0%(分母不変。条件「slot 実行の状態導出規則」の対応 UC に UC-09 を追記)
- rdra-feedback.md: #16 を解消済みへ。残存は SR-001 / SR-002(スキル側の変更要求)のみ
- `_inputs-digest.md` は arch 20260908_015000 / nfr 20260907_120000 から再生成
