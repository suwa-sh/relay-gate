# source: docs/usdm/latest/requirements.yaml#requirements[REQ-006].specifications[SPEC-006-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-006-03 確報クロスチェック runner は、完了した依頼に保存された stdout・stderr・exitcode をそのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ返す。チェック結果・差分件数・レポート URI などを stdout・stderr・exitcode 以外の連携データとして追加せず、依頼の管理状態名(SUCCEEDED / FAILED / ABORTED)も返さない

  REQ-006: 確報クロスチェックが、ジョブスケジューラの別ジョブ定義から起動され、全テーブル・全ファイルを対象に日次整合性を正式確認し、stdout・stderr・exitcode をジョブスケジューラへ返すこと

  @atdd_SPEC-006-03-1
  Scenario: SPEC-006-03-1
    Given 依頼が exitcode=3 で FAILED になった
    When runner が応答する
    Then ジョブスケジューラは保存済み stdout・stderr と終了コード 3 を受け取り、それ以外の連携データを受け取らない

  @atdd_SPEC-006-03-2
  Scenario: SPEC-006-03-2
    Given 依頼が ABORTED になった
    When runner が応答する
    Then 保存済み stdout・stderr・exitcode だけが返り、状態名は返らない
