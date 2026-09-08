# 変換推論根拠(差分更新 20260907_021000_feedback_todo_followup)

前イベント `20260905_093000_feedback_todo_resolution` の推論根拠を引き継ぎ、本イベントで変更した箇所だけを記す。

## translation(変更なし)

| product-input フィールド | 根拠 | 判定 |
|---|---|---|
| workload_type / availability / latency / data_sensitivity / traffic / consistency / cost_posture / target_clouds | arch 差分 20260907_015000 はティア構成・認証認可・DR 方針・外部連携・storage_type を変えていない(E-027 は storage_type file で既存の config_store に収まる)。NFR 差分 20260907_013000 は grade を据え置き(grade_description / reason / source_model のみ更新) | 無変更。MCL 全量再実行は不要 |

## 要素説明の更新根拠

| 更新箇所 | 上流の根拠 | 起因 CR |
|---|---|---|
| config_store: rapid-crosscheck.env(RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC。速報有効時のみ) | RDRA 情報「速報クロスチェック設定」(所有者: 基盤適用設計者)、arch E-027 / storage_mapping E-027 file(env 形式 rapid-crosscheck.env)/ SP-025、NFR C.1.2.2(バックアップ対象に追加)/ E.5.1.1(接続参照名で解決) | CR-013 |
| config_store: 読み手(facade・slot runner・速報クロスチェック runner・worker が起動のたびに読む) | arch storage_mapping E-027 の reason、SP-008 / SP-010 | CR-013 |
| management_db: 接続参照名の解決(RAPID_DB_CONN_REF / HANG_DB_CONN_REF)、claim の lease / poll の出所 | arch SP-008(RDB 接続は RAPID_DB_CONN_REF で解決)、SP-010(lease 期間・poll 間隔の出所)、E-027 の関係(E-013 / E-015 / E-017)、NFR B.3.1.1 / F.1.2.1 | CR-013 |
| management_db: abort_updates(REQUESTED 依頼の条件付き UPDATE) | arch SP-022 / LP-021(WHERE status = REQUESTED の条件付き UPDATE。該当なしは正常)、RDRA 状態「クロスチェック依頼」REQUESTED → ABORTED。既存の app_rw ロールは UPDATE 権限を持つため権限設計は変えない | CR-014 |
| observability: 中止済み run の依頼未作成 warning はメール通知対象外 | arch LP-023 / CLP-004(dispatcher は warning を実行ログに残し正常終了)、RDRA 条件「中止済み run の比較依頼作成除外」。NFR C.1.3.1 / C.1.3.2 / C.3.1.1 は据え置き(NFR 差分の照合結果)のため、アラート規則は追加せず対象外を明記するに留めた | CR-014 |
| execution_log_store: 日時はローカルタイムゾーン、指示子なし、run_id と同じ時刻軸 | arch CLP-002(利用者決定。UTC 統一を削除)/ CTP-003 / E-025 occurred_at | CR-015 |
| execution_hosts: timezone 設定(全ホスト同一 TZ、unit で上書きしない、組織内 NTP)と REQ-LOG-003 | arch CLP-002 が「プロセスの TZ 環境変数に従う」「タイムゾーン指示子なし」と定めるため、run_id と実行ログを突き合わせるにはログを出す全ホスト(実行ホスト・DB セグメントの確報 worker ホスト)で TZ が一致している必要がある。時刻同期は閉域(foundation: air-gapped)のため組織内 NTP に限定。TZ の具体値は適用側の決定事項(適用構成文書)とし、inventory 例の `relay_gate_timezone` は例示 | CR-015 |
| ansible config ロール: rapid-crosscheck.env を 0640、off では配置しない | hang-detector.env と同じ扱い(接続参照名の露出範囲を実行グループに限定)。storage_mapping E-027「RAPID_CROSSCHECK_MODE=off では読まない」に合わせ `rapid_crosscheck_mode` 変数で配置を切り替える | CR-013 |
| conformance: REQ-LOG-003 を conformant、summary 24 要件 | 上記 timezone 設定と timedatectl 検証規則を evidence とした。TZ の具体値が未確定でも要件(一致していること)は構成で満たせるため conformant | CR-015 |

## 影響なしと判定した項目の根拠

| 項目 | 判定 | 根拠 |
|---|---|---|
| CR-014 の速報比較依頼の作成条件(両系成功 × 並行稼働実行の状態) | infra 構成変更なし(observability の注記のみ) | dispatcher のアプリケーション規則(LP-010 / LP-023)であり、管理 DB のスキーマ・権限・観測メトリクスに変更を要しない |
| CR-015 の管理 DB `*_at` 列(RDB のタイムスタンプ型に委ねる) | infra 構成変更なし | PostgreSQL のタイムスタンプ型の選択(timestamp / timestamptz)は spec の rdb-schema の責務。infra は DB ホストの TZ を実行ホストとそろえる(REQ-LOG-003)ことで時刻軸を保証する |
| CR-015 の RELAY_GATE_NOW(UTC Z 付き入力 → ローカル変換) | infra 構成変更なし | テスト用の時刻注入はアプリケーションの入力契約であり配備要素に現れない |

## arch フィードバック / 書き戻しチェック

- arch へ戻す新規知見: なし(本イベントは arch 差分の下流追従のみ。ホスト間 TZ 統一は CLP-002 から導かれる配備制約であり、確認推奨項目として報告する)
- 書き戻しチェック: 不要(translation フィールドに影響する arch 変更なし)
