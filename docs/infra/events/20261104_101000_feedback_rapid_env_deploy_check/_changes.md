# 変更サマリ

- event_id: 20261104_101000_feedback_rapid_env_deploy_check
- trigger_event: infra:20261104_091000_feedback_external_review_fixes(上流 latest は変更なし)
- created_at: 2026-11-04T10:10:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261104_rapid_env_deploy_check(direct work unit: CR-d8a2f4b6-001#1。causal work unit: CR-d8a2f4b6-001#1(速報クロスチェック設定の配置時検査をファイルの存在確認だけにする)。packet: docs/pipeline/feedback-runs/20261104_rapid_env_deploy_check/stage-packets/infrastructure.md)
- 利用者の決定(2026-11-04): 確報の設定は構築の変数で使う設置だけ配置する。認証情報らしい値の検査は警告だけにする。確報の設定は実行ホストと DB セグメントの両方に置き、使わない設置では両方から消す(いずれも推奨案)
- 前提(利用者の方針): 全ホスト(確報 worker が動く DB セグメントを含む)が構築手順で同じようにデプロイされている。relay-gate の処理の中から設定ファイルは配らない。比較コマンドを変えたら構築手順で配り直す

## 追加

- 構築の変数 `relay_gate_final_crosscheck_enabled`(確報クロスチェックを使うか。既定 false。速報の `rapid_crosscheck_mode` と同じ形)。全ホストで同じ値にするため inventory 例の全ホスト共通の変数に追記し、README にも追記
- site.yml の DB セグメントに config ロールを割り当てた。DB セグメントで置くのは確報クロスチェック worker 設定だけ

## 変更

構築手順(config ロール)の配置時検査が CLI 契約より厳しく、仕様どおりの正当な設定で構築が失敗していた。配置時はファイルの存在確認だけにし、中身の検査は CLI 契約に任せた(前回のハング検知定期ジョブ設定の直し方と同じ)。

| 設定ファイル | 前回の構築時の検査 | 今回の構築時の検査 | 中身の検査の所有者(CLI 契約) |
|---|---|---|---|
| 速報クロスチェック設定(rapid-crosscheck.env。速報有効時のみ) | RAPID_DB_CONN_REF の行と、RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC が正の整数の行を grep で必須 | `test -f`(ファイルがあることだけ) | 起動コマンドは validate-config.sh --rapid-crosscheck。RAPID_DB_CONN_REF の欠落・空と RAPID_* の値の不正は各読み手の起動時検査(終了コード 2) |
| 確報クロスチェック worker 設定(final-crosscheck.env) | 実行ホストだけに常に配置し、`test -s`(空でないこと) | 変数が true なら実行ホストと DB セグメントの両方に置き `test -f`。false なら両方から消す(state: absent) | 起動コマンドは validate-config.sh --final-crosscheck。必須キーの欠落・空は確報 runner / worker の起動時検査 |
| 認証情報らしい値(全 env / CSV) | password / secret / token の直後に `=` がある行があれば失敗(コメント行も) | env のコメント行を除き、一致した行の該当ファイルと行番号を警告するだけ。構築は止めない。両セグメントで行う(DB セグメントでは確報の設定だけが対象) | CLI 契約の「秘密らしい値は警告して受け付ける」方針(2026-09-22)に揃えた。参照名だけを置く方針は変えない |

確報を使わない設置でファイルを置かないことは、CLI 契約と矛盾しない。CLI 契約は、ファイルが無い・FINAL_DB_CONN_REF が無い・空を「確報を使わない設置」として扱う(housekeep.sh / abort-final-crosscheck.sh)。

構築が失敗していた正当な設定の例:

- 速報: lease 期間・poll 間隔を省いた設定(CLI 契約では任意キーで、既定 600 / 30 秒)
- 速報: キーの前に空白がある行、値を引用符で囲んだ行、値の後ろに空白がある行(CLI 契約では前後の空白を除き、先頭末尾の引用符を外す)
- 確報: 確報クロスチェックを使わない設置(以前は常に配置し、空のファイルも拒否していた)
- 認証情報らしい値: `# token = ...` のようなコメント行、比較ツール起動コマンドの `--api-token=参照名` のような引数、ジョブマップの fixed_params のセル

変更したファイル:

- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: 上表の 3 つの検査と、そのコメント・配置タスク名
- infra/product/onprem/ansible/inventory.ini.example: `relay_gate_final_crosscheck_enabled=false` を全ホスト共通の変数に追記
- infra/product/onprem/ansible/site.yml: DB セグメントにも config ロールを割り当てた
- docs/cloud-context/generated-md/product/relay-gate-target-architecture.md: 設定ノードに final-crosscheck.env を追記し、DB セグメントに確報クロスチェック worker 設定のノードと確報 worker からの読み取りの辺を追加
- infra/product/onprem/README.md: 前提に、全ホストが構築手順でデプロイ済みであること(処理の中から配らない、コマンド変更時は配り直す)、速報・確報の切り替え変数、認証情報らしい値は警告だけで構築を止めないことを追記
- docs/mcl/product/output/product-impl-onprem.yaml: config_store の contents と検証規則 3 件(速報・確報・認証情報らしい値)
- docs/mcl/product/output/product-mapping-onprem.yaml: config_store の configuration_notes
- docs/mcl/product/output/product-workload-model.yaml: config_store の説明
- docs/cloud-context/conformance/product/product-conformance-onprem.yaml: 設定の要件の notes(判定は不変)
- docs/mcl/product/input/product-input.yaml(と直下コピー): config_store の説明(translation は不変)

## 削除

- 構築時の「RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC の 3 キーを持ち、秒の 2 キーが正の整数」の検査(存在確認に置き換え)
- 確報クロスチェック worker 設定の無条件の配置と「空でない」の検査(変数で切り替える配置と存在確認に置き換え)
- 「確報は常時有効のため無条件に配置する」のコメント(CLI 契約と食い違うため)
- 認証情報らしい値で構築を失敗させる動作(警告に置き換え)

## 補足

- 変数を false にすると、両方の置き場から final-crosscheck.env を消す。構築手順をサーバーの状態の正本とし、残ったファイルで housekeep.sh が確報を使う設置と誤判定するのを防ぐ
- DB セグメントには確報の設定以外を置かない。他の設定ファイルの配置と検査は `segment == 'execution'` のときだけ行う(runtime ロールと同じ書き方)

## 変えなかったもの

- product-observability.yaml / product-cost-hints.yaml: 速報・確報の設定のキー構成や構築時の検査を書いていない
- ハング検知定期ジョブ設定・ハウスキープ設定の検査: 既に存在確認だけで CLI 契約と一致している
- arch: 新しい知見は無い(Phase4 で arch を更新しない)
