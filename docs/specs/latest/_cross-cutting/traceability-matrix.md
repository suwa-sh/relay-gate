# 要件トレーサビリティマトリクス

生成対象: `docs/specs/events/20260817_155817_spec_generation/`
分母算出根拠: `docs/rdra/latest/*.tsv`
判定ルール: `docs/rdra/latest/cross-cutting-traceability-template.md`

## 網羅率サマリー

| カテゴリ | 全要素数 | カバー済み | 未カバー | 網羅率 |
|---------|:-------:|:--------:|:------:|:-----:|
| 情報の属性 | 44 | 44 | 0 | 100% |
| 条件 | 2 | 2 | 0 | 100% |
| バリエーションの値 | 18 | 18 | 0 | 100% |
| 状態遷移パス | 18 | 18 | 0 | 100% |
| 外部システム連携 | 3 | 3 | 0 | 100% |
| **合計** | **85** | **85** | **0** | **100%** |

> 是正履歴: 「バリエーションの値」で当初未カバーだった 運用モード（並行稼働／新実装単独本番／次世代実装との並行稼働、3値）を、パターンA（Spec側対応）として `並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md` のバリエーション一覧・BDDシナリオに追記し、100%網羅を達成した。

## 情報属性マトリクス

分母: 情報.tsv の `{情報名}.{属性名}` ごと（44件）

| 情報名 | 属性名 | 参照 UC | 参照 Spec ファイル | カバー状態 |
|--------|--------|--------|-----------------|:---------:|
| execution-spec.json | run_id | feature flag設定に基づきslotを選択して起動する | [feature flag設定に基づきslotを選択して起動する](../並行稼働実行業務/並行稼働実行フロー/feature%20flag設定に基づきslotを選択して起動する/spec.md) | covered |
| execution-spec.json | parent_run_id | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | JOB_ID | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | ホスト | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | 実行ユーザー | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | スクリプト | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | 作業ディレクトリ | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | 固定引数 | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | 追加引数 | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | マップ版 | feature flag設定に基づきslotを選択して起動する | 同上（job_map_version） | covered |
| execution-spec.json | 実装版 | feature flag設定に基づきslotを選択して起動する | 同上（impl_version） | covered |
| execution-spec.json | hang_detect_limit_minutes | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| execution-spec.json | 認証情報参照名 | feature flag設定に基づきslotを選択して起動する | 同上（credential_ref） | covered |
| Runner実行結果 | run_id | 並行稼働実行結果を確認する | [並行稼働実行結果を確認する](../並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する/spec.md) | covered |
| Runner実行結果 | slot種別（blue/green） | 並行稼働実行結果を確認する | 同上（slot_type） | covered |
| Runner実行結果 | role区分（foreground/background/rapid-crosscheck） | 並行稼働実行結果を確認する | 同上（role_type） | covered |
| Runner実行結果 | 開始時刻（started-at） | 並行稼働実行結果を確認する | 同上（started_at） | covered |
| Runner実行結果 | 標準出力（stdout） | 並行稼働実行結果を確認する | 同上（stdout_path） | covered |
| Runner実行結果 | 標準エラー（stderr） | 並行稼働実行結果を確認する | 同上（stderr_path） | covered |
| Runner実行結果 | 終了コード（exitcode） | 並行稼働実行結果を確認する | 同上（exit_code） | covered |
| Runner実行結果 | 実行状態（RUNNING/SUCCEEDED/FAILED/ABORTED） | 並行稼働実行結果を確認する | 同上（status） | covered |
| 速報比較依頼 | run_id | 速報クロスチェック結果を確認する | [速報クロスチェック結果を確認する](../クロスチェック業務/速報クロスチェックフロー/速報クロスチェック結果を確認する/spec.md) | covered |
| 速報比較依頼 | JOB_ID | 速報クロスチェック結果を確認する / blue-green runnerの完了通知を受けて速報比較依頼を作成する | 同上（job_id） | covered |
| 速報比較依頼 | 依頼日時 | blue-green runnerの完了通知を受けて速報比較依頼を作成する | [blue-green runnerの完了通知を受けて速報比較依頼を作成する](../クロスチェック業務/速報クロスチェックフロー/blue-green%20runnerの完了通知を受けて速報比較依頼を作成する/spec.md)（requested_at） | covered |
| 速報比較依頼 | 状態（REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED） | 速報クロスチェック結果を確認する | 同上（status） | covered |
| 速報比較依頼 | lease期限 | 速報クロスチェックを実行し差分を検知する | [速報クロスチェックを実行し差分を検知する](../クロスチェック業務/速報クロスチェックフロー/速報クロスチェックを実行し差分を検知する/spec.md)（lease_expires_at） | covered |
| 速報比較依頼 | worker識別子 | 速報クロスチェックを実行し差分を検知する | 同上（worker_id） | covered |
| 速報比較結果 | run_id | 速報クロスチェック結果を確認する | [速報クロスチェック結果を確認する](../クロスチェック業務/速報クロスチェックフロー/速報クロスチェック結果を確認する/spec.md) | covered |
| 速報比較結果 | 比較判定結果（OK/NG） | 速報クロスチェック結果を確認する | 同上（comparison_result） | covered |
| 速報比較結果 | 差分件数 | 速報クロスチェック結果を確認する | 同上（diff_count） | covered |
| 速報比較結果 | 差分詳細（レポートURI） | 速報クロスチェック結果を確認する | 同上（diff_detail_uri） | covered |
| 速報比較結果 | 比較完了日時 | 速報クロスチェック結果を確認する | 同上 | covered |
| 確報比較依頼 | run_id | 確報クロスチェック結果を確認する | [確報クロスチェック結果を確認する](../クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md) | covered |
| 確報比較依頼 | 対象日 | 確報クロスチェック結果を確認する | 同上（target_date） | covered |
| 確報比較依頼 | 状態（REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED） | 確報クロスチェック結果を確認する | 同上（status） | covered |
| 確報比較依頼 | lease期限 | 確報クロスチェック結果を確認する | 同上（lease_expires_at） | covered |
| 確報比較依頼 | worker識別子 | 確報クロスチェック結果を確認する | 同上（worker_id） | covered |
| 確報比較依頼 | 対象テーブル・対象ファイル一覧 | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | [全テーブル・全ファイルを対象に確報クロスチェックを実行する](../クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する/spec.md)（target_tables/target_files） | covered |
| ハング検知記録 | run_id | background実行の未完了・非0終了・速報比較異常を定期検知する | [background実行の未完了・非0終了・速報比較異常を定期検知する](../実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) | covered |
| ハング検知記録 | 異常検知種別（ハング疑い/background実行エラー/速報クロスチェック異常） | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上（detection_type） | covered |
| ハング検知記録 | 検知日時 | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上（detected_at） | covered |
| ハング検知記録 | 検知しきい値（hang_detect_limit_minutes） | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上（threshold_minutes） | covered |
| ハング検知記録 | 対象slot種別（blue/green） | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上（slot_type） | covered |
| ハング検知記録 | 通知先 | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上（notify_target） | covered |

