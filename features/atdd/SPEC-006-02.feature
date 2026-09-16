# source: docs/usdm/latest/requirements.yaml#requirements[REQ-006].specifications[SPEC-006-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-006-02 確報クロスチェック worker は DB セグメントで依頼を poll / claim し、比較ツールで全テーブル・全ファイルの比較を起動し、起動した実装の stdout・stderr・exitcode を依頼レコードへ保存する。exitcode が 0 なら SUCCEEDED、非 0 または実行エラーなら FAILED とする

  REQ-006: 確報クロスチェックが、ジョブスケジューラの別ジョブ定義から起動され、全テーブル・全ファイルを対象に日次整合性を正式確認し、stdout・stderr・exitcode をジョブスケジューラへ返すこと

  @atdd_SPEC-006-02-1
  Scenario: SPEC-006-02-1
    Given REQUESTED の確報比較依頼
    When worker が claim して比較を完了する
    Then 依頼に stdout・stderr・exitcode が保存され、exitcode=0 で SUCCEEDED、非 0 で FAILED になる
