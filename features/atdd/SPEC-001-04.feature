# source: docs/usdm/latest/requirements.yaml#requirements[REQ-001].specifications[SPEC-001-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-001-04 blue / green の runner は設定で実体スクリプトを割り当て、実装固有の起動方式・ホスト・OS・プロトコルを slot の runner に閉じ込める。runner を差し替えることで異なる世代の実装を並行稼働できる。relay-gate は、そのまま BLUE_RUNNER / GREEN_RUNNER に割り当てられる標準の slot runner を、正式な提供物として提供する。標準の slot runner は、slot ジョブマップの行に従い、ローカル実行(host と user が両方空の行)と SSH 実行(それ以外の行)の両方を扱い、runner の外部 IF(引数、--help の応答、Runner Result Contract の 3 ファイルと execution-spec.json、完了通知)を満たす。標準の slot runner を使う適用で利用者が用意するものは、feature flag と slot ジョブマップ(と実行先の実装)だけとし、runner のスクリプトを書く必要はない。標準の slot runner が扱わない起動方式・プロトコル(特殊な接続)は、これまでどおり利用者が runner を自作して割り当てられる。自作する runner のための共通ライブラリの提供と runner の外部 IF は残す。標準の slot runner を「参考実装(仮採用)」としては扱わない。標準の slot runner のファイル構成(blue 用と green 用を 1 つの実体で兼ねるか、ファイル名、置き場所、feature flag への書き方の例)は仕様で 1 つに確定する(推奨は、1 つの実体を blue と green の両方に割り当てられる形)。元の方針資料は「BLUE_RUNNER と GREEN_RUNNER は適用ごとに実体を割り当てる」とし、標準の runner の提供には触れていない。標準の slot runner の正式な提供は利用者決定(2026-11-16)であり、割り当てる実体として標準の slot runner を選べる形で方針資料の記述と両立させる

  REQ-001: ジョブスケジューラの同一ジョブ定義から、feature flag の設定だけで現行実装(blue)と新実装(green)の並行稼働・単独本番を切り替えられること

  @atdd_SPEC-001-04-1
  Scenario: SPEC-001-04-1
    Given BLUE_RUNNER / GREEN_RUNNER に実体スクリプトのパスが設定されている
    When facade が slot を起動する
    Then facade は実装固有の起動方式を判断せず、設定された runner を起動する

  @atdd_SPEC-001-04-2
  Scenario: SPEC-001-04-2
    Given green runner を次世代実装用に差し替える
    When feature flag と runner 設定だけを変更する
    Then facade と比較規約を変更せずに並行稼働できる

  @atdd_SPEC-001-04-3
  Scenario: SPEC-001-04-3
    Given BLUE_RUNNER と GREEN_RUNNER に relay-gate が提供する標準の slot runner を割り当て、blue と green の slot ジョブマップを置いた feature flag 設定
    When 設定を検証する
    Then エラーにならず終了コード 0 で終わる

  @atdd_SPEC-001-04-4
  Scenario: SPEC-001-04-4
    Given 標準の slot runner を割り当てた slot で、slot ジョブマップの JOB_ID の行の host と user が両方空である
    When facade がその slot を起動する
    Then ジョブマップの script が facade と同じホストでローカル実行され、その slot の成果物ディレクトリに stdout.log / stderr.log / exitcode.txt が揃い、execution-spec.json に解決した実行先が記録される

  @atdd_SPEC-001-04-5
  Scenario: SPEC-001-04-5
    Given 標準の slot runner を割り当てた slot で、slot ジョブマップの JOB_ID の行に host と user がある
    When facade がその slot を起動する
    Then ジョブマップの script がその host でその user として SSH で実行され、その slot の成果物ディレクトリに stdout.log / stderr.log / exitcode.txt が揃う

  @atdd_SPEC-001-04-6
  Scenario: SPEC-001-04-6
    Given ローカル実行と SSH 実行だけで足りる適用
    When BLUE_RUNNER と GREEN_RUNNER に標準の slot runner を割り当てて並行稼働を構成する
    Then 利用者が用意するものは feature flag と slot ジョブマップ(と実行先の実装)だけで、runner のスクリプトを書かずに blue と green の実装が起動される

  @atdd_SPEC-001-04-7
  Scenario: SPEC-001-04-7
    Given 標準の slot runner が扱わない起動方式・プロトコルで動く実装
    When 利用者が共通ライブラリを使って runner の外部 IF を満たす runner を自作し、BLUE_RUNNER または GREEN_RUNNER に割り当てる
    Then facade を変更せずにその runner が起動され、その slot の成果物ディレクトリに stdout.log / stderr.log / exitcode.txt が揃う

  @atdd_SPEC-001-04-8
  Scenario: SPEC-001-04-8
    Given relay-gate の提供物の一覧
    When slot runner の位置づけを確認する
    Then 標準の slot runner は正式な提供物として載っており、参考実装(仮採用)という扱いの runner は無い
