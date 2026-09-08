---
schema_version: distillery.feedback-request/v1
feedback_id: 20260908_slot_status_wording
created_at: 2026-09-08T10:00:00+09:00
source: distillery-impl
uc_id: c770d8f0
---

## CR-c770d8f0-019: 条件「slot 実行の状態導出規則」の管理 DB 側の文言を Spec の限定記述に揃える

- severity: improvement
- related_ids: [REQ-003, REQ-005, REQ-010]
- related_files: [docs/rdra/latest/条件.tsv]

### 観測した事実

RDRA 条件「slot 実行の状態導出規則」は「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」と書いている。一方、feedback `20260907_abort_consistency` で確定した条件「中止済み run の比較依頼作成除外」は slot_executions.status を「ファイル正本 aborted.txt のミラー」と定め、USDM SPEC-005-02 の受け入れ条件(中止後に実装が走り切って完了通知を送っても速報比較依頼を作らない)は、その経路で管理 DB の slot_executions.status が ABORTED のまま残ることを前提にしている。Spec(rdb-schema.yaml の slot_executions.status、CLI 契約 shared_rules.exitcode_to_status.slot_execution、UC「実装スクリプトを実行して Runner Result を出力する」)は「slot_executions.status は aborted.txt / exitcode.txt 公開時の条件付き UPDATE(WHERE status='RUNNING')で一度だけ終端値を書き、abort 後に exitcode.txt が公開されても ABORTED のまま残す(導出値へ再同期しない)」と明記済み(rdra-feedback #16、todo DIST-029)。

### 現在の仕様と問題

abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した経路では、ファイル正本の導出値(exitcode.txt 優先 = SUCCEEDED / FAILED)と管理 DB(ABORTED のまま)が一致しない。RDRA の「同じ状態を保持する」という文言はこの経路で成り立たず、正本間に文言差が残る。実装は Spec の記述だけで閉じるが、次回以降の反証レビューで同じ差分が再指摘される。

### 変更してほしいこと

- 条件「slot 実行の状態導出規則」の「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」を次に改める: 「速報クロスチェック有効時は、管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した場合、管理 DB は ABORTED のまま残し、ファイル正本の導出値(exitcode.txt 優先)へ再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料として使う」。
- 判定表の説明(縦軸 exitcode.txt、横軸 aborted.txt)は変更しない。
- USDM の該当 SPEC(REQ-003 配下の Runner Result 出力、または REQ-005 配下の SPEC-005-02)に「Given abort-blue で ABORTED にした slot の実装が走り切って exitcode.txt を公開した When 管理 DB を確認する Then slot_executions.status は ABORTED のままである」を受け入れ条件として追加する(既存の同旨の受け入れ条件があれば重複させない)。
- 下流(arch の E-014 二重マッピング説明、spec の該当記述)は既に同じ内容を持つため、文言参照の追従のみでよい。

### 完了条件

- 条件.tsv の「slot 実行の状態導出規則」に「同じ状態を保持する」の表現が無く、条件付き更新と ABORTED 据え置きが明記されている。
- USDM に上記の受け入れ条件が存在する。
- spec の rdra-feedback.md から #16 が解消済みになっている。
