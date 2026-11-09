# 変換推論根拠

## translation を変えない理由

- workload_type / availability_tier / latency / data_classification / traffic / consistency / cost_posture / target_clouds は、いずれも上流の変更の影響を受けない
- 変わるのは、ハウスキープ設定の接続参照名が必須になる設置の範囲と、必須なのに無い・空のときの振る舞い(tier-ops 内の規則)だけで、MCL 出力の該当箇所に閉じる

## 上流の変更とインフラ設計への反映

| 上流の変更 | 反映先 | 推論 |
|---|---|---|
| SP-027 / arch-decision-026(off 以外または確報クロスチェックを使う設置では接続参照名が必須。無い・空なら設定エラーで何も削除しない。接続しないのは管理 DB を一切使わない設置だけ) | impl housekeep_delete / connection_resolution / 検証規則、mapping management_db / config_store notes、product-input / workload の config_store、conformance notes、構成図の辺 | 前回の「off では省略できる」は条件が広すぎた。off でも確報クロスチェックを使う設置は管理 DB を使うので必須側に入る |
| SP-028 / BC-006(設定の検査を置き場の残りの削除を含むすべての削除より先に行い、設定エラーなら置き場の中身も消さない) | impl housekeep_delete | 削除の段の説明の先頭に検査を置いた |
| CM-013 / BC-005 / E-028(判定に RAPID_CROSSCHECK_MODE と確報クロスチェック worker 設定の有無を使う。設定があるとみなす判定方法は仕様で確定) | impl 検証規則、config ロールのコメント | 判定は housekeep.sh の起動時に行う。配置時の静的検査に同じ判定を持たせると二重管理になるため足さない |
| NFR B.3.3.1(必須化で増え続ける状態は起きない。管理 DB を一切使わない設置では off 以外の期間の実行の行と成果物が残る分を別に見込む) | workload / mapping / impl の容量、cost-hints storage_tiering、product-input management_db | 「接続しない設定の間は増え続ける」を外し、残る分だけを別に見込む記述に改めた |
| 設定エラーは非 0 終了 | observability alert-housekeep-failure | 設定エラーはジョブスケジューラの障害通知の対象。warn が対象外になるのは管理 DB を一切使わない設置だけ |

## 変更しない判断

- config ロールの存在検査(空でもよい)は維持する。管理 DB を一切使わない設置では空のファイルも正当になり得る
- housekeep_del ロールの作成、削除権限の所有の規則(CTR-008)は不変
