# 変換推論根拠

## 差分更新を選んだ理由

- translation の 8 フィールドは上流の変更で値が変わらない(ティア数 4、配置セグメント 2、RDB 1 種、ファイル共有、復旧目標、コスト方針は同じ)
- 変わるのは、ハウスキープが管理 DB に接続しない設定の振る舞い(tier-ops 内の規則)と、ハウスキープ設定の接続参照名の省略可否だけで、MCL 出力の該当箇所に閉じる
- 実行ログの整理(logrotate)は、インフラ設計がすでに logrotate の配置を前提にしており、上流の訂正とすでに一致している
- そのため MCL product-design を全量再実行せず、該当箇所の差分更新(skipped_targeted_update)とした

## 上流の項目と反映先

| 上流の項目 | 反映先 | 推論 |
|---|---|---|
| SP-027 / SP-028 / arch-decision-025(off で接続参照名が無い・空なら管理 DB に接続せず、確報比較依頼と行を削除しない) | impl housekeep_delete / connection_resolution、mapping management_db notes、observability alert-housekeep-failure、構成図の辺 | 接続しない設定では housekeep_del による削除の段が起きない。warn は終了コードに影響しないので失敗通知の対象外 |
| E-028(db_conn_ref が nullable) | impl config_store の検証規則と contents、workload / mapping / product-input のハウスキープ設定、conformance notes、config ロールの検査 | 従来の検証規則「保持日数と接続参照名のキーを持つこと」は off の省略を許さず矛盾するため、接続参照名は off 以外のときだけ必須にした(CLI 契約でも off 以外で欠落・空なら housekeep.sh がエラー)。保持日数は値として必須だが、キーは省略でき既定 90 日になる(CLI 契約の validate-config --housekeep)。両方を省略した空のファイルも正当になり得るため、config ロールの非空検査を存在検査へ改めた |
| NFR B.3.3.1(接続しない設定では行と確報比較依頼が増え続け、off でない期間の実行の成果物も残る) | workload / mapping / impl の容量の頭打ち、cost-hints storage_tiering、product-input management_db | 「保持日数で頭打ち」は接続する設定でだけ成り立つ。接続しない設定の間の増加分は別に見込む |
| NFR F.1.2.1(接続しないときは管理 DB に接続しない) | mapping / impl の接続解決 | 接続参照名の解決の記述に例外を加えた |
| CTR-006 / arch-decision-024(実行ログは relay-gate が整理せず logrotate で 3 か月保管) | 変更なし(execution_log_store、logs.retention、runtime ロールの logrotate 配置) | `ローテーション / logrotate / 手動` で latest を走査し、実行ログの整理を手動とする記述が無いことを確認した。過去の arch フィードバック記録の名前「オンプレミス代替構成における手動運用への配慮」は CTR-006 の名前そのもので、arch 側でも名前は変わっていないため履歴として残す |

## IaC を変えなかった理由(config ロール以外)

- housekeep_del ロールは接続しない設定でも作ってよい(使われないだけで、削除権限の所有の規則 CTR-008 は不変)
- 実行ログの logrotate 配置(日次・90 世代・圧縮)は残す

## MCL 上位コンテキスト

- プロジェクトルートの foundation-context / shared-platform-context は 2026-11-03 に SMTP とメール通知の記述を削除済み(利用者承認)。手順どおりイベント配下へコピーを取り直し、latest のコピーにも反映した
