# 変換推論根拠

## translation を変えない理由

- 上流(USDM / RDRA / NFR / arch)の latest は変わっていない
- workload_type / availability_tier / latency / data_classification / traffic / consistency / cost_posture / target_clouds は、構築手順の検査の範囲の影響を受けない

## 根拠にした正本

| 正本 | 内容 | 反映 |
|---|---|---|
| CLI 契約 config_files の rapid-crosscheck.env | 必須は RAPID_DB_CONN_REF / RAPID_COMPARE_COMMAND(off 以外のとき)。RAPID_LEASE_SEC(既定 600)/ RAPID_POLL_INTERVAL_SEC(既定 30)は任意。不在・RAPID_DB_CONN_REF 欠落は読み手が終了コード 2 | 配置時は存在確認だけにし、必須・任意の区別を impl / mapping / workload / product-input / 配置タスク名に反映 |
| CLI 契約 commands の validate-config.sh(--rapid-crosscheck / --final-crosscheck) | 起動コマンドの検証(速報は 3 点、確報はコマンド部分だけ) | 起動コマンドの検証は validate-config.sh、その他のキーは各読み手の起動時検査、と所有者を分けて書いた |
| CLI 契約 config_input_rules の env_files | キーと値の前後の空白を除き、値の先頭末尾の引用符を外す。前後の空白を除いて `#` で始まる行はコメント行 | 行頭一致の grep は正当な行を取りこぼすため使わない。認証情報らしい値の警告の対象から env のコメント行を外した |
| CLI 契約 config_files の final-crosscheck.env と housekeep_rules.db_requirement / abort-final-crosscheck.sh | 確報クロスチェックを使わない設置は正当。判定は final-crosscheck.env が無い・FINAL_DB_CONN_REF が無い・空 | 構築の変数 relay_gate_final_crosscheck_enabled(既定 false)で、使う設置だけ配置し存在を確認する。使わない設置でファイルを置かないことは、この判定と矛盾しない |
| CLI 契約 config_files の <slot>-job-map.csv の credential_ref(on_format_violation) | 秘密やパスらしい値は警告して受け付け、拒否しない(2026-09-22 に利用者が確定) | 構築時の認証情報らしい値の検査も、失敗ではなく警告(該当ファイルと行番号)にした |

## 配置時を存在確認だけにする理由

- ハング検知定期ジョブ設定・ハウスキープ設定の配置時検査(存在確認だけ)と同じ考え方にする
- 配置時にキーや値を判定すると、validate-config.sh と各読み手の起動時検査との二重管理になり、今回のように食い違う
- ファイルが無いことだけは配置時に検出できる(速報有効時に無ければ読み手でも終了コード 2 になる)

## 利用者の決定(2026-11-04。どちらも推奨案)

- 確報の設定: 空のファイルで表すのではなく、速報の rapid_crosscheck_mode と同じ形の構築の変数で、配置するかを切り替える
- 認証情報らしい値: 構築を止めずに警告だけにする。値そのものは出さず、該当ファイルと行番号だけを出す
- 確報の設定の置き場: 確報 runner(実行ホスト)と確報 worker(DB セグメント)の両方が読むため、DB セグメントにも config ロールを適用して確報の設定だけを置く。false では両方から消す(構築手順をサーバーの状態の正本とする)
- 前提: 全ホストが構築手順で同じようにデプロイされている。relay-gate の処理の中から設定ファイルは配らず、比較コマンドを変えたら構築手順で配り直す