## 条件マトリクス

分母: 条件.tsv の各条件（2件）

| 条件名 | ルール | 適用 UC | 適用 Spec ファイル | カバー状態 |
|--------|-------|--------|-----------------|:---------:|
| feature flag設定（BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODE） | BLUE_MODE/GREEN_MODEはforeground/background/offのいずれか、両方同時foregroundは不可。RAPID_CROSSCHECK_MODEはon/off | feature flag設定に基づきslotを選択して起動する | [feature flag設定に基づきslotを選択して起動する](../並行稼働実行業務/並行稼働実行フロー/feature%20flag設定に基づきslotを選択して起動する/spec.md) の分岐条件一覧 | covered |
| hang_detect_limit_minutes | background roleごとの未完了許容しきい値（分）を超過し、かつexitcode.txt未出力の場合にハング疑いとして検知する | background実行の未完了・非0終了・速報比較異常を定期検知する | [background実行の未完了・非0終了・速報比較異常を定期検知する](../実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) の分岐条件一覧 | covered |

## バリエーションマトリクス

分母: バリエーション.tsv の `{バリエーション名}.{値}` ごと（18件）

| バリエーション名 | 値 | 適用 UC | 適用 Spec ファイル | カバー状態 |
|----------------|---|--------|-----------------|:---------:|
| 運用モード | 並行稼働 | feature flag設定に基づきslotを選択して起動する | [feature flag設定に基づきslotを選択して起動する](../並行稼働実行業務/並行稼働実行フロー/feature%20flag設定に基づきslotを選択して起動する/spec.md) のバリエーション一覧 | covered |
| 運用モード | 新実装単独本番 | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| 運用モード | 次世代実装との並行稼働 | feature flag設定に基づきslotを選択して起動する | 同上 | covered |
| slotモード（BLUE_MODE/GREEN_MODE） | off | feature flag設定に基づきslotを選択して起動する / background roleを起動する | 同上 / [background roleを起動する](../並行稼働実行業務/並行稼働実行フロー/background%20roleを起動する/spec.md) | covered |
| slotモード（BLUE_MODE/GREEN_MODE） | background | 同上 | 同上 | covered |
| slotモード（BLUE_MODE/GREEN_MODE） | foreground | 同上 | 同上 | covered |
| RAPID_CROSSCHECK_MODE | on | feature flag設定に基づきslotを選択して起動する | [feature flag設定に基づきslotを選択して起動する](../並行稼働実行業務/並行稼働実行フロー/feature%20flag設定に基づきslotを選択して起動する/spec.md) | covered |
| RAPID_CROSSCHECK_MODE | off | 同上 | 同上 | covered |
| role区分 | foreground | foreground roleの標準出力・標準エラー・終了コードを応答する | [foreground roleの標準出力・標準エラー・終了コードを応答する](../並行稼働実行業務/並行稼働実行フロー/foreground%20roleの標準出力・標準エラー・終了コードを応答する/spec.md) | covered |
| role区分 | background | 同上 / 再実行対象のbackground実行・速報比較依頼を選択する | 同上 / [再実行対象のbackground実行・速報比較依頼を選択する](../実行制御業務/background側リランフロー/再実行対象のbackground実行・速報比較依頼を選択する/spec.md) | covered |
| role区分 | rapid-crosscheck | 並行稼働実行結果を確認する | [並行稼働実行結果を確認する](../並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する/spec.md) | covered |
| クロスチェック種別 | 速報クロスチェック | 速報クロスチェックを実行し差分を検知する 他 | [速報クロスチェックを実行し差分を検知する](../クロスチェック業務/速報クロスチェックフロー/速報クロスチェックを実行し差分を検知する/spec.md) 他 | covered |
| クロスチェック種別 | 確報クロスチェック | 全テーブル・全ファイルを対象に確報クロスチェックを実行する 他 | [全テーブル・全ファイルを対象に確報クロスチェックを実行する](../クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する/spec.md) 他 | covered |
| slot種別 | blue | 並行稼働実行結果を確認する / blue background実行の中止を依頼する | [並行稼働実行結果を確認する](../並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する/spec.md) / [blue background実行の中止を依頼する](../実行制御業務/blue中止フロー/blue%20background実行の中止を依頼する/spec.md) | covered |
| slot種別 | green | 並行稼働実行結果を確認する / green background実行の中止を依頼する | 同上 / [green background実行の中止を依頼する](../実行制御業務/green中止フロー/green%20background実行の中止を依頼する/spec.md) | covered |
| 異常検知種別 | ハング疑い | background実行の未完了・非0終了・速報比較異常を定期検知する | [background実行の未完了・非0終了・速報比較異常を定期検知する](../実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) | covered |
| 異常検知種別 | background実行エラー | 同上 | 同上 | covered |
| 異常検知種別 | 速報クロスチェック異常 | 同上 | 同上 | covered |

