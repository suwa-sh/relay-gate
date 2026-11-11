# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-03 実行の単位を消す条件は、単位内のすべての構成要素(並行稼働実行、各 slot、速報比較依頼)が終端していることとする。管理 DB を使う設定では、並行稼働実行が COMPLETED / ABORTED、すべての slot 実行が SUCCEEDED / FAILED / ABORTED、すべての速報比較依頼が SUCCEEDED / FAILED / ABORTED であること。RAPID_CROSSCHECK_MODE=off で管理 DB の行が無い実行は成果物だけで判定し、execution-spec.json で起動対象になっている slot(mode が off の slot は含まない)のすべてで、成果物ディレクトリに exitcode.txt または aborted.txt があること。起動対象の slot の成果物ディレクトリが無い場合や execution-spec.json が無い実行は、終わっていないものとして残し、標準エラーに warn を出す。速報比較依頼だけのリランで作られた run は成果物を持たないため、管理 DB の行だけで判定する。1 つでも終わっていない構成要素(RUNNING、CLAIMED、REQUESTED、slot の終了ファイルが無い)があれば、経過日数にかかわらず単位ごと残す。管理 DB に接続しないときの扱いは SPEC-014-08 に従う

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-03-1
  Scenario: SPEC-014-03-1
    Given 並行稼働実行は COMPLETED(foreground の中継は終わった)だが background slot が RUNNING のまま、ほかの構成要素の終了日時から保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物と管理 DB の行は残る

  @atdd_SPEC-014-03-2
  Scenario: SPEC-014-03-2
    Given 並行稼働実行は COMPLETED だが速報比較依頼が REQUESTED・CLAIMED・RUNNING のいずれかのまま、ほかの構成要素の終了日時から保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物と管理 DB の行は残る

  @atdd_SPEC-014-03-3
  Scenario: SPEC-014-03-3
    Given RAPID_CROSSCHECK_MODE=off で管理 DB の行が無く、execution-spec.json に記録された速報クロスチェックのモードが off で、execution-spec.json で起動対象のすべての slot の成果物ディレクトリに exitcode.txt または aborted.txt があり、その更新時刻の最も遅いものから保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物ディレクトリと通知済みの印が無くなる

  @atdd_SPEC-014-03-4
  Scenario: SPEC-014-03-4
    Given RAPID_CROSSCHECK_MODE=off で管理 DB の行が無く、起動対象のすべての slot が終了しているが、その最も遅い更新時刻から保持日数以内の実行
    When ハウスキープを実行する
    Then その実行の成果物ディレクトリは残る

  @atdd_SPEC-014-03-5
  Scenario: SPEC-014-03-5
    Given RAPID_CROSSCHECK_MODE=off で管理 DB の行が無く、起動対象の slot のいずれかの成果物ディレクトリに exitcode.txt も aborted.txt も無い実行
    When ハウスキープを実行する
    Then 経過日数にかかわらずその実行の成果物ディレクトリは残る

  @atdd_SPEC-014-03-6
  Scenario: SPEC-014-03-6
    Given 管理 DB の行が無く、execution-spec.json に記録された速報クロスチェックのモードが off で、execution-spec.json で mode が off の slot があり、その slot の成果物ディレクトリが無く、起動対象のほかの slot はすべて終了して保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物ディレクトリは無くなる

  @atdd_SPEC-014-03-7
  Scenario: SPEC-014-03-7
    Given 管理 DB の行が無く、execution-spec.json が無いか、起動対象の slot の成果物ディレクトリが無い成果物ディレクトリ
    When ハウスキープを実行する
    Then その成果物ディレクトリは残り、標準エラーに warn の行が出る

  @atdd_SPEC-014-03-8
  Scenario: SPEC-014-03-8
    Given 速報比較依頼だけのリランで作られた run を含むリランの親子で、すべての管理 DB の行が終端し、最も遅い終了日時から保持日数を過ぎた
    When ハウスキープを実行する
    Then その run を含む親子すべての管理 DB の行と成果物が無くなる

  @atdd_SPEC-014-03-9
  Scenario: SPEC-014-03-9
    Given 速報比較依頼だけのリランで作られた run の速報比較依頼が RUNNING である
    When ハウスキープを実行する
    Then その run とリランの親子の管理 DB の行と成果物は、経過日数にかかわらず残る
