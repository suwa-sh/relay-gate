# infra イベント変更サマリ

- event_id: `20260907_124000_feedback_abort_consistency`
- trigger_event: `arch:20260907_122000_feedback_abort_consistency, nfr:20260907_120000_feedback_abort_consistency`
- created_at: 2026-09-07T12:40:00Z
- 種別: 差分更新(infra-event-diff.yaml。前イベント `20260907_021000_feedback_todo_followup`)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項(2026-09-07 DIST-025 A / DIST-026 A / DIST-027 A)は決定を採用。確認推奨項目は完了報告で返却)
- feedback request: 20260907_abort_consistency(direct work unit: なし。causal work unit: CR-c770d8f0-016#1, CR-c770d8f0-017#1, CR-c770d8f0-018#1。packet: docs/pipeline/feedback-runs/20260907_abort_consistency/stage-packets/infrastructure.md)

```yaml
feedback_request:
  feedback_request_id: "20260907_abort_consistency"
  input_sha256: "70cda63f92e887e459a3817580e45a840e3ff201065a534085ad113fb8910b81"
  request_ids: ["CR-c770d8f0-016","CR-c770d8f0-017","CR-c770d8f0-018"]
  work_unit_ids: ["CR-c770d8f0-016#1","CR-c770d8f0-017#1","CR-c770d8f0-018#1"]
```

## MCL 再実行の判断

- translation(workload_type / availability_tier / latency_target_p99 / data_classification / traffic_pattern_type / consistency_model / cost_posture / target_clouds)は無変更
- 影響は管理 DB の実装仕様(条件付き UPDATE の対象状態と更新件数の扱い)、観測仕様の診断専用事象とアラート対象外の範囲、適合性検証への REQ-DB-006 追加、構成図の辺の説明に限られる
- したがって mcl-product-design の全量再実行はスキップし、MCL 出力を対象箇所だけ更新した(前回 20260907_021000 と同じ判断。ハイブリッド方式: MCL 出力は全量を本イベントに保持し latest へ全量上書き)

## product-input 変更フィールド

- source_refs: `arch-design:20260907_015000_feedback_todo_followup` / `nfr-grade:20260907_013000_feedback_todo_followup` → `arch-design:20260907_122000_feedback_abort_consistency` / `nfr-grade:20260907_120000_feedback_abort_consistency`
- observability_needs.notes: 中止済み run の定義を「並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(aborted.txt 公開済み)」に拡張し(CR-c770d8f0-016)、worker が RUNNING への条件付き UPDATE 0 件で比較を開始しなかった事実も実行ログにのみ残ること、abort-rapid-crosscheck が REQUESTED / CLAIMED / RUNNING を中止できること(確報は RUNNING のみ)を追記(CR-c770d8f0-017)

## MCL 出力ファイル(更新)

- `docs/mcl/product/output/product-workload-model.yaml`(更新): management_db の説明に速報比較依頼の状態遷移(worker の CLAIMED → RUNNING、abort-rapid-crosscheck の 3 状態 → ABORTED、abort-blue / abort-green の REQUESTED → ABORTED)を条件付き UPDATE で行い更新件数で競合を判定する旨を追加。REQ-DB-006「WHERE 句で現在状態を条件にした UPDATE の更新件数を CLI クライアントから取得できる」(must)を追加
- `docs/mcl/product/output/product-mapping-onprem.yaml`(更新): management_db の vendor_feature にコマンドタグ(UPDATE n)による更新件数取得、configuration_notes に 3 種の条件付き UPDATE の 0 件時の扱い(worker: 比較を開始しない / abort-rapid-crosscheck: エラー / abort-blue・abort-green: 正常)と app_rw 権限で足りる旨
- `docs/mcl/product/output/product-impl-onprem.yaml`(更新): management_db の abort_updates を書き直し(abort-rapid-crosscheck: worker 停止確認のうえ status IN ('REQUESTED','CLAIMED','RUNNING')。abort-final-crosscheck: RUNNING のみ。abort-blue / abort-green: REQUESTED。競合窓の保険)、worker_start_update(status = CLAIMED かつ自 worker_id 条件。0 件なら比較ツールを起動せず comparison_result も登録せず正常終了しログに残す)と aborted_run_judgement(parallel_run.status と slot_executions.status を同一トランザクションで読む。テーブル・権限の追加は不要)を追加。validation_rules に psql コマンドタグ UPDATE 0 の取得と分岐(REQ-DB-006)を追加
- `docs/mcl/product/output/product-observability.yaml`(更新): diagnostic_only_events の中止済み run を slot 実行 ABORTED を含む定義に拡張し(foreground 完了後の background 中止が該当)、worker の 0 件終了(run_id / worker_id 付き)を追加。alert-error-rate の対象外事象に abort-rapid-crosscheck による ABORTED 化と worker の 0 件終了を追記し、abort-blue / abort-green の ABORTED 化を競合窓の保険と明記
- `docs/mcl/product/output/product-cost-hints.yaml`(変更なし)
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml`(更新): REQ-DB-006 を conformant で追加(PostgreSQL のコマンドタグ UPDATE n を psql -c の出力から取得)。summary を 25 要件(conformant 20 / partial 5 / non_conformant 0)に更新
- `docs/cloud-context/generated-md/product/relay-gate-target-architecture.md`(更新): ops CLI → 管理 DB の辺を abort-rapid-crosscheck(REQUESTED・CLAIMED・RUNNING 依頼を ABORTED)と abort-blue / abort-green(未着手依頼を ABORTED。保険)に書き直し、rapid runner → 管理 DB の辺に中止済み run 判定(parallel_run と slot_executions)と CLAIMED → RUNNING の条件付き UPDATE を追記。適合性サマリを 25 要件に更新
- `docs/cloud-context/decisions/product/*.yaml`(変更なし。決定記録は履歴として据え置き)
- IaC スケルトン(ansible 5 ロール、inventory 例、terraform)は変更なし(権限・配置ファイル・unit 構成に変更がないため)

## infra-event.yaml 変更フィールド

- event_id / created_at / source / trigger_event / previous_event_ref / feedback_request / arch_event_ref / nfr_event_ref を本イベントへ更新
- mcl_execution.outputs の description に 20260907 中止整合差分の要約を追記(conformance は 25 要件)
- arch_feedback: 据え置き(新規フィードバックなし)

## arch フィードバック

- なし。本イベントの差分はすべて arch 20260907_122000_feedback_abort_consistency の変更(SP-009 / SP-011 / SP-022 / LP-021 / LP-023 / LP-024 / CLP-004 / AG-002 / E-016 / E-017 / E-024)を下流へ追従したもの。REQ-DB-006(条件付き UPDATE の更新件数取得)は LP-021 / LP-024 が既に「更新件数」で判定すると定めており、RDB 製品側の実現手段(psql コマンドタグ)を確認したに過ぎないため arch の記述を変える知見ではない。arch のイベントは作成していない

## 書き戻しチェック

- 不要。arch 差分はティア構成・認証認可方式・DR 方針・外部連携・storage_type を変えておらず(条件付き UPDATE の対象状態と中止済み run の判定キーはアプリケーション規則と管理 DB の実装仕様に閉じる)、product-input の translation フィールドに影響しない

## 照合結果(causal work unit)

| work unit | status | 反映先 / 理由 |
|---|---|---|
| CR-c770d8f0-016#1 | changed | 中止済み run の判定キー(並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)を observability の diagnostic_only_events / alert-error-rate、product-input の notes、impl.database.management_db の aborted_run_judgement(parallel_run.status と slot_executions.status を同一トランザクションで読む。テーブル・権限追加不要)、構成図の rapid runner → 管理 DB の辺へ反映 |
| CR-c770d8f0-017#1 | changed | abort-rapid-crosscheck の対象拡張(REQUESTED / CLAIMED / RUNNING。worker 停止確認と status IN 条件付き UPDATE)、abort-final-crosscheck(RUNNING のみ)、worker の CLAIMED → RUNNING 条件付き UPDATE(0 件なら比較を開始しない)を impl.database.management_db(abort_updates / worker_start_update / 検証規則)、mapping の notes、workload-model の説明と REQ-DB-006、conformance(REQ-DB-006 conformant。25 要件)、observability の対象外事象、product-input の notes、構成図の辺へ反映。既存の app_rw 権限で足り権限設計は変えない |
| CR-c770d8f0-018#1 | changed | abort-blue / abort-green による REQUESTED 依頼の ABORTED 化を「完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」と位置づけ直し、impl.database.management_db の abort_updates、mapping の notes、workload-model の説明、observability の alert-error-rate、構成図の ops CLI → 管理 DB の辺の文言へ反映 |

## 仮採用(confidence: low)

- なし(新規 low は作らない。既存の REQ-OPS-002(組織既存監視の有無。todo DIST-013)は本 CR の対象外で据え置き)

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した。REQ-DB-006 は arch LP-021 / LP-024 の「更新件数で判定する」を RDB 製品の機能要件として明文化したもので、選択肢を伴う判断ではない)