## 状態遷移マトリクス

分母: 状態.tsv で「遷移UC」が非空の行（18件）

| 状態モデル | 遷移元 | 遷移先 | 適用 UC | 適用 Spec ファイル | カバー状態 |
|-----------|--------|--------|--------|-----------------|:---------:|
| background slot実行状態 | RUNNING | SUCCEEDED | background実行の未完了・非0終了・速報比較異常を定期検知する | [background実行の未完了・非0終了・速報比較異常を定期検知する](../実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) の状態遷移一覧 | covered |
| background slot実行状態 | RUNNING | FAILED | background実行の未完了・非0終了・速報比較異常を定期検知する | 同上 | covered |
| background slot実行状態 | RUNNING | ABORTED | 対話確認のうえblue background実行をABORTEDへ遷移させる | [対話確認のうえblue background実行をABORTEDへ遷移させる](../実行制御業務/blue中止フロー/対話確認のうえblue%20background実行をABORTEDへ遷移させる/spec.md) の状態遷移一覧 | covered |
| background slot実行状態 | RUNNING | ABORTED | 対話確認のうえgreen background実行をABORTEDへ遷移させる | [対話確認のうえgreen background実行をABORTEDへ遷移させる](../実行制御業務/green中止フロー/対話確認のうえgreen%20background実行をABORTEDへ遷移させる/spec.md) の状態遷移一覧 | covered |
| background slot実行状態 | SUCCEEDED | RUNNING | execution-spec.jsonの実行設定を保ったまま再実行する | [execution-spec.jsonの実行設定を保ったまま再実行する](../実行制御業務/background側リランフロー/execution-spec.jsonの実行設定を保ったまま再実行する/spec.md) の状態遷移一覧 | covered |
| background slot実行状態 | FAILED | RUNNING | execution-spec.jsonの実行設定を保ったまま再実行する | 同上 | covered |
| background slot実行状態 | ABORTED | RUNNING | execution-spec.jsonの実行設定を保ったまま再実行する | 同上 | covered |
| 速報比較依頼状態 | CLAIMED | RUNNING | 速報クロスチェックを実行し差分を検知する | [速報クロスチェックを実行し差分を検知する](../クロスチェック業務/速報クロスチェックフロー/速報クロスチェックを実行し差分を検知する/spec.md) の状態遷移一覧 | covered |
| 速報比較依頼状態 | RUNNING | SUCCEEDED | 速報クロスチェックを実行し差分を検知する | 同上 | covered |
| 速報比較依頼状態 | RUNNING | FAILED | 速報クロスチェックを実行し差分を検知する | 同上 | covered |
| 速報比較依頼状態 | RUNNING | ABORTED | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる | [対話確認のうえ速報比較依頼をABORTEDへ遷移させる](../実行制御業務/速報比較中止フロー/対話確認のうえ速報比較依頼をABORTEDへ遷移させる/spec.md) の状態遷移一覧 | covered |
| 速報比較依頼状態 | SUCCEEDED | REQUESTED | execution-spec.jsonの実行設定を保ったまま再実行する | [execution-spec.jsonの実行設定を保ったまま再実行する](../実行制御業務/background側リランフロー/execution-spec.jsonの実行設定を保ったまま再実行する/spec.md) の状態遷移一覧 | covered |
| 速報比較依頼状態 | FAILED | REQUESTED | execution-spec.jsonの実行設定を保ったまま再実行する | 同上 | covered |
| 速報比較依頼状態 | ABORTED | REQUESTED | execution-spec.jsonの実行設定を保ったまま再実行する | 同上 | covered |
| 確報比較依頼状態 | CLAIMED | RUNNING | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | [全テーブル・全ファイルを対象に確報クロスチェックを実行する](../クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する/spec.md) の状態遷移一覧 | covered |
| 確報比較依頼状態 | RUNNING | SUCCEEDED | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | 同上 | covered |
| 確報比較依頼状態 | RUNNING | FAILED | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | 同上 | covered |
| 確報比較依頼状態 | RUNNING | ABORTED | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる | [対話確認のうえ確報比較依頼をABORTEDへ遷移させる](../実行制御業務/確報比較中止フロー/対話確認のうえ確報比較依頼をABORTEDへ遷移させる/spec.md) の状態遷移一覧 | covered |

