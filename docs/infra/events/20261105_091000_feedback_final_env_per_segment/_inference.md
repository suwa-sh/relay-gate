# 変換推論根拠

## translation を変えない理由

- 上流(USDM / RDRA / NFR / arch)の latest は変わっていない
- 変更は構築手順で配る設定ファイルの中身の範囲に収まる
- そのため、workload_type / availability_tier / latency / data_classification / traffic / consistency / cost_posture / target_clouds は影響を受けない

## 根拠にした正本

| 正本 | 内容 | 反映 |
|---|---|---|
| CLI 契約 config_files の final-crosscheck.env の readers | 確報 runner(実行ホスト)の必須は FINAL_DB_CONN_REF、任意は FINAL_POLL_INTERVAL_SEC / FINAL_POLL_LIMIT_SEC。FINAL_COMPARE_COMMAND は読まない。確報 worker(DB セグメント)の必須は FINAL_DB_CONN_REF / FINAL_COMPARE_COMMAND、任意は FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC | 置き場ごとに配る中身を分けた |
| 同 readers(abort-final-crosscheck.sh / housekeep.sh) | どちらも FINAL_DB_CONN_REF だけを使う(有無の判定、または接続) | 実行ホストのファイルに FINAL_DB_CONN_REF を残す理由として書いた。実行ホストの読み手は全員 FINAL_DB_CONN_REF だけを使う |
| 同 note | 各読み手は自分のホストの $RELAY_GATE_CONFIG_DIR/final-crosscheck.env だけを読む。比較ツール起動コマンドは worker 側のファイルの FINAL_COMPARE_COMMAND だけが持つ(2026-11-04 利用者決定)。配置時の検査は存在確認だけ | 配置先のファイル名は両方とも同じにした。存在確認だけの検査は変えない |
| 同 readers(validate-config.sh --final-crosscheck) | worker が読む置き場のファイルを、worker が動くホストで検証する | DB セグメントで実行すると書いた。実行ホストのファイルには FINAL_COMPARE_COMMAND が無いため、そちらでは実行しない |

## 実装の選び方

- 配置タスクを segment ごとに 2 つ置き、元ファイルを別にした(利用者が承認した推奨の実装)
  - 実行ホストセグメント: `files/final-crosscheck-runner.env`
  - DB セグメント: `files/final-crosscheck-worker.env`
- segment の値(`'execution'` / `'db'`)は、ロール内の既存の書き方に合わせた
- 存在確認(`test -f`)と消す処理(state: absent)は、segment で分けずに両方のセグメントで行う
- 配置時は中身の違いを判定しない。中身の検査は CLI 契約(各読み手の起動時の検査と validate-config.sh)が持つ
