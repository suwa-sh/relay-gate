# 変更サマリ

- event_id: 20260819_104301_slot_config_comparison_def_exitcode
- 元USDM: 20260819_104301_slot_config_comparison_def_exitcode
- 生成日時: 2026-08-19T10:43:01

```yaml
feedback_request:
  feedback_request_id: "20260818_164000_rdra_followup_6078c4ed"
  input_sha256: "b4b730a7e786c58c6d949948b78ce20988e293d795ae752239a546e36557bf72"
  request_ids: ["CR-6078c4ed-008","CR-6078c4ed-009","CR-6078c4ed-010"]
  work_unit_ids: ["CR-6078c4ed-008#1","CR-6078c4ed-009#1","CR-6078c4ed-010#1"]
```

## 追加

- 情報: slot別実行設定（属性: run_id, slot種別（blue/green）, ホスト, 実行ユーザー, スクリプト, 作業ディレクトリ, 固定引数, 実装版, 認証情報参照名。run共通のexecution-spec.jsonから分離し、run_idとslot種別で一意に識別する）
- 情報: 比較定義（属性: JOB_ID, 比較対象テーブル, 比較対象ファイル, 比較実装識別子, 有効期間。速報・確報クロスチェックの双方が実行時に参照する）
- 条件: relay-gateエラーの退避終了コード（実行結果未確定・取得不能・中止済み = 125、バリデーションエラー = 124。bashが自動生成する126/127との衝突を避けて予約する。foregroundのexitcode.txt値は0を含む全値を透過する）
- 状態: background slot実行状態 → STARTING → RUNNING の遷移を追加（遷移UC: background roleを起動する）
- 状態: background slot実行状態 → STARTING → UNKNOWN / RUNNING → UNKNOWN の遷移を追加（遷移UC: background実行の未完了・非0終了・速報比較異常を定期検知する。timeoutや結果取得不能では推測でFAILEDを確定しない）
- 状態: background slot実行状態 → UNKNOWN → SUCCEEDED / UNKNOWN → FAILED の回復遷移を追加（遷移UC: background実行の未完了・非0終了・速報比較異常を定期検知する。実結果の回収により確定する）
- 状態: background slot実行状態 → UNKNOWN → ABORTED の遷移を追加（遷移UC: 対話確認のうえblue background実行をABORTEDへ遷移させる / 対話確認のうえgreen background実行をABORTEDへ遷移させる）
- BUC: 並行稼働実行フロー → UC「feature flag設定に基づきslotを選択して起動する」「background roleを起動する」に情報「slot別実行設定」を追加
- BUC: 並行稼働実行フロー → UC「foreground roleの標準出力・標準エラー・終了コードを応答する」に条件「relay-gateエラーの退避終了コード」を追加
- BUC: background側リランフロー → UC「execution-spec.jsonの実行設定を保ったまま再実行する」に情報「slot別実行設定」を追加
- BUC: 速報クロスチェックフロー → UC「速報クロスチェックを実行し差分を検知する」に情報「比較定義」を追加
- BUC: 確報クロスチェックフロー → UC「全テーブル・全ファイルを対象に確報クロスチェックを実行する」に情報「比較定義」を追加

## 変更

- 情報: execution-spec.json → 属性からslot別の項目（ホスト, 実行ユーザー, スクリプト, 作業ディレクトリ, 固定引数, 実装版, 認証情報参照名）を除き、run共通の実行設定（run_id, parent_run_id, JOB_ID, 追加引数, マップ版, hang_detect_limit_minutes）に変更。関連情報へ「slot別実行設定」を追加
- 情報: Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） → 属性へ起動試行identity（attempt_id, attempt_no, 起動受付時刻（accepted_at））を追加し、実行状態をSTARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTEDの6値へ変更。関連情報へ「slot別実行設定」を追加
- 状態: background slot実行状態 → 初期遷移の遷移先をRUNNINGからSTARTINGへ変更（2行: 遷移UCなしの初期遷移、および遷移UC「execution-spec.jsonの実行設定を保ったまま再実行する」の初期遷移）

## 削除

- なし

状態.tsv のマージは「コンテキスト + 状態モデル + 状態 + 遷移UC + 遷移先状態」で行を特定する。
初期遷移の変更は、状態が空の 2 行（遷移UCなし / 遷移UC「execution-spec.jsonの実行設定を保ったまま再実行する」）を
遷移UC で区別して遷移先状態のみを RUNNING → STARTING に置き換える。
同じ状態キーを持つ他の遷移行・終端説明行は変更しない。
