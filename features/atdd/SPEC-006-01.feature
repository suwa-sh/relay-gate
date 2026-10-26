# source: docs/usdm/latest/requirements.yaml#requirements[REQ-006].specifications[SPEC-006-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-006-01 確報クロスチェック runner はジョブスケジューラから業務上の引数なしで起動され(受け付けるのは実行補助のオプションだけ)、business_date や対象カタログの版などの業務パラメータを持たない確報比較依頼を 1 件登録し、対象依頼が終端状態(SUCCEEDED / FAILED / ABORTED)になるまで同期 polling する

  REQ-006: 確報クロスチェックが、ジョブスケジューラの別ジョブ定義から起動され、全テーブル・全ファイルを対象に日次整合性を正式確認し、stdout・stderr・exitcode をジョブスケジューラへ返すこと

  @atdd_SPEC-006-01-1
  Scenario: SPEC-006-01-1
    Given ジョブスケジューラが確報ジョブを引数なしで起動
    When runner が起動する
    Then final_crosscheck_request が REQUESTED で 1 件登録され、runner は終端状態まで待機する

  @atdd_SPEC-006-01-2
  Scenario: SPEC-006-01-2
    Given 確報 runner の引数
    When 引数の一覧を確認する
    Then business_date や対象カタログの版を渡す引数は無い
