# 変更サマリ

- event_id: 20260905_083000_feedback_todo_resolution
- 元USDM: docs/usdm/events/20260905_083000_feedback_todo_resolution/requirements.yaml
- 生成日時: 2026-09-05T08:30:00
- feedback request: 20260905_todo_resolution(direct / causal work unit: CR-c770d8f0-001#1 〜 CR-c770d8f0-011#1。packet: docs/pipeline/feedback-runs/20260905_todo_resolution/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20260905_todo_resolution"
  input_sha256: "285429579e9c9d28307d4c779317f01941b915a1203d0e5b5f53a6c014ed7108"
  request_ids: ["CR-c770d8f0-001","CR-c770d8f0-002","CR-c770d8f0-003","CR-c770d8f0-004","CR-c770d8f0-005","CR-c770d8f0-006","CR-c770d8f0-007","CR-c770d8f0-008","CR-c770d8f0-009","CR-c770d8f0-010","CR-c770d8f0-011"]
  work_unit_ids: ["CR-c770d8f0-001#1","CR-c770d8f0-002#1","CR-c770d8f0-003#1","CR-c770d8f0-004#1","CR-c770d8f0-005#1","CR-c770d8f0-006#1","CR-c770d8f0-007#1","CR-c770d8f0-008#1","CR-c770d8f0-009#1","CR-c770d8f0-010#1","CR-c770d8f0-011#1"]
```

マージ規則の補足: BUC.tsv は BUC + UC のグループ単位、状態.tsv はコンテキスト + 状態モデル + 状態のグループ単位で、イベント側の行集合が latest の同グループを置き換える(グループ内の行の追加・削除を含む)。

## 追加

- 情報: ハング検知定期ジョブ設定（属性: 通知先メールアドレス, 送信コマンド, 件名プレフィックス, 管理 DB 接続参照名。関連: 通知メール, 監視記録, 適用構成文書。所有者: 基盤適用設計者）(CR-c770d8f0-010)
- 状態: 並行稼働実行 STARTED → ABORTED（遷移UC: 実行を ABORTED へ遷移させる）(CR-c770d8f0-009)
- 状態: 並行稼働実行 RUNNING → COMPLETED（遷移UC: 比較ツールでジョブ単位比較を実行して結果を登録する。速報比較依頼だけを新規作成したリラン由来 run の終端）(CR-c770d8f0-009)
- 状態: 並行稼働実行 RUNNING → COMPLETED（遷移UC: 実装スクリプトを実行して Runner Result を出力する。background slot リラン由来 run の終端）(CR-c770d8f0-009)
- 状態: 監視状態 ハング疑い通知済み → 比較異常通知済み（遷移UC: ハング疑い・実行エラー・比較異常を通知する）(CR-c770d8f0-008)
- 条件: slot 実行の状態導出規則（exitcode.txt があれば SUCCEEDED(0) / FAILED(非 0)、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING）(CR-c770d8f0-004)
- 条件: 完了通知失敗の扱い（送信失敗は自動検知しない。slot runner は実行ログに警告を残し Runner Result と終了コードは変更しない。復旧は運用者が速報クロスチェック runner を同一引数で再実行）(CR-c770d8f0-005)
- 条件: 比較結果の登録条件（比較ツールを起動して終了コードを得たときだけ comparison_result を登録。比較定義なし・起動失敗では登録せず依頼だけ FAILED(exit_code=6 相当)で終端）(CR-c770d8f0-011)

## 変更

- 情報: feature flag 設定 → 属性を元資料の 9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)に揃え、設定版を削除。RAPID_CROSSCHECK_MODE を foreground / background / off に変更(CR-c770d8f0-001)
- 情報: ジョブマップ → 形式を CSV(1 行目ヘッダー、1 行 1 job_id)とし、属性名を元資料の列名(job_id / host / user / work_dir / script / fixed_params / hang_detect_limit_minutes)に統一。fixed_params の JSON 配列セル規則(二重引用符で囲み内部の二重引用符は二重化)を明記。credential_ref / map_version は末尾の任意列、実装版列は削除(CR-c770d8f0-002)
- 情報: クロスチェックジョブマップ → 形式を slot ジョブマップと同じ CSV に統一(CR-c770d8f0-002)
- 情報: 対象カタログ → 形式を slot ジョブマップと同じ CSV に統一(CR-c770d8f0-002)
- 情報: 実行設定(execution-spec) → 実装版の出所を feature flag の BLUE_IMPL / GREEN_IMPL、マップ版の出所をジョブマップ側の版と明記(CR-c770d8f0-001)
- 情報: 並行稼働実行(parallel_run) → run_id 属性に形式({ローカルタイムゾーンの yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}、Z 無し)を明記(CR-c770d8f0-003)。STARTED からの ABORTED とリラン由来 run の COMPLETED 到達を説明に追記(CR-c770d8f0-009)
- 情報: Runner Result → 属性に aborted.txt(中止日時 1 行。中止時のみ生成)を追加し、slot 実行の状態をファイル正本から導出する旨を明記(CR-c770d8f0-004)
- 情報: slot 実行 → 状態導出規則(exitcode.txt / aborted.txt)を説明に反映(CR-c770d8f0-004)
- 情報: ハング検知上限設定 → 属性から調整日時・調整根拠を削除し、調整記録の置き場を適用構成文書に移す(CR-c770d8f0-007)
- 情報: 適用構成文書 → 属性に運用者の調整記録(調整日時、調整根拠となる警告時経過時間)を追加(CR-c770d8f0-007)
- 情報: ジョブスケジューラ応答 → 属性から応答日時を削除(CR-c770d8f0-007)
- 情報: 監視記録 → monitor_status の値説明を状態モデル「監視状態」の 6 値と一致させ、通知後・中止後の終端を明記。関連情報にハング検知定期ジョブ設定を追加(CR-c770d8f0-008 / CR-c770d8f0-010)
- 情報: 通知メール → 宛先・送信コマンドの出所としてハング検知定期ジョブ設定を関連付け(CR-c770d8f0-010)
- 状態: slot 実行 RUNNING → ABORTED → 説明に aborted.txt の書き込みと off 以外での管理 DB 更新を追加(CR-c770d8f0-004)
- 状態: 監視状態 監視中 → 正常終了 / ハング疑い通知済み → 正常終了 → 監視対象が ABORTED になった場合の中止済み終端と「通知後正常終了」の別名を説明に追加(CR-c770d8f0-008)
- 条件: 速報クロスチェック有効判定 → RAPID_CROSSCHECK_MODE の値を foreground / background / off で判定するよう変更(CR-c770d8f0-001)
- 条件: ジョブマップ解決条件 → CSV 形式・元資料の列名・fixed_params セルの解析規則を明記(CR-c770d8f0-002)
- 条件: slot 中止可否判定 → 中止の記録先を aborted.txt とし、off モードでも中止が成立することを明記(CR-c770d8f0-004)
- 条件: ハング検知判定 → aborted.txt がある対象の終端を追記(CR-c770d8f0-004)
- 条件: リラン事前検証 → RUNNING の判定をファイル正本(exitcode.txt / aborted.txt)で行うことを明記(CR-c770d8f0-004)
- 条件: 設定所有区分 → ハング検知定期ジョブ設定と調整記録の所有区分を追加(CR-c770d8f0-010 / CR-c770d8f0-007)
- バリエーション: 速報クロスチェックモード → 値を foreground / background / off の 3 値に変更(CR-c770d8f0-001)
- バリエーション: 運用モード → 速報の値を on から background に変更(CR-c770d8f0-001)
- バリエーション: Runner Result 成果物種別 → aborted.txt を追加(CR-c770d8f0-004)
- バリエーション: 監視状態 → 値を状態モデル「監視状態」の 6 値に統一し、「通知後正常終了」を遷移の別名として説明に記載(CR-c770d8f0-008)
- バリエーション: ハング検知判定結果 → 値を 6 値(監視対象外 / 正常終了または中止済み / 監視中 / ハング疑い / 実行エラー / 比較異常)に統一(CR-c770d8f0-008)
- バリエーション: 設定所有区分 → ハング検知定期ジョブ設定(所有者: 基盤適用設計者)を追加(CR-c770d8f0-010)
- BUC: 適用構成定義フロー → UC「feature flag を設定する」の説明を元資料の 9 キー・3 値に更新(CR-c770d8f0-001)
- BUC: 実行中止フロー / background 側リランフロー / background 実行監視フロー → UC「実行を ABORTED へ遷移させる」「リラン対象を検証する」「background 実行の経過時間と終了状態を判定する」に条件「slot 実行の状態導出規則」(と Runner Result)を関連付け、中止 UC の説明に aborted.txt を追記(CR-c770d8f0-004)
- BUC: 速報クロスチェックフロー → UC「速報クロスチェック runner へ完了通知を送信する」に条件「完了通知失敗の扱い」と情報「実行ログ」を関連付け(CR-c770d8f0-005)
- BUC: 速報クロスチェックフロー → UC「比較ツールでジョブ単位比較を実行して結果を登録する」に条件「比較結果の登録条件」を関連付け(CR-c770d8f0-011)
- BUC: background 実行監視フロー → UC「ハング疑い・実行エラー・比較異常を通知する」の入力情報に「ハング検知定期ジョブ設定」を追加(CR-c770d8f0-010)
- BUC: background 実行監視フロー → UC「hang_detect_limit_minutes をジョブごとに調整する」に情報「適用構成文書」を関連付け(CR-c770d8f0-007)
- BUC: background 実行監視フロー → UC「ハング疑い・実行エラー・比較異常を通知する」の説明に通知後の終端遷移を追記(CR-c770d8f0-008)
- BUC: background 側リランフロー → リラン由来 parallel_run の COMPLETED 到達経路を UC 説明に追記(CR-c770d8f0-009)
- システム概要: system_overview → 管理 DB(RDB)を relay-gate 内部のジョブキュー兼管理 DB(内部構成要素)として明記し、feature flag の 9 キーを記載(CR-c770d8f0-006 / CR-c770d8f0-001)

## 削除

- 外部システム: 管理 DB(RDB)（relay-gate 内部のジョブキュー兼管理 DB としてシステム概要に記載。リモート実行ホスト(SSH)は外部システムのまま維持）(CR-c770d8f0-006)
- BUC: 外部システム「管理 DB(RDB)」への関連行 17 件（UC: slot 実行モードを選択して runner を起動する / 速報比較結果を参照する / 速報クロスチェック runner へ完了通知を送信する / 両系成功時に速報比較依頼を作成する / 速報比較依頼を claim する / 比較ツールでジョブ単位比較を実行して結果を登録する / 確報比較依頼を登録して終端状態まで待機する / 確報比較依頼を claim する / 比較ツールで日次全量比較を実行して結果を保存する / 保存済みの確報結果をジョブスケジューラへ返す / background 実行の経過時間と終了状態を判定する / 監視記録を保存する / 実行を ABORTED へ遷移させる / リラン結果を parent_run_id で追跡する / リラン対象を検証する / 元の execution-spec.json から復元して新しい run_id で起動する / 速報比較依頼だけを新規作成する）。管理 DB は relay-gate 内部のデータストアとして扱う(CR-c770d8f0-006)
