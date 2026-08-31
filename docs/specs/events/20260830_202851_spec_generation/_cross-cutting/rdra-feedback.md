# RDRA フィードバック(Spec 生成時の発見事項)

> 生成: Step4d(トレーサビリティマトリクス + 網羅率是正)。対象 RDRA = `docs/rdra/latest/`。
> 網羅率は `traceability-matrix.md` を参照(合計 99.4%。未カバー 2 件はいずれも本ファイル対象(パターン B)。初回集計の未カバー 8 件のうち 6 件はパターン A として Spec 側に追記済み)。

## 変更要望一覧

| # | 種別 | 対象RDRA要素 | 変更内容 | 理由 |
|---|------|-------------|---------|------|
| 1 | 削除または移動 | 情報: ハング検知上限設定 の属性「調整日時」「調整根拠(最後の警告の経過時間)」 | ジョブマップの属性から外し、適用構成文書(運用者の調整記録)の属性へ移す | UC「slot ごとのジョブマップを定義する」tier-facade.md は `adjusted_at` / `adjustment_basis` をジョブマップ列に含めない判断(仮採用)。調整根拠は監視記録(`monitor_records` の警告時経過時間)から読み取り、記録の正本はジョブマップではなく適用文書またはコミット履歴。属性の置き場が RDRA と設計で食い違っている |
| 2 | 削除 | 情報: ジョブスケジューラ応答 の属性「応答日時」 | 不要 | 条件「実行履歴はジョブスケジューラの責務」により、応答時刻はジョブスケジューラの実行履歴が正本。facade は stdout / stderr / 終了コードだけを中継し、時刻を持たない(UC「foreground slot の結果をジョブスケジューラへ中継する」) |
| 3 | 変更 | バリエーション: 監視状態(未検知、ハング疑い、通知済み、通知後正常終了) | 状態モデル「監視状態」の 6 値(監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了)に揃える。または「通知後正常終了」を状態モデルの遷移(ハング疑い通知済み → 正常終了)の別名として説明列で明示する | 状態.tsv と バリエーション.tsv で同名「監視状態」の値集合が一致しない(_inference.md 確認推奨項目 11)。Spec は状態.tsv を正として `monitor_status` の英字コード 6 値を採用し、バリエーション「未検知」を MONITORING に対応させた(UC「監視記録を保存する」)。RDRA 側の二重定義を解消したい |
| 4 | 追加 | 状態: 並行稼働実行 の遷移 STARTED → ABORTED | 遷移「実行を ABORTED へ遷移させる」を STARTED からも許可する | 状態.tsv は RUNNING → ABORTED のみ。facade が parallel_run を STARTED で作成した直後(RUNNING 更新前)に中止された実行を取りこぼさないため、UC「実行を ABORTED へ遷移させる」は `status IN ('STARTED','RUNNING')` を条件にしている(spec.md 状態遷移一覧に注記済み) |
| 5 | 追加 | 状態: 並行稼働実行 の遷移 RUNNING → COMPLETED(遷移 UC の追加) | rapid-crosscheck リランで作成した parallel_run(UC「速報比較依頼だけを新規作成する」)の COMPLETED 遷移をどの UC が担うかを定義する(候補: UC「比較ツールでジョブ単位比較を実行して結果を登録する」で依頼の終端時に更新) | 状態.tsv の RUNNING → COMPLETED は「foreground slot の結果をジョブスケジューラへ中継する」だけが遷移 UC。リラン由来の parallel_run には foreground slot が無く、COMPLETED に到達する経路が未定義(buc-spec.md / spec.md に仮採用として注記済み) |
| 6 | 追加 | 情報: ハング検知定期ジョブ設定(hang-detector.env: 通知先・送信コマンド・DB 接続) | 新規追加(適用構成管理コンテキスト。設定所有区分の値にも追加) | UC「ハング疑い・実行エラー・比較異常を通知する」は通知メールの送信手段と宛先の設定を要する(_inference.md 確認推奨項目 10)が、RDRA の情報・設定所有区分(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 適用文書)に該当する置き場が無い |
| 7 | 追加 | 状態: 監視状態 の遷移 HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED | 状態.tsv に 3 遷移を追加する(遷移 UC: 「background 実行の経過時間と終了状態を判定する」「ハング疑い・実行エラー・比較異常を通知する」) | ハング疑い通知後に対象が終端した場合(速報比較依頼が NG / FAILED → COMPARE_ERROR_NOTIFIED、background slot が非 0 終了 → EXEC_ERROR_NOTIFIED、正常終了 → COMPLETED)の遷移が状態.tsv に無く、通知済み run が再判定されない・監視記録が未終端のまま残る欠陥になっていた(Step3 Round 2 G3 #1)。Spec 側は 3 遷移を追加して採用済み |
| 8 | 要否確認 | 条件 / BUC: 完了通知失敗の検知(速報クロスチェック runner への完了通知が失敗した run の検出・再通知) | 要件を追加するか、スコープ外を RDRA に明記するか判断する | 完了通知(rapid-crosscheck-runner.sh)の失敗は slot runner が実行ログに `WARN completion notice failed ...` を残すだけで(Runner Result 3 ファイルは変更しない)、自動検知・自動再通知は RDRA に要件が無いため Spec ではスコープ外とした。復旧は運用者が同一引数で rapid-crosscheck-runner.sh を再実行する(冪等・先勝ち)。片系完了のまま無音で残る run を検知したい場合は要件追加が必要(Step3 Round 2 G2 #1) |
| 9 | 確認 | 方針資料 C2「Hang Detection」図の `HangDetector -.-> FinalQueue` | 図の破線を削除するか、本文(監視対象は background slot と速報比較依頼)を改める | 方針資料の C2 図は hang-detector が確報依頼キューを参照するように読めるが、本文と Spec(cli-command-contract.yaml hang-detector.sh / asyncapi.yaml)では確報依頼は走査対象外。Spec は本文を正とし、確報依頼のハング監視は final-crosscheck-runner.sh の polling 上限(FINAL_POLL_LIMIT_SEC、既定 8 時間)で代替する仮採用(Step3 Round 2 G3 #13) |
| 10 | 変更 | USDM SPEC-001-01 本文の feature flag キー `BLUE_IMPL / GREEN_IMPL / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER` | feature flag 契約のキー(`BLUE_MODE` / `GREEN_MODE` / `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_MODE` / `CONFIG_VERSION`)に合わせて USDM 本文を見直す | cli-command-contract.yaml `config_files[feature-flag.env]` には上記 4 キーが無く、validate-config.sh は未知キーとして `warn:` を出す。USDM 本文と契約のキー名が食い違ったままだと受け入れ条件の照合(usdm-acceptance-matrix)で誤読を招く |
| 11 | 追加 | 状態: 監視状態 の遷移 MONITORING / HANG_SUSPECTED_NOTIFIED → COMPLETED(中止済み対象の終端)、バリエーション: ハング検知判定結果 の値集合 | (1) 状態.tsv に「監視対象(background slot 実行 / 速報比較依頼)が ABORTED になったとき、未終端の監視記録を COMPLETED で終端する」遷移を追加する(遷移 UC: 「background 実行の経過時間と終了状態を判定する」)。(2) バリエーション「ハング検知判定結果」を hang_judgement 6 値(NOT_TARGET / COMPLETED / MONITORING / HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR)に揃える(監視対象外 NOT_TARGET と正常終了・中止済み COMPLETED を分離) | 実行中止フロー(abort-blue / abort-green / abort-rapid-crosscheck)で ABORTED になった対象の監視記録が未終端のまま残り、再判定・再通知の対象になり続ける欠陥を防ぐため、Spec(cli-command-contract.yaml `hang-detector.sh` / `shared_rules.state_codes.hang_judgement`)は ABORTED を判定 COMPLETED として終端する仮採用を置いた(round-1 F-008 / F-010 / F-011)。#7 の 3 遷移と同じく状態.tsv に無い遷移であり、判定結果の値集合もバリエーション.tsv と食い違う |
| 12 | 追加 | 条件: 「comparison_results の登録条件」(比較結果は比較ツールを起動して終了コードを得たときだけ登録する。比較定義なし・起動失敗では登録しない) | 条件.tsv に追加する(または既存条件「比較ツール終了コードの対応」の説明に「終了コードを得られない場合は比較結果を登録せず依頼だけ FAILED で終端する」を追記する)。関連 UC: 「比較ツールでジョブ単位比較を実行して結果を登録する」 | round-1 F-017 の修正で Spec 側(cli-command-contract.yaml `rapid-crosscheck-worker.sh.idempotency`、同 UC spec.md 分岐条件一覧)に新設した条件名で、RDRA 条件.tsv に存在しないためトレーサビリティ集計で孤立する(round-2 F-116)。RDRA 更新までは Spec の条件名に「(spec 追加)」を付して扱う |

## 対応方針

- 本フィードバックは `dist-requirements`(差分モード)で RDRA を差分更新し、影響する UC の Spec を再生成する
- Spec 側は上記の判断を仮採用値として既に反映しており、RDRA 更新までは Spec の記述(状態.tsv 準拠の英字コード、STARTED → ABORTED の許容、hang-detector.env)を実装の正本とする
- #1 / #2 は traceability-matrix.md の未カバー要素一覧で「RDRA フィードバック対象」として注記した。#3〜#6 は網羅率の分母に影響しない(RDRA 側に要素が無い、または値の名称差)ため未カバー要素には現れない

## 後工程・スキルへの変更要求(RDRA 対象外)

> Step6.5 反証レビュー(round-1)で挙がったスキーマ拡張要求。RDRA の変更ではなく distillery スキル(dist-spec)のスキーマと後工程(distillery-impl)への要望であるため、本イベントでは修正せずここに記録する。対応先は `dist-spec` のスキーマ更新(次版)。

| # | 由来 | 対象 | 変更要求 | 理由 |
|---|------|------|---------|------|
| SR-001 | round-1 F(minor) | dist-spec スキーマ `schema-spec-event.json`(`use_cases[]`)/ `schema-api-summary.json` | `use_cases[]` に `usdm: [{req_id, spec_id, scenarios: [..]}]`(または `_api-summary.yaml` に `usdm_refs`)を追加し、生成時に spec.md「関連 USDM」表と同内容を YAML にも出す。`validateSpecEvent.js` で spec_id の USDM 実在チェックを行う | UC → USDM SPEC ID / acceptance_criteria の対応が各 spec.md の Markdown 表にしか無く、後工程(distillery-impl の ATDD 生成・`usdm-acceptance-matrix.md` の再生成)が Markdown 表を再パースしている。機械可読フィールドが無いため照合の自動検証ができない |
| SR-002 | round-1 F(minor) | dist-spec スキーマ `schema-rdb-schema.json`(`columns[]`) | `columns[]` に任意の `enum: [..]` を追加し、`rdb-schema.yaml` の列挙列(status / completion_status / monitor_status / slot / mode / role / target_type / comparison_type)に機械可読な enum を持たせる。`cli-command-contract.yaml` `shared_rules.state_codes` はそれを参照(または生成)する形にして二重管理を解消する | 列挙値が description の日本語文中にしか無く、bash 定数・SQL DDL(CHECK 制約)の codegen が description を正規表現で拾うか `shared_rules.state_codes` と手で突き合わせるしかない。本イベントでは `shared_rules.state_codes` を正として description の値集合を手動で揃えている |

- スキーマ更新までの暫定: 列挙値の正本は `cli-command-contract.yaml` `shared_rules.state_codes`、USDM 対応の正本は各 spec.md「関連 USDM」表 + `_cross-cutting/usdm-acceptance-matrix.md` とする
