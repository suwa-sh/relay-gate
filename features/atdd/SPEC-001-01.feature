# source: docs/usdm/latest/requirements.yaml#requirements[REQ-001].specifications[SPEC-001-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-001-01 facade は feature flag 設定(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE、BLUE_IMPL / GREEN_IMPL、BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)を読み込み、slot(blue / green)ごとの実行モード(foreground / background / off)を選択する

  REQ-001: ジョブスケジューラの同一ジョブ定義から、feature flag の設定だけで現行実装(blue)と新実装(green)の並行稼働・単独本番を切り替えられること

  @atdd_SPEC-001-01-1
  Scenario: SPEC-001-01-1
    Given feature flag 設定に BLUE_MODE=foreground, GREEN_MODE=background が定義されている
    When ジョブスケジューラが facade を起動する
    Then blue が foreground、green が background として起動される

  @atdd_SPEC-001-01-2
  Scenario: SPEC-001-01-2
    Given slot の実行モードが off である
    When facade を起動する
    Then その slot の runner は起動されない

  @atdd_SPEC-001-01-3
  Scenario: SPEC-001-01-3
    Given 確報クロスチェックの制御設定は feature flag に含まれない
    When facade を起動する
    Then facade は確報クロスチェックを起動しない

  @atdd_SPEC-001-01-4
  Scenario: SPEC-001-01-4
    Given 元資料の 9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)で feature flag 設定を書く
    When 設定を検証する
    Then 未知キーの警告は出ない

  @atdd_SPEC-001-01-5
  Scenario: SPEC-001-01-5
    Given BLUE_IMPL / GREEN_IMPL が設定されている
    When run を開始する
    Then execution-spec.json の実装版は BLUE_IMPL / GREEN_IMPL の値を出所とし、ジョブマップに実装版の列を要求しない

  @atdd_SPEC-001-01-6
  Scenario: SPEC-001-01-6
    Given RAPID_CROSSCHECK_RUNNER と RAPID_CROSSCHECK_WORKER が設定されている
    When slot が完了する
    Then slot runner は RAPID_CROSSCHECK_RUNNER へ完了通知(blue-completed / green-completed)を送り、速報クロスチェック worker の実体は RAPID_CROSSCHECK_WORKER で解決される
