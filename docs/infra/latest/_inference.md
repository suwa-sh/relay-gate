# 変換推論根拠

## translation を変えない理由

- 上流(USDM / RDRA / NFR / arch)の latest は変わっていない
- 管理 DB が単一インスタンスであることは既存の構成どおり。今回は、その前提を接続参照名の解決先として明記するだけ
- そのため、workload_type / availability_tier / latency / data_classification / traffic / consistency / cost_posture / target_clouds は影響を受けない

## 根拠にした事実

| 事実 | 反映 |
|---|---|
| 確報 runner は実行ホストの FINAL_DB_CONN_REF、確報 worker は DB セグメントの FINAL_DB_CONN_REF で管理 DB に接続する(前回の変更で置き場ごとに別ファイルになった) | 2 つの置き場の参照名が同じ管理 DB に解決されなければならないことを、確報設定のコメントと検証規則の description に書いた |
| 確報 runner が登録した依頼を、確報 worker が同じキューから取得する | 解決先が別の DB だと、設定の検査を通っても確報ジョブが完了しない、を理由として書いた |
| 速報(RAPID_DB_CONN_REF)・ハング検知(HANG_DB_CONN_REF)・ハウスキープ(HOUSEKEEP_DB_CONN_REF)も同じ管理 DB の表を読み書きする | 5 つの参照名すべてを前提の対象にした |
| ハウスキープは専用 DB ロール housekeep_del で接続する | 同じ管理 DB に専用ロールで接続する、と書いた |
| 構築時の検査は設定ファイルの存在確認だけ | 検査は変えず、解決先が同じことは導入する側が確かめる、と書いた |

## 書き方の選び方

- 条件は「参照名の文字列が同じ」ではなく「解決先(接続先の DB)が同じ」とした
  - 置き場ごとに参照名の文字列が違っても、同じ DB に解決されれば正しい
- 新しい検証規則・検査タスクは足さず、既存の説明文(connection_resolution、確報の存在の検証規則の description、コメント)の中に書いた
  - 新しい規則を足すと「構築時に検査する」と読めてしまうため
- 確かめ方の具体的な手順は書かない(利用者の指示の範囲外)

## ハウスキープの仮置き表現を揃えた根拠(controller の追加指示)

| CLI 契約の記述 | 反映 |
|---|---|
| config_files の housekeep.env: path は $RELAY_GATE_CONFIG_DIR/housekeep.env、キーは HOUSEKEEP_RETENTION_DAYS(既定 90)と HOUSEKEEP_DB_CONN_REF(housekeep_del の接続参照名) | 設定の置き場は /etc/relay-gate なので、配置先は /etc/relay-gate/housekeep.env。config ロールは配置先を /etc/relay-gate/{{ relay_gate_housekeep_config_file }} と組み立てるため、変数の値を housekeep.env にすると書いた |
| artifact_root_entries: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ と $RELAY_GATE_ARTIFACT_ROOT/housekeep-pending/ | 成果物の run ディレクトリは /var/lib/relay-gate/facade/(impl の mount_point)なので、成果物ルートは /var/lib/relay-gate。置き場の例を /var/lib/relay-gate/housekeep-pending にした |
| notified_mark の file_name: <run_id>.<role> | 印のファイル名として書いた |

- 変数名・タスク・検査は変えていない。仕様に無い設計判断は足していない
