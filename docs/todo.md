# TODO / 追加提案

本ファイルは後続スキルからの追加提案を集約する。
RDRA に存在しない要素を追加する前に、ここで合意を得てから requirements スキルで反映する。

## 2026-08-30 dist-requirements からの追加提案

### DIST-001: 外部システム「管理 DB(RDB)」「リモート実行ホスト(SSH)」の扱い(内部構成要素か外部システムか)
- **発生元**: dist-requirements (20260830_181841_initial_build)
- **種別**: RDRA追加
- **提案内容**: 方針資料は管理 DB をジョブキュー兼管理 DB として relay-gate の構成要素に含めており、SSH 接続先は適用側で定義する事項。RDRA では BUC の関連先として参照させるため外部システムとして仮登録した。dist-architecture で BC 境界を決める際に、管理 DB を内部データストアへ、SSH ホストを適用側(runner 実装)の関心事へ寄せるか確認する。他の選択肢: 管理 DB のみ内部扱いにして外部システムから除外 / 両方とも外部システムのまま維持
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D6-A: 管理 DB を外部システムから外し内部データストアとしてシステム概要に記載。SSH ホストは外部システム維持(CR-006、rdra:20260905_083000_feedback_todo_resolution)

## 2026-08-30 dist-requirements からの追加提案