## 外部システム連携マトリクス

分母: 外部システム.tsv の各外部システム（3件）

| 外部システム名 | 役割 | 連携 UC | 連携 Spec ファイル | カバー状態 |
|-------------|------|--------|-----------------|:---------:|
| ジョブスケジューラ | 共通のジョブ定義からJOB_IDと追加引数を渡してfacadeを起動し、foreground実行結果だけを受け取る | foreground roleの標準出力・標準エラー・終了コードを応答する / 確報クロスチェック結果をstdout-stderr-exitcodeで応答する | [foreground roleの標準出力・標準エラー・終了コードを応答する](../並行稼働実行業務/並行稼働実行フロー/foreground%20roleの標準出力・標準エラー・終了コードを応答する/spec.md) / [確報クロスチェック結果をstdout-stderr-exitcodeで応答する](../クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果をstdout-stderr-exitcodeで応答する/spec.md) | covered |
| blue実装 | 既存実装（strangler対象）としてslotの一方を担い、Runner Result Contractに従った実行結果を出力する | background roleを起動する / feature flag設定に基づきslotを選択して起動する / blue background実行の中止を依頼する / 対話確認のうえblue background実行をABORTEDへ遷移させる / execution-spec.jsonの実行設定を保ったまま再実行する | [background roleを起動する](../並行稼働実行業務/並行稼働実行フロー/background%20roleを起動する/spec.md) 他 | covered |
| green実装 | 新実装（strangler移行先）としてslotの一方を担い、Runner Result Contractに従った実行結果を出力する | background roleを起動する / feature flag設定に基づきslotを選択して起動する / green background実行の中止を依頼する / 対話確認のうえgreen background実行をABORTEDへ遷移させる / execution-spec.jsonの実行設定を保ったまま再実行する | [background roleを起動する](../並行稼働実行業務/並行稼働実行フロー/background%20roleを起動する/spec.md) 他 | covered |

