# 変換推論根拠

## 差分更新を選んだ理由

- translation の 8 フィールドは上流の変更で値が変わらない(ティア数 4、配置セグメント 2、RDB 1 種、ファイル共有、復旧目標、コスト方針は同じ)
- 変わるのは、メール通知という 1 要素の削除と、tier-ops 内の運用スクリプト 1 本(housekeep)・DB ロール 1 つ・設定 1 つの追加であり、MCL 出力の該当箇所に閉じる
- そのため MCL product-design を全量再実行せず、該当箇所の差分更新(skipped_targeted_update)とした

## 上流の項目と反映先

| 上流の項目 | 反映先 | 推論 |
|---|---|---|
| arch-decision-022 / CTP-001(通知送信手段なし) | workload alerting_channel、mail_notification の削除、mapping / impl / conformance / 図 / IaC の Postfix 削除 | relay-gate がメールを送らないので MTA・送信コマンド・SMTP ポートは不要 |
| SP-018 / CTP-009(終了結果と標準エラーをジョブスケジューラの障害通知で届ける) | impl execution_hosts の timer 廃止、job_scheduler の定義・exit_code_policy・alerting、REQ-SCH-003 | systemd timer で起動すると終了結果がジョブスケジューラに届かず通知が成立しない。arch tier-ops は hang-detector を「ジョブスケジューラの定期ジョブ」と定めており、infra の timer は以前からの不一致だった |
| CTP-010(日次メールサマリー → ジョブスケジューラの既存監視) | observability dashboards / alerting / escalation | 送信手段が無いため、ジョブの実行履歴・終了結果の確認へ置き換える |
| E-026 / storage_mapping E-026(HANG_DB_CONN_REF だけ) | impl / workload / mapping の hang-detector.env、config ロールのキー構成検査 | メール 3 キーの削除 |
| ホスト監視の fallback(cron メール) | mapping / impl / decision-005 / conformance / backup ロール | MTA が無くなるので cron メールは届かない。CTP-010 の「ジョブスケジューラの既存監視への統合」に合わせ、閾値検査スクリプトをジョブスケジューラの定期ジョブにして障害通知で届ける(確認推奨項目) |
| arch-decision-023 / CTP-002 / CTR-008(削除は housekeep だけ、専用ロール) | impl roles に housekeep_del、app_rw の権限文言、検証規則、postgresql ロール、REQ-DB-007 | 従来の「app_rw に DELETE が管理レコード以外に付与されていないこと」は管理レコードの DELETE を許す読み方ができ、CTP-002 と矛盾するため「app_rw / ops_ro にどのテーブルへの DELETE も無い」に改めた。ロール名は既存の app_rw / ops_ro の命名にそろえた仮の名前 housekeep_del(確認推奨項目) |
| SP-028 / LP-026(置き場への同一ファイルシステム内 rename) | impl artifact_store の housekeep_staging と検証規則、runtime ロールの検査、REQ-ART-004 | product-decision-003 は NFS も許すため、置き場が別ファイルシステムだと rename(2) が失敗する。同一ファイルシステム(NFS は同一 export)を検証規則にした |
| storage_mapping E-021(off 時の通知済みの印) | impl artifact_store の notified_marks、REQ-ART-004 | 一時ファイル → リネームの原子的確定は既存の REQ-ART-001 と同じ規則 |
| E-028 / CTR-007(ハウスキープ設定、保持日数は正の整数) | impl config_store、config ロール、検証規則 | ファイル名・キー名は仕様で確定するため、IaC は変数(relay_gate_housekeep_config_file)で受け、内容検査は validate-config.sh の所有とした |
| CTR-006(保持期間超過分の手動削除 → ハウスキープの自動削除) | mapping artifact_store の gap、cost-hints storage_tiering、容量の頭打ち | 成果物と管理 DB の量は保持日数(既定 90 日)× 1 日あたりの量で頭打ちになる。実行ログは logrotate(3 ヶ月)のまま |
| CTP-001(起動口にハウスキープ定期ジョブ) | job_scheduler の定義、REQ-SCH-002、README の適用順序 | 1 日 1 回。削除したくない場合は登録しない(運用手順書) |

## 仕様で確定するもの(infra では決めない)

- ハウスキープ設定のファイル名・キー名
- 削除待ちの置き場と通知済みの印の場所・ファイル名
- ハング検知ジョブの警告終了の終了コードの値

## 書き戻しチェック

- 不要。arch 差分はティア数・認証認可方式(接続ロールの追加のみ)・DR 方針・storage_type を変えず、外部連携はメール通知が減っただけで translation に影響しない
