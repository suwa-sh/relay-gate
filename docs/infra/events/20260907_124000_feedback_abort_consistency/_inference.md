# 変換推論根拠(差分更新 20260907_124000_feedback_abort_consistency)

前イベント `20260907_021000_feedback_todo_followup` の推論根拠を引き継ぎ、本イベントで変更した箇所だけを記す。

## translation(変更なし)

| product-input フィールド | 根拠 | 判定 |
|---|---|---|
| workload_type / availability / latency / data_sensitivity / traffic / consistency / cost_posture / target_clouds | arch 差分 20260907_122000 はティア構成・認証認可・DR 方針・外部連携・storage_type を変えていない(変更は SP-009 / SP-011 / SP-022 / LP-021 / LP-023 / LP-024 / CLP-004 / AG-002 / E-016 / E-017 / E-024 の規則・説明)。NFR 差分 20260907_120000 は grade を据え置き(C.3.3.1 の grade_description / reason / source_model のみ更新) | 無変更。MCL 全量再実行は不要 |

## 要素説明の更新根拠

| 更新箇所 | 上流の根拠 | 起因 CR |
|---|---|---|
| observability / product-input notes: 中止済み run = 並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED(aborted.txt 公開済み) | RDRA 条件「中止済み run の比較依頼作成除外」(判定材料 parallel_run.status / slot_executions.status)、arch SP-009 / LP-023 / CLP-004(dispatcher は warning を実行ログに残し正常終了)、NFR C.3.3.1(中止済み run の説明)。C.1.3.2(監視方式)は据え置きのため通知方式は変えず、診断専用事象の定義だけを拡張した | CR-016 |
| management_db: aborted_run_judgement(parallel_run.status と slot_executions.status を同一トランザクションで読む) | arch LP-023(完了通知の登録と同じトランザクション内で両状態を読む)、E-016 → E-014 の関係。slot_executions は既存テーブル(aborted.txt のミラー)であり、テーブル・列・権限の追加は不要と判定 | CR-016 |
| management_db: abort_updates(abort-rapid-crosscheck は status IN ('REQUESTED','CLAIMED','RUNNING') の条件付き UPDATE。0 件はエラー。abort-final-crosscheck は RUNNING のみ) | RDRA 条件「依頼中止可否判定」(停止確認 yes + status IN 条件付き UPDATE)、状態「クロスチェック依頼」CLAIMED → ABORTED、arch SP-022 / LP-021 / E-024、NFR C.3.3.1(手動復旧手順)。既存の app_rw ロールは UPDATE 権限を持つため権限設計は変えない | CR-017 |
| management_db: worker_start_update(status = CLAIMED かつ自 worker_id 条件の条件付き UPDATE。0 件なら比較を開始せず正常終了) | RDRA 状態「クロスチェック依頼」CLAIMED → RUNNING(条件付き UPDATE。0 件なら比較を開始しない)、arch SP-011 / LP-024 / AG-002 不変条件 / CLP-004(0 件で開始しなかったこともログに残す) | CR-017 |
| workload-model REQ-DB-006 / mapping vendor_feature / impl 検証規則: 条件付き UPDATE の更新件数を CLI クライアントから取得できる | arch LP-021 / LP-024 が「更新件数」で競合を判定すると定めるため、RDB 製品に対する機能要件として明文化した。PostgreSQL は UPDATE のコマンドタグ(UPDATE n)を返し psql -c の出力からシェルスクリプトが取得できるため conformant。REQ-DB-001(FOR UPDATE SKIP LOCKED)とは別の要件(claim 排他ではなく状態遷移の競合判定) | CR-017 |
| observability: alert-error-rate の対象外事象に abort-rapid-crosscheck による ABORTED 化と worker の 0 件終了 | arch SP-022(運用者の明示中止は正常な運用操作)、LP-024(0 件終了は正常終了)、NFR C.1.3.1 / C.3.1.1 据え置き(NFR 差分の照合結果)。運用者の明示操作と、その結果として worker が比較を開始しなかった事象は異常ではないためアラート対象外とした | CR-017 |
| abort-blue / abort-green の REQUESTED → ABORTED を「競合窓の保険。dispatcher 側の中止済み run 判定と併用」と記述 | RDRA 状態「クロスチェック依頼」REQUESTED → ABORTED の説明、条件「slot 中止可否判定」、arch SP-022 / LP-021 / CM-005 / E-017 / E-024、NFR C.3.3.1 | CR-018 |
| conformance summary 25 要件(conformant 20 / partial 5) | REQ-DB-006 追加分。partial の 5 件は変更なし | CR-017 |
| 構成図: ops CLI → 管理 DB の辺、rapid runner → 管理 DB の辺 | 上記 abort_updates / aborted_run_judgement / worker_start_update を図の辺の説明に反映。mermaid の辺ラベルに括弧・スラッシュを使わない表現にした(md-mermaid-lint で検証) | CR-016 / 017 / 018 |

## 影響なしと判定した項目の根拠

| 項目 | 判定 | 根拠 |
|---|---|---|
| CR-017 の worker 停止確認(対話 yes/no) | infra 構成変更なし | CLI の対話規約(spec の ux-ui 規約)であり配備要素に現れない。impl の abort_updates に前提として記す |
| CR-017 の lease 失効 → 再 claim の抜け | infra 構成変更なし | RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC の出所と claim_pattern は前イベントで反映済み。抜けを塞ぐ手段は abort-rapid-crosscheck の対象拡張(アプリケーション規則)であり、lease の設定値や DB 構成は変えない |
| CR-016 の rapid_run 完了事実の記録(blue_status / green_status / 成果物 URI) | infra 構成変更なし | 既存列への記録であり、スキーマ・権限・観測メトリクスに変更を要しない(rdb-schema は spec の責務) |
| IaC スケルトン(ansible / terraform) | 変更なし | DB ロール権限(app_rw の UPDATE)・配置ファイル・systemd unit 構成に変更がない |

## arch フィードバック / 書き戻しチェック

- arch へ戻す新規知見: なし(本イベントは arch 差分の下流追従のみ。REQ-DB-006 は LP-021 / LP-024 の判定方式を RDB 機能要件として明文化したもので、arch の記述を変える知見ではない)
- 書き戻しチェック: 不要(translation フィールドに影響する arch 変更なし)