## 未カバー要素一覧

該当なし（全カテゴリ 100% 網羅済み）。

是正履歴（参考）:

| カテゴリ | 要素 | 想定される理由 | 対応方針 |
|---------|------|-------------|---------|
| バリエーションの値 | 運用モード（並行稼働／新実装単独本番／次世代実装との並行稼働） | 業務システム運用管理コンテキストのバリエーションであり、個々のUC設計時にBLUE_MODE/GREEN_MODEの組み合わせとしてしか暗黙的に表現されておらず、UC Specのトレーサビリティテーブルに明示行がなかった | 対応済み（パターンA）: `並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md` のバリエーション一覧・BDDシナリオに追記し、covered化した |

## BUC↔UC対応表

BUC.tsv の「BUC」列（9件）と実際に生成された23 UCの対応関係。1つのBUCが複数UCに分解されており、1:1対応ではない。

| BUC ID | BUC 名 | 対応する UC ID | 関係 |
|--------|--------|---------------|------|
| BUC-01 | 並行稼働実行フロー | feature flag設定に基づきslotを選択して起動する、background roleを起動する、foreground roleの標準出力・標準エラー・終了コードを応答する、並行稼働実行結果を確認する | 1:4（アクティビティ単位でUCに分解） |
| BUC-02 | 速報クロスチェックフロー | blue-green runnerの完了通知を受けて速報比較依頼を作成する、速報クロスチェックを実行し差分を検知する、速報クロスチェック結果を確認する | 1:3 |
| BUC-03 | 確報クロスチェックフロー | 全テーブル・全ファイルを対象に確報クロスチェックを実行する、確報クロスチェック結果をstdout-stderr-exitcodeで応答する、確報クロスチェック結果を確認する | 1:3 |
| BUC-04 | ハング監視フロー | background実行の未完了・非0終了・速報比較異常を定期検知する、ハング疑い・異常の通知を確認する、ハング疑い・異常を運用者へ通知する | 1:3 |
| BUC-05 | blue中止フロー | blue background実行の中止を依頼する、対話確認のうえblue background実行をABORTEDへ遷移させる | 1:2 |
| BUC-06 | green中止フロー | green background実行の中止を依頼する、対話確認のうえgreen background実行をABORTEDへ遷移させる | 1:2 |
| BUC-07 | 確報比較中止フロー | RUNNING中の確報比較依頼の中止を依頼する、対話確認のうえ確報比較依頼をABORTEDへ遷移させる | 1:2 |
| BUC-08 | 速報比較中止フロー | RUNNING中の速報比較依頼の中止を依頼する、対話確認のうえ速報比較依頼をABORTEDへ遷移させる | 1:2 |
| BUC-09 | background側リランフロー | 再実行対象のbackground実行・速報比較依頼を選択する、execution-spec.jsonの実行設定を保ったまま再実行する | 1:2 |

合計: BUC 9件 → UC 23件（4+3+3+3+2+2+2+2+2 = 23）。BUC.tsv にID列が存在しないため、BUC名を一意キーとしてBUC IDを付番した（並行稼働実行フローの登場順）。
