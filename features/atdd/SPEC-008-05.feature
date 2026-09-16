# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-05].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-05 hang_detect_limit_minutes は導入時に全ジョブ 60 分に設定し、正常終了パターンの警告が出そろった時点でジョブごとに最後の警告の経過時間を基準に調整する。foreground role は 0 を設定して検知対象から除外できる

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-05-1
  Scenario: SPEC-008-05-1
    Given ジョブマップの hang_detect_limit_minutes を変更した
    When 次回以降の run を実行する
    Then 新しい上限が execution-spec.json に反映され判定に使われる

  @atdd_SPEC-008-05-2
  Scenario: SPEC-008-05-2
    Given hang_detect_limit_minutes を調整した
    When 調整の記録を確認する
    Then 調整日時と調整根拠(警告時経過時間)は適用構成文書に残り、ジョブマップの列には持たない