### DIST-002: 状態モデル「並行稼働実行」「slot 実行」の状態値(方針資料で未定義)
- **発生元**: dist-requirements (20260830_181841_initial_build)
- **種別**: RDRA追加
- **提案内容**: 方針資料は parallel_run.status と rapid_run.blue_status / green_status の値を定義していない。RDRA では保守的に、並行稼働実行 = STARTED / RUNNING / COMPLETED / ABORTED、slot 実行 = RUNNING / SUCCEEDED / FAILED / ABORTED を仮採用した(クロスチェック依頼と同じ終端状態名に揃え、リラン・中止の判定条件を表現するため)。dist-spec の rdb-schema で列挙値を確定する前に、方針資料側へ状態値を追記するか確認する。他の選択肢: slot 実行をクロスチェック依頼と同じ 6 状態(REQUESTED/CLAIMED を含む)にする / parallel_run.status を slot 実行状態の集約(いずれか RUNNING なら RUNNING)として導出値にする
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: 仮採用値(並行稼働実行 STARTED/RUNNING/COMPLETED/ABORTED、slot 実行 RUNNING/SUCCEEDED/FAILED/ABORTED)を確定。元資料の RUNNING/ABORTED と矛盾なし

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-003: A.2.1.1 サーバ内の冗長化(仮採用 Lv2)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: Lv2(電源・ディスク冗長化)。他の選択肢: Lv1(冗長化なし、再起動で復旧) / Lv3(N+1 手動切替)。理由: facade・runner はジョブスケジューラ実行ホスト上、管理 DB は単一 RDB。オンプレ機器構成が RDRA に無いため低確信。foreground 経路の停止が本番業務ジョブの失敗になる点を踏まえ機器構成を確認する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv2 を適用側で上書き可能な既定値として確定(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-004: A.3.1.1/A.3.1.2 災害対策の範囲・業務継続の要否(仮採用 Lv0/Lv0)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: A.3.1.1 Lv0(対策なし)、A.3.1.2 Lv0(業務継続不要)。他の選択肢: Lv1(バックアップ遠隔地保管)+Lv1(24 時間以内復旧) / Lv2(コールドスタンバイ拠点)+Lv1。理由: 実行履歴・監査はジョブスケジューラの責務で、成果物と execution-spec.json からリラン可能なため基盤単体の DR を要求しないと推定したが、ビジネス判断のため要確認(Step0 プリインタビュー Q3 の仮置き)
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv0/Lv0 を既定値として確定(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-005: C.2.1.2 パッチ適用方針(仮採用 Lv1)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: Lv1(セキュリティパッチのみ随時)。他の選択肢: Lv2(四半期定期適用) / Lv3(月次定期+緊急時即時)。理由: エアーギャップ環境のためパッチはオフラインで持ち込む必要があり、適用頻度は組織の運用ルール次第で RDRA から推論できない
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv1 を既定値として確定(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-006: C.4.1.1 テスト環境(仮採用 Lv2)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: Lv2(簡易テスト環境・本番縮小構成)。他の選択肢: Lv1(テスト環境なし。並行稼働のクロスチェック自体が本番検証) / Lv3(本番同等テスト環境)。理由: feature flag・ジョブマップ・比較定義の切替を本番前に検証する縮小環境が妥当と推定したが、本番同等環境の要否は適用側の判断のため低確信
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv2 を既定値として確定(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-007: C.5.1.1 サポート時間(仮採用 Lv1)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: Lv1(営業時間内 9-17 時)。他の選択肢: Lv2(延長 9-21 時) / Lv3(平日 24 時間対応)。理由: 夜間バッチの background 異常メール(warning/error)を誰がいつ受けて対処するかは運用体制次第で RDRA に無い。運用時間 A.1.1.1=Lv3 とのギャップを確認する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv1 を既定値として確定。根拠: 元資料「warning / error でメールを飛ばし静観してもらう運用」(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-quality-attributes からの追加提案

### DIST-008: C.6.1.1 ログ保管期間(仮採用 Lv2)
- **発生元**: dist-quality-attributes (nfr:20260830_183726_initial_nfr)
- **種別**: NFR確認
- **提案内容**: 仮採用: Lv2(3ヶ月)。他の選択肢: Lv1(1ヶ月) / Lv3(6ヶ月)。理由: 監査の正本はジョブスケジューラにあり、relay-gate の成果物・実行ログ・監視記録は障害調査と警告傾向確認用。並行稼働期間の長さ(hang_detect_limit_minutes 調整に警告傾向を使う期間)に依存するため要確認
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: Lv2 を既定値として確定(CR-012、nfr:20260905_085000_feedback_todo_resolution)

## 2026-08-30 dist-architecture からの追加提案

### DIST-009: slot 実行の永続化方式(file 正本 + 速報有効時 rdb の二重マッピング)
- **発生元**: dist-architecture (arch:20260830_184457_initial_arch)
- **種別**: Arch追加
- **提案内容**: 仮採用: E-014 slot 実行は Runner Result(exitcode.txt)をファイル正本とし、RAPID_CROSSCHECK_MODE=on のときだけ管理 DB にも mode / PID / 状態を保持する二重マッピング(storage_mapping の rdb 側 confidence: low)。他の選択肢: rdb のみ(off モードで DB 接続しない要件に反する) / file のみ(abort-* と background-rerun の対象特定を成果物走査だけで行う)。dist-spec の rdb-schema で正本と DB の同期規則を確定すること。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D4-A: ファイル正本(exitcode.txt / aborted.txt)+ 速報有効時 DB ミラーの二重マッピングを確定(CR-004、arch:20260905_091000_feedback_todo_resolution)

## 2026-08-30 dist-architecture からの追加提案

### DIST-010: ジョブ起動要求・通知メールのストレージマッピング(永続レコードなし)
- **発生元**: dist-architecture (arch:20260830_184457_initial_arch)
- **種別**: Arch追加
- **提案内容**: 仮採用: E-009 ジョブ起動要求は永続レコードを持たず execution-spec.json(追加引数)と実行ログに取り込む(file, low)。E-022 通知メールはメール送信後に送信内容を実行ログへ残し alerted_at を監視記録に記録する(file, low)。他の選択肢: 管理 DB に起動要求テーブル / 通知履歴テーブルを持つ(履歴・監査はジョブスケジューラの責務とする方針に反する可能性) / まったく残さない。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: 仮採用(永続レコードなし。実行ログと監視記録に残す)を確定。元資料「履歴・監査はジョブスケジューラの責務」と整合

## 2026-08-30 dist-architecture からの追加提案

### DIST-011: 集約境界仮説 5 件(AG-001〜AG-005)の確定
- **発生元**: dist-architecture (arch:20260830_184457_initial_arch)
- **種別**: Arch追加
- **提案内容**: 仮採用(全件 low): AG-001 並行稼働実行 root(member: slot 実行 / execution-spec / Runner Result / 応答)、AG-002 速報実行 root(member: 完了通知 / 速報比較依頼 / 比較結果)、AG-003 確報比較依頼 root、AG-004 監視記録 root、AG-005 ジョブマップ root。他の選択肢: slot 実行を独立集約 / 速報比較依頼を独立集約(claim 競合の分離)。最終確定は dist-spec の _model-summary または ddd-tactical-implementation で行う。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: 集約境界仮説 AG-001〜005 を仮採用のまま確定。最終確定は dist-impl の tactical design で行う

## 2026-08-30 dist-architecture からの追加提案

### DIST-012: 運用体制(サポート時間・夜間バッチ異常メールの受け手)
- **発生元**: dist-architecture (arch:20260830_184457_initial_arch)
- **種別**: Arch追加
- **提案内容**: 仮採用(CTP-009, low): サポートは営業時間内(9-17 時)、夜間バッチの異常メールの受け手は運用体制で定める。NFR C.5.1.1 の仮採用値を踏襲。他の選択肢: 夜間も当番制で対応 / 翌営業日対応で確定。運用者の対処(中止・リラン)のタイミングが確報の夜間ウィンドウに影響するため要確認。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: 営業時間内サポート、夜間の受け手は適用側の運用体制で定める(CTP-009 confidence 昇格。arch:20260905_091000_feedback_todo_resolution)

## 2026-08-30 dist-infrastructure からの追加提案

### DIST-013: 組織既存のホスト監視エージェントの有無を確認(REQ-OPS-002)
- **発生元**: dist-infrastructure (infra:20260830_190412_infra_product_design)
- **種別**: Infra確認事項
- **提案内容**: confidence: low で保守的な⭐推奨(組織既存の監視エージェントへの統合)を仮採用した。運用開始前に組織側の既存ホスト監視(CPU/メモリ/ディスク/ネットワーク)の有無を確認し、無い場合はsar/df + cronメールによるfallback監視(product-impl-onprem.yaml#impl.operations.backup_and_monitoring, ansible/roles/relay-gate-backup)で代替する運用を正式化すること。参照: product-decision-005, product-conformance-onprem.yaml(REQ-OPS-002: partial)。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: fallback 監視(sar/df + cron メール)を infra 成果物どおり確定。既存監視エージェントの有無確認は運用開始前の適用側作業

## 2026-08-30 dist-infrastructure からの追加提案

### DIST-014: 管理DBのRPO4h/RTO12h具体値をtechnology_context.constraintsへ明文化するか検討
- **発生元**: dist-infrastructure (arch:20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design)
- **種別**: Arch確認事項
- **提案内容**: infraフィードバックでCTP-006(可用性と計画停止)を補強するRPO/RTOの具体値追加を検討したが、auto_adopt方針により既存ポリシーとの重複可能性がある詳細値の追加は保守的に見送った。次回arch再設計時に、product-decision-002(PostgreSQL選定、RPO 4h/RTO 12h)の値をCTP-006またはtechnology_context.constraintsへ統合するかを検討すること。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 却下
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: product-decision-002 に RPO 4h / RTO 12h があるため arch へ重複させない(据え置き)

## 2026-08-30 dist-spec からの追加提案

### DIST-015: 設定ファイルの形式(feature flag = env、ジョブマップ / クロスチェックジョブマップ / 対象カタログ = TSV)
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: Spec仮採用
- **提案内容**: 仮採用: feature flag は env 形式(BLUE_MODE / GREEN_MODE / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_MODE / CONFIG_VERSION)、slot ジョブマップ・クロスチェックジョブマップ・対象カタログは TSV(1 行 1 job_id、固定引数列は JSON 配列文字列)。他の選択肢: すべて YAML(bash に YAML パーサが無く実行時依存が増える) / すべて JSON(jq 前提)。理由: arch storage_mapping E-001 は env 形式(high)だがジョブマップの形式は「JOB_ID の行」以上の記述が無い。エアーギャップで bash 標準コマンドだけで読める TSV を保守的に仮採用。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D1-A / D2-A: feature flag は元資料の 9 キー(RAPID_CROSSCHECK_MODE=foreground|background|off)、ジョブマップ類は CSV + 元資料の列名に戻す(CR-001 / CR-002、rdra:20260905_083000_feedback_todo_resolution、spec:20260905_100000_feedback_todo_resolution)

## 2026-08-30 dist-spec からの追加提案

### DIST-016: lease 期間・poll 間隔・polling 上限の既定値
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: Spec仮採用
- **提案内容**: 仮採用: lease 10 分 / worker poll 30 秒 / final-crosscheck runner polling 60 秒 / polling 上限 8 時間(超過時は非 0 で終了し依頼状態は変更しない)。すべて設定で上書き可。他の選択肢: lease 5 分 / poll 10 秒 / polling 30 秒(検知は速いが DB 負荷と lease 失効の誤判定リスク増) / lease 30 分 / poll 5 分 / polling 5 分(負荷最小だが worker 障害時の再取得が遅い)。理由: RDRA / arch に具体値が無い(arch LP-013「polling の間隔と上限は設定で指定」)。NFR B.2.2.1(8 時間)・B.2.1.2(〜10 TPS)に収まる保守値を仮採用。実運用値で見直す。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: lease 10 分 / poll 30 秒 / polling 60 秒 / 上限 8 時間を設定で上書き可能な既定値として確定

## 2026-08-30 dist-spec からの追加提案

### DIST-017: slot 実行の永続化(RAPID_CROSSCHECK_MODE=off 時の abort-blue / abort-green の対象特定)
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: Spec仮採用
- **提案内容**: 仮採用: RAPID_CROSSCHECK_MODE=on のとき slot_executions テーブルに mode / PID / status / artifact_dir を保持し abort-* と background-rerun の対象特定に使う。off のときは成果物ファイル(started-at.txt / exitcode.txt)だけで状態を導出し、abort-blue / abort-green は管理 DB が無い旨を stderr に出して終了する(状態更新先が無い)。他の選択肢: 常にファイルのみ(ABORTED を成果物ディレクトリの aborted.txt マーカーで表す。RDRA に無いファイルの発明) / 常に RDB(off 時に管理 DB 接続を要求し条件「速報クロスチェック有効判定」に反する)。理由: arch storage_mapping E-014 の rdb 側 confidence が low。off 時の中止対象特定は RDRA に定義が無い。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D4-A: off でも abort-blue / abort-green が aborted.txt を書き、rerun / hang-detector が ABORTED と判定する(CR-004、rdra:20260905_083000_feedback_todo_resolution、spec:20260905_100000_feedback_todo_resolution)

## 2026-08-30 dist-spec からの追加提案

### DIST-018: run_id の形式
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: Spec仮採用
- **提案内容**: 仮採用: {UTC yyyymmddThhmmssZ}-{job_id}-{8 桁 hex 乱数}(例: 20260830T113000Z-JOB001-3f9a1c2e)。成果物ディレクトリ名として時系列ソートでき、管理 DB なし(off)でも facade 単独で発行できる。他の選択肢: UUIDv4(衝突耐性は高いがディレクトリ一覧で時系列が読めない) / 管理 DB のシーケンス(off 時に発行できない)。理由: RDRA / arch に形式の定義が無い。ID 形式は複数 tier が共有する算出規則のため契約(cli-command-contract.yaml)に定義して仮採用。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D3: 利用者決定により {ローカル TZ yyyymmddThhmmss}-{job_id}-{8 桁 hex}(Z 無し)で確定。UUID には戻さない(CR-003、rdra:20260905_083000_feedback_todo_resolution、spec:20260905_100000_feedback_todo_resolution)

## 2026-08-30 dist-spec からの追加提案

### DIST-019: 通知メールの送信手段と宛先設定(hang-detector.env)の設定所有区分
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: RDRA追加
- **提案内容**: 仮採用: OS 標準の mail / sendmail コマンドを tier-ops の gateway で呼び、宛先・件名プレフィックス・送信コマンドは hang-detector 用 env 設定ファイル(hang-detector.env: ALERT_MAIL_TO / ALERT_MAIL_CMD / ALERT_SUBJECT_PREFIX)で指定する。RDRA の情報「通知メール」に宛先(運用者)はあるが設定の所有区分(バリエーション「設定所有区分」)に該当項目が無いため、Spec では設定ファイル契約として仮置きし RDRA には追加しない。他の選択肢: feature flag 設定ファイルに宛先を追加(feature flag の設定所有区分に反する) / 適用構成文書に宛先を書きスクリプト引数で渡す(定期ジョブ定義に宛先が漏れる)。理由: arch L-ops-gateway「メール送信アダプタ(OS 標準コマンド)」。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: 情報「ハング検知定期ジョブ設定」(hang-detector.env)を RDRA と設定所有区分に追加(CR-010、rdra:20260905_083000_feedback_todo_resolution)

## 2026-08-31 dist-spec からの追加提案

### DIST-020: 速報完了通知の送信失敗を自動検知する要件の要否
- **発生元**: dist-spec (spec:20260830_202851_spec_generation)
- **種別**: RDRA追加
- **提案内容**: 仮採用: 速報クロスチェック runner への完了通知(blue-completed / green-completed)が失敗した場合、slot runner は stderr.log に warn を残し終了コードは実装スクリプトの exitcode のままとし、復旧は運用者が同一引数で rapid-crosscheck-runner.sh を再実行する(冪等・先勝ち)。自動検知(hang-detector が rapid_runs の片系未通知を warning 通知する等)は RDRA に要件が無いためスコープ外とした。他の選択肢: hang-detector に通知種別 notify-missing を追加して warning 通知 / slot runner が通知失敗時に非 0 で終了してジョブスケジューラで検知。速報結果が揃わない事象を運用者がどう検知するか確認する。
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: D5-A: 完了通知失敗の自動検知はスコープ外と RDRA 条件に明記。復旧は運用者の手動再通知(CR-005、rdra:20260905_083000_feedback_todo_resolution)

## 2026-08-31 dist-pipeline からの追加提案

### DIST-021: spec 網羅率 99.4%: rdra-feedback の変更要望 12 件(requirements 差分更新で解消予定)
- **発生元**: dist-pipeline (20260830_202851_spec_generation)
- **種別**: rdra-feedback
- **提案内容**: docs/specs/latest/_cross-cutting/rdra-feedback.md 参照。未カバー 2 件(情報の属性)を含む 12 件。対応する場合は feedback request を作成して /distillery:dist-pipeline で差分実行する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-05, feedback:20260905_todo_resolution)**: rdra-feedback 12 件のうち #1〜7、#11、#12 を RDRA 反映(CR-007〜011)、#8 は D5、#10 は D1 で逆方向(契約を元資料へ戻す)に決定、#9 は本文を正とし RDRA 変更なし(元資料 C2 図の修正はユーザー作業)。rdra:20260905_083000_feedback_todo_resolution

## 2026-09-05 dist-architecture からの追加提案

### DIST-022: 実行ログの日時タイムゾーン(CLP-002 は UTC、run_id の時刻部はローカル TZ)
- **発生元**: dist-architecture (arch:20260905_091000_feedback_todo_resolution)
- **種別**: Arch確認事項
- **提案内容**: run_id の時刻部を利用者決定でローカル TZ にしたため、実行ログの日時(CLP-002: UTC 統一)と時刻軸が食い違う。⭐推奨 A: CLP-002 のログ日時もホストのローカル TZ に揃える(run_id と同じ時刻軸で調査できる)。他の選択肢: B: UTC のまま(相関時に読み替え) / C: オフセット付き ISO 8601(ローカル時刻 + +09:00 等)。今回の feedback run では未反映。採用する場合は feedback request で差分実行する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-07, feedback:20260907_todo_followup)**: A: 実行ログ・CLI stdout・DB *_at をホストのローカル TZ(指示子なし)に統一。Runner Result ファイルの中身は UTC Z 維持(CR-015、arch:20260907_015000_feedback_todo_followup、spec:20260907_024000_feedback_todo_followup)

## 2026-09-06 dist-spec からの追加提案

### DIST-023: 速報クロスチェック設定(rapid-crosscheck.env: RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC)を RDRA 情報・設定所有区分に追加
- **発生元**: dist-spec (spec:20260905_100000_feedback_todo_resolution)
- **種別**: RDRA追加
- **提案内容**: spec の設定ファイル契約 rapid-crosscheck.env に対応する RDRA 情報が無い(前イベントからの継続。今回 _model-summary.yaml の誤った rdra_info を外した)。⭐推奨 A: RDRA 情報「速報クロスチェック設定」を追加(hang-detector.env = 情報「ハング検知定期ジョブ設定」と同型)。他の選択肢: B: hang-detector.env に統合(所有者が異なる) / C: RDRA 外の実装設定として Spec のみで管理(トレーサビリティに乗らない)。採用する場合は feedback request で差分実行する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-07, feedback:20260907_todo_followup)**: A: RDRA 情報「速報クロスチェック設定」を追加し設定所有区分と 4 UC に紐づけ(CR-013、rdra:20260907_011000_feedback_todo_followup)

## 2026-09-06 dist-spec からの追加提案

### DIST-024: 中止(aborted.txt)後に実装が終了して exitcode.txt が公開された slot の完了通知の要否
- **発生元**: dist-spec (spec:20260905_100000_feedback_todo_resolution)
- **種別**: Spec仮採用
- **提案内容**: 仮採用 A: 通知は送る(状態導出は exitcode.txt 優先で SUCCEEDED / FAILED。速報比較依頼の要否は worker 側の依頼作成条件で判断)。他の選択肢: B: aborted.txt があれば通知を送らない(WARN completion notice skipped) / C: 通知は送るが rapid-crosscheck-runner が parallel_runs=ABORTED の run を無視する。RDRA / USDM に定義が無く CR-004 の決定(exitcode.txt 優先)から最小の解釈で導けるのは A。confidence: low
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-07, feedback:20260907_todo_followup)**: C + 半歩拡張: 中止済み run では dispatcher(rapid-crosscheck-runner)が速報比較依頼を作らず、abort-blue / abort-green が REQUESTED 未着手依頼も ABORTED にする(CR-014、rdra:20260907_011000_feedback_todo_followup、spec:20260907_024000_feedback_todo_followup)

## 2026-09-07 dist-spec からの追加提案

### DIST-025: 中止済み run の判定キー(parallel_run ABORTED だけでは foreground 完了後の除外が効かない)
- **発生元**: dist-spec (spec:20260907_024000_feedback_todo_followup)
- **種別**: RDRA確認
- **提案内容**: CR-014 の条件文は「並行稼働実行が ABORTED の run では速報比較依頼を作らない」だが、foreground 完了後に parallel_run は COMPLETED になるため、その後の background slot 中止(aborted.txt)では parallel_run が ABORTED にならず典型経路で除外が効かない。spec は仮採用 ⭐A: parallel_run ABORTED または slot 実行 ABORTED(aborted.txt 公開済み)を中止済みと判定。他の選択肢: B: parallel_run ABORTED のみ(RDRA 条件文どおり。抜けを容認) / C: abort-blue / abort-green が COMPLETED の parallel_run も ABORTED にする(状態モデル変更)。RDRA 条件「中止済み run の比較依頼作成除外」の文言を A に合わせる変更要望(rdra-feedback #13)
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-08, feedback:20260907_abort_consistency)**: A: 中止済み run の判定キーを「並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED」に拡張(CR-016、rdra:20260907_114000_feedback_abort_consistency、spec:20260907_131000_feedback_abort_consistency)

## 2026-09-07 dist-spec からの追加提案

### DIST-026: abort-rapid-crosscheck の対象に REQUESTED / CLAIMED を加えるか
- **発生元**: dist-spec (spec:20260907_024000_feedback_todo_followup)
- **種別**: RDRA確認
- **提案内容**: 中止済み run の CLAIMED 依頼が lease 失効で REQUESTED に戻り再 claim される経路を止める手段が無い。⭐A: abort-rapid-crosscheck の対象に REQUESTED / CLAIMED を加える(条件「依頼中止可否判定」・状態.tsv・SPEC-010-02 の変更要望、rdra-feedback #15)。他の選択肢: B: 現状維持(hang-detector 通知で運用者が気づく) / C: worker の claim SELECT で中止済み run を除外する。requirements 段階の確認推奨項目 1(CLAIMED の中止)と同根
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-08, feedback:20260907_abort_consistency)**: A: abort-rapid-crosscheck の対象を REQUESTED / CLAIMED / RUNNING に拡張。worker の CLAIMED → RUNNING は条件付き UPDATE で 0 件なら比較を開始しない。元資料「RUNNING でない場合はエラー終了」を広げる変更のため元資料側に追記候補(CR-017、rdra:20260907_114000_feedback_abort_consistency、spec:20260907_131000_feedback_abort_consistency)

## 2026-09-07 dist-spec からの追加提案

### DIST-027: REQUESTED → ABORTED(abort-blue / abort-green)の位置づけ(競合窓の保険)
- **発生元**: dist-spec (spec:20260907_024000_feedback_todo_followup)
- **種別**: RDRA確認
- **提案内容**: ⭐A: 競合窓の保険として残し、状態.tsv の説明文「両 slot 完了直後の抜けを防ぐ」を経路に合わせて修正(rdra-feedback #14)。他の選択肢: B: 遷移を RDRA から削除 / C: abort-blue / abort-green を終端済み slot にも許可する(中止可否判定の変更)
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-08, feedback:20260907_abort_consistency)**: A: REQUESTED → ABORTED を競合窓の保険として説明を書き直し(CR-018、rdra:20260907_114000_feedback_abort_consistency)

## 2026-09-07 dist-infrastructure からの追加提案

### DIST-028: ホスト間のタイムゾーン統一方式(REQ-LOG-003)
- **発生元**: dist-infrastructure (infra:20260907_021000_feedback_todo_followup)
- **種別**: Infra確認事項
- **提案内容**: ログ日時をローカル TZ にしたため全ホストの TZ 一致が前提になる。⭐A: OS の TZ 設定を全ホストで同じ値にし unit / cron で上書きしない(仮採用。具体値は適用側の relay_gate_timezone)。他の選択肢: B: systemd unit / ジョブスケジューラの環境変数で TZ を明示 / C: ジョブスケジューラ実行ホストの TZ を正とし他ホストを合わせる。適用側で確定する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 確定
- **ステータス**: closed
- **決定(2026-09-08, feedback:20260907_abort_consistency)**: A: OS の TZ 設定を全ホストで同一にし unit / cron で上書きしない。具体値は適用側の relay_gate_timezone(infra:20260907_021000_feedback_todo_followup の REQ-LOG-003)

## 2026-09-08 dist-spec からの追加提案

### DIST-029: 条件「slot 実行の状態導出規則」の管理 DB 側の文言(slot_executions.status は一度だけ終端値を書き、abort 後の exitcode.txt では再同期しない)
- **発生元**: dist-spec (spec:20260907_131000_feedback_abort_consistency)
- **種別**: RDRA確認
- **提案内容**: Spec は slot_executions.status を aborted.txt / exitcode.txt 公開時の条件付き UPDATE で一度だけ書き、abort 後に実装が走り切って exitcode.txt を公開した経路では導出値(exitcode.txt 優先)と一致せず ABORTED のまま残す、と限定している(USDM SPEC-005-02 AC6 の前提)。RDRA 条件.tsv は「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」としか書いていない。⭐推奨 A: RDRA 条件の文言を Spec の限定記述に合わせる(実装には影響しない文言差の解消。rdra-feedback #16)。他の選択肢: B: RDRA は変えず Spec 側の限定記述だけで運用 / C: runner が exitcode.txt 公開時に ABORTED を上書きして再同期(条件「中止済み run の比較依頼作成除外」の判定材料と SPEC-005-02 AC6 に反するため非推奨)
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: 反映
- **ステータス**: closed
- **決定(2026-09-08, feedback:20260908_slot_status_wording)**: A: 条件「slot 実行の状態導出規則」の管理 DB 側を「公開時点の状態を条件付き更新で一度だけ書き、abort 後は ABORTED を残して再同期しない」に改め、USDM SPEC-005-02 に受け入れ条件を追加。arch E-014 / spec の旧文言引用も追従(CR-019、rdra:20260908_011000_feedback_slot_status_wording、arch:20260908_015000_feedback_slot_status_wording、spec:20260908_024000_feedback_slot_status_wording)

## 2026-09-17 dist-spec からの追加提案

### DIST-030: runner --help 問い合わせの 1 slot あたり予算 4.6 秒(待機 4 秒 + 停止 0.2 秒 + 回収・起動オーバーヘッド 0.4 秒)
- **発生元**: dist-spec (20260917_050000_feedback_impl_feedback_fd678b04)
- **種別**: 仮採用値
- **提案内容**: 提案内容: cli-command-contract.yaml validate-config.sh runner_help_probe.per_slot_probe_budget_seconds = 4.6(仮採用、confidence: low)。待機上限 4 秒・TERM → 0.2 秒後 KILL・逐次は CR-fd678b04-002 の利用者希望値で確定。プロセスグループの回収と起動のオーバーヘッド 0.4 秒以内だけが実測(両 slot 未応答で約 9.1 秒 = 2 × 4.55 秒)からの導出で、両 slot 未応答の上限 2 × 4.6 = 9.2 秒 ≤ NFR B.2.1.1 の 10 秒(残り 0.8 秒)。他の選択肢: 0.2 秒(2 × 4.4 = 8.8 秒。実測より厳しく、遅いホストで BDD がフレークしうる)/ 0.9 秒(2 × 5.1 = 10.2 秒。NFR を超えるため待機上限を 3.5 秒に下げる必要)。実装フェーズの実測で確定する
- **根拠**: (サブエージェントが記入)
- **影響範囲**: (サブエージェントが記入)
- **推奨対応**: [ ] requirements スキル再実行で反映 / [ ] 却下 / [ ] 保留
- **ステータス**: open

