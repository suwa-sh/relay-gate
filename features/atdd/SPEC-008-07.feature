# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-07].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-07 ハング検知は、その回の見回りで新たに見つけた background 異常を、ハング検知ジョブ自身の終了結果で知らせる。運用者にはジョブスケジューラの既存のジョブ監視・障害通知で届く。見回り・判定・監視記録の保存は SPEC-008-01〜03 のまま続け、自動中止・自動再実行をしない(SPEC-008-04)。新たな異常が無ければ終了コード 0 で終わる。注意(ハング疑い)は警告終了、異常(background 実行エラー・速報クロスチェック異常)は失敗として終了コードで区別し、同じ回に両方を見つけた場合は失敗で終わる。警告終了の値は確報の比較 NG と同じ考え方(ジョブステータスが警告終了になる値)とし、具体的な値は CLI 契約で確定する。見つけた異常は標準エラーに 1 件 1 行で出し、行には対象(run_id と role、または速報比較依頼)、段階(warning / error)、経過時間を含める。通知済みの異常は次回以降の見回りで再び知らせず、その判定は監視記録の遷移規則を使う。RAPID_CROSSCHECK_MODE=off では監視記録の代わりに、ハング検知が成果物ルート配下へ通知済みの印をファイルで残し、同じ規則で判定する。印は Runner Result の契約ファイル(stdout.log / stderr.log / exitcode.txt / execution-spec.json / started-at.txt / aborted.txt)とは別のファイルにし、一時ファイルからのリネームで書く。印の置き場所とファイル名は仕様で確定する。通知の判定が終わったあとで監視記録または印の保存に失敗した場合は、その異常を次回も知らせる(知らせ漏れより重複を選ぶ)。経過時間の傾向の確認は、ハング検知ジョブの出力と監視記録で行う

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を、ハング検知ジョブ自身の終了結果と標準エラーで運用者へ知らせること

  @atdd_SPEC-008-07-1
  Scenario: SPEC-008-07-1
    Given 新たな background 異常が無い
    When ハング検知ジョブが実行される
    Then 終了コード 0 で終わり、標準エラーに異常の行は出ない

  @atdd_SPEC-008-07-2
  Scenario: SPEC-008-07-2
    Given 新たに見つけた異常がハング疑いだけである
    When ハング検知ジョブが実行される
    Then ジョブステータスが警告終了になる終了コードで終わり、標準エラーにハング疑いの対象ごとに warning の行が 1 行ずつ出る

  @atdd_SPEC-008-07-3
  Scenario: SPEC-008-07-3
    Given background 実行エラーまたは速報クロスチェック異常を新たに見つけた
    When ハング検知ジョブが実行される
    Then 0 とも警告終了の値とも異なる失敗を表す終了コードで終わり、標準エラーに異常の対象ごとに error の行が 1 行ずつ出る

  @atdd_SPEC-008-07-4
  Scenario: SPEC-008-07-4
    Given 同じ見回りでハング疑いと background 実行エラーを新たに見つけた
    When ハング検知ジョブが実行される
    Then 失敗を表す終了コードで終わり、標準エラーに warning の行と error の行がそれぞれ 1 件 1 行で出る

  @atdd_SPEC-008-07-5
  Scenario: SPEC-008-07-5
    Given ハング検知ジョブが標準エラーに出した異常の行
    When 行の内容を確認する
    Then 対象(run_id と role、または速報比較依頼)、段階(warning / error)、経過時間が含まれる

  @atdd_SPEC-008-07-6
  Scenario: SPEC-008-07-6
    Given 管理 DB を使う設定(RAPID_CROSSCHECK_MODE が off 以外)で、前回の見回りで通知した異常の状態がその後変わっていない
    When 2 回目の見回りでハング検知ジョブが実行される
    Then 同じ異常の行は標準エラーに出ず、ほかに新たな異常が無ければ終了コード 0 で終わる

  @atdd_SPEC-008-07-7
  Scenario: SPEC-008-07-7
    Given RAPID_CROSSCHECK_MODE=off で、前回の見回りで通知した異常の状態がその後変わっていない
    When 2 回目の見回りでハング検知ジョブが実行される
    Then 同じ異常の行は標準エラーに出ず、ほかに新たな異常が無ければ終了コード 0 で終わる

  @atdd_SPEC-008-07-8
  Scenario: SPEC-008-07-8
    Given RAPID_CROSSCHECK_MODE=off で異常を通知した
    When 成果物ルート配下を確認する
    Then 通知済みの印が残っており、Runner Result の契約ファイル(stdout.log / stderr.log / exitcode.txt / execution-spec.json / started-at.txt / aborted.txt)の内容は変わっていない

  @atdd_SPEC-008-07-9
  Scenario: SPEC-008-07-9
    Given 異常を通知したが、その回の監視記録(RAPID_CROSSCHECK_MODE=off では通知済みの印)の保存に失敗した
    When 次の見回りでハング検知ジョブが実行される
    Then 同じ異常の行が再び標準エラーに出て、その段階に応じた終了コードで終わる
