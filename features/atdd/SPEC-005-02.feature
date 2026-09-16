# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-02 速報クロスチェック runner は、blue と green の両方が成功したときに限り比較依頼を一意に作成する。blue / green の完了順にかかわらず比較依頼は 1 件だけ作られる。いずれかが失敗した場合は比較依頼を作成せず終了する。並行稼働実行(parallel_run)が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(成果物ディレクトリに aborted.txt が公開済み)のいずれかに該当する中止済み run では、後から完了通知を受けても速報比較依頼を作成しない。並行稼働実行は foreground slot の結果を中継した時点で COMPLETED になるため、foreground 完了後に background slot を abort-blue / abort-green で中止した run もこの判定で除外する。判定材料は管理 DB の parallel_run.status と slot_executions.status(ファイル正本 aborted.txt のミラー)とする。完了事実(blue_status / green_status と成果物 URI)は記録し、実行ログに警告を残す。この判断は速報クロスチェック runner(dispatcher)が行い、slot runner は行わない。RAPID_CROSSCHECK_MODE=off では完了通知も比較依頼も存在しないため、この規則は速報有効時だけに適用する

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-02-1
  Scenario: SPEC-005-02-1
    Given blue と green が両方成功で完了
    When 後に完了した側の通知が届く
    Then 比較依頼が 1 件だけ作成される

  @atdd_SPEC-005-02-2
  Scenario: SPEC-005-02-2
    Given green が先に完了し blue が後に完了
    When 両通知が処理される
    Then 比較依頼は重複せず 1 件である

  @atdd_SPEC-005-02-3
  Scenario: SPEC-005-02-3
    Given blue が非 0 で終了
    When green が成功で完了する
    Then 比較依頼は作成されない

  @atdd_SPEC-005-02-4
  Scenario: SPEC-005-02-4
    Given 並行稼働実行が ABORTED
    When 後から完了通知を受ける
    Then 速報比較依頼は作成されず、完了事実だけが記録される

  @atdd_SPEC-005-02-5
  Scenario: SPEC-005-02-5
    Given 並行稼働実行は COMPLETED だが対象 slot の slot 実行が ABORTED
    When 後から完了通知を受ける
    Then 速報比較依頼は作成されず、完了事実だけが記録される

  @atdd_SPEC-005-02-6
  Scenario: SPEC-005-02-6
    Given foreground の blue が完了して並行稼働実行が COMPLETED になった後に background の green を abort-green で中止した
    When green の実装が走り切って完了通知を送る
    Then 速報比較依頼は作成されず、実行ログに警告が残る

  @atdd_SPEC-005-02-7
  Scenario: SPEC-005-02-7
    Given 並行稼働実行が ABORTED で片系が成功済み
    When もう片系の完了通知を受ける
    Then 両系成功でも速報比較依頼は作成されず、実行ログに警告が残る

  @atdd_SPEC-005-02-8
  Scenario: SPEC-005-02-8
    Given 中止した run を background-rerun でリランした
    When 新しい run の両系が成功する
    Then 新しい run_id で速報比較依頼が作成される

  @atdd_SPEC-005-02-9
  Scenario: SPEC-005-02-9
    Given abort-blue で ABORTED にした slot の実装が走り切って exitcode.txt を公開した
    When 管理 DB を確認する
    Then slot_executions.status は ABORTED のままである
