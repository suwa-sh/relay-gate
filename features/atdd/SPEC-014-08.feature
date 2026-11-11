# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-08].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-08 管理 DB に接続しないとき(RAPID_CROSSCHECK_MODE=off で、確報クロスチェックを使わない設置(確報クロスチェック worker の設定が無い設置)で、ハウスキープ設定の管理 DB 接続参照名が無い・空)は、ハウスキープは管理 DB に接続せず、確報比較依頼と管理 DB の行を削除しない。起動のたびに、管理 DB の行を削除しないことを示す warn を標準エラーへ 1 行出す。成果物ルートの実行は成果物だけで判定するが、execution-spec.json に記録された速報クロスチェックのモードが off でない実行(off 以外の期間に作られ、管理 DB に終わっていない構成要素があり得る実行)は、判定できないものとして経過日数にかかわらず単位ごと残し、その実行を残したことを示す warn を標準エラーへ出す。off の期間に作られた成果物だけの実行は、SPEC-014-03 と SPEC-014-04 の成果物だけの規則どおりに判定して削除・保持する。これらの warn は終了コードに影響しない。管理 DB に接続しないときは、本 SPEC の規則が SPEC-014-01〜07 より優先する。RAPID_CROSSCHECK_MODE が off 以外の設置や、確報クロスチェックを使う設置で接続参照名が無い・空のときは、本 SPEC の振る舞いにならず SPEC-014-07 の設定エラーになる。warn の文言と設定のキー名は仕様(CLI 契約)で確定する

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-08-1
  Scenario: SPEC-014-08-1
    Given 管理 DB に接続しない設定(RAPID_CROSSCHECK_MODE=off で、確報クロスチェック worker の設定が無い設置で、ハウスキープ設定の管理 DB 接続参照名が無い・空)で、終端状態で completed_at から保持日数を過ぎた確報比較依頼がある
    When ハウスキープを実行する
    Then その確報比較依頼と管理 DB の行は残り、標準エラーに管理 DB の行を削除しない旨の warn の行が 1 行出る

  @atdd_SPEC-014-08-2
  Scenario: SPEC-014-08-2
    Given 管理 DB に接続しない設定(RAPID_CROSSCHECK_MODE=off で、確報クロスチェック worker の設定が無い設置で、ハウスキープ設定の管理 DB 接続参照名が無い・空)で、execution-spec.json に記録された速報クロスチェックのモードが off でなく、起動対象のすべての slot の成果物ディレクトリに exitcode.txt または aborted.txt があり、その最も遅い更新時刻から保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の単位の成果物ディレクトリは残り、標準エラーにその実行を残した旨の warn の行が出る

  @atdd_SPEC-014-08-3
  Scenario: SPEC-014-08-3
    Given 管理 DB に接続しない設定(RAPID_CROSSCHECK_MODE=off で、確報クロスチェック worker の設定が無い設置で、ハウスキープ設定の管理 DB 接続参照名が無い・空)で、execution-spec.json に記録された速報クロスチェックのモードが off で、起動対象のすべての slot の成果物ディレクトリに exitcode.txt または aborted.txt があり、その最も遅い更新時刻から保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物ディレクトリと通知済みの印が無くなる

  @atdd_SPEC-014-08-4
  Scenario: SPEC-014-08-4
    Given 管理 DB に接続しない設定(RAPID_CROSSCHECK_MODE=off で、確報クロスチェック worker の設定が無い設置で、ハウスキープ設定の管理 DB 接続参照名が無い・空)で、削除の失敗が無い
    When ハウスキープを実行する
    Then 標準エラーに warn の行が出ても終了コード 0 で終わる
