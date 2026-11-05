# 変換推論根拠

## translation を変えない理由

- 上流(USDM / RDRA / NFR / arch)の latest は変わっていない
- workload_type / availability_tier / latency / data_classification / traffic / consistency / cost_posture / target_clouds は、構築手順の検査の範囲の影響を受けない

## 根拠にした正本

| 正本 | 内容 | 反映 |
|---|---|---|
| CLI 契約 config_files の hang-detector.env | キーは HANG_DB_CONN_REF(RAPID_CROSSCHECK_MODE が off でないとき必須)、RAPID_HANG_DETECT_LIMIT_MINUTES(任意、既定 60)、HANG_SCAN_WINDOW_HOURS(任意、既定 72) | 3 キーを持ち得る旨を impl / mapping / workload / conformance / product-input / 配置タスク名に反映 |
| CLI 契約 commands の hang-detector.sh | hang-detector.env 不在、off 以外で HANG_DB_CONN_REF 欠落・空は走査前の設定エラー(終了コード 2) | 中身の検査は hang-detector.sh が起動時に行うとコメント・検証規則に書いた |
| CLI 契約 config_input_rules の env_files | コメント行は前後の空白を除いて `#` で始まる行。行の形の規則 | 行の形の検査も CLI 契約が所有するとした |
| CLI 契約 commands の validate-config.sh | 検証種別は --feature-flag / --job-map / --rapid-crosscheck / --final-crosscheck / --housekeep の 5 つ | hang-detector.env の検証種別は無いため、「validate-config.sh が所有する」とは書かず「CLI 契約が所有し hang-detector.sh が起動時に行う」と書いた |

## 配置時を存在確認だけにする理由

- ハウスキープ設定の配置時検査(存在確認だけ)と同じ考え方にする
- 配置時にモードやキーを判定すると、hang-detector.sh の起動時検査と判定の二重管理になり、今回のように食い違う
- ファイルが無いことだけは配置時に検出できる(hang-detector.sh でも終了コード 2 になる条件)
