# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-01 実装スロットと runner は feature flag が、ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes は該当 slot のジョブマップが、速報・確報の比較ツール起動コマンド(各 1 行)はそれぞれの worker が読む設定が所有する。比較対象(テーブル・ファイル)の定義は relay-gate の設定に持たず、適用側が比較ツール側で定義する。slot ジョブマップの場所は feature flag が所有する。feature flag に、slot ジョブマップの場所を書く任意のキーを blue 用と green 用に 1 つずつ持つ(キー名は仕様で確定する。推奨は BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)。キーが無い、または値が空のときは、これまでの固定の名前(設定ファイル置き場の blue-job-map.csv / green-job-map.csv)を使い、既存の設定はそのまま動く。値は絶対パスと相対パスのどちらも受け付け、相対パスの基準は、その feature flag の設定ファイル(feature-flag.env)があるディレクトリとする。相対パスの解決の規則は、feature flag の runner / worker の 4 キー(BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)と同じにする(規則の詳細は仕様の CLI 契約を正とする)。解決した後の場所は、ジョブマップを読むすべての処理(feature flag の検証コマンドによるジョブマップの所在の検査と表示、slot runner のジョブマップ解決、ジョブマップを読む運用系のコマンド)で同じものを使う。slot runner は feature flag の設定ファイルを読まない契約のままとし、解決した後の場所を runner へ渡す方法は仕様で確定する。ジョブマップ単体の検証コマンド(パスを渡して検証する)は、渡されたパスを検証する動きのまま変えない。元の方針資料のしくみの資料の設定例(9 キー)にはジョブマップの場所の行が無く、利用イメージの資料の設定例は feature flag にジョブマップの場所を相対パスで書いている。本仕様は、利用イメージの資料の設定例に寄せた利用者決定(2026-11-16)である

  REQ-004: ジョブスケジューラのジョブ定義に実行先(ホスト・実行ユーザー・スクリプトパス)を持たせず、slot runner が実装固有のジョブマップで JOB_ID から実行先を解決し、解決結果を execution-spec.json として保存すること

  @atdd_SPEC-004-01-1
  Scenario: SPEC-004-01-1
    Given slot のジョブマップに JOB_ID の行がある
    When runner が JOB_ID を解決する
    Then ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes が得られる

  @atdd_SPEC-004-01-2
  Scenario: SPEC-004-01-2
    Given relay-gate の設定ファイル一式
    When 比較対象(テーブル・ファイル)の一覧やジョブ ID ごとの比較定義を探す
    Then 存在せず、クロスチェックに関する設定は速報・確報の比較ツール起動コマンド各 1 行だけである

  @atdd_SPEC-004-01-3
  Scenario: SPEC-004-01-3
    Given feature flag に blue 用のジョブマップの場所のキーを絶対パスで書き、そのパスと設定ファイル置き場の blue-job-map.csv の両方にジョブマップがある
    When blue の runner が JOB_ID を解決する
    Then キーに書いたパスのジョブマップの行で実行先が解決される

  @atdd_SPEC-004-01-4
  Scenario: SPEC-004-01-4
    Given feature flag にジョブマップの場所のキーが blue 用も green 用も無い
    When blue と green の runner が JOB_ID を解決する
    Then 設定ファイル置き場の blue-job-map.csv と green-job-map.csv の行で実行先が解決される

  @atdd_SPEC-004-01-5
  Scenario: SPEC-004-01-5
    Given feature flag のジョブマップの場所のキーの値が空である
    When その slot の runner が JOB_ID を解決する
    Then キーが無いときと同じく、設定ファイル置き場の固定の名前のジョブマップの行で実行先が解決される

  @atdd_SPEC-004-01-6
  Scenario: SPEC-004-01-6
    Given feature flag に green 用のジョブマップの場所のキーだけを書き、blue 用のキーが無い
    When blue と green の runner が JOB_ID を解決する
    Then green はキーに書いたパスのジョブマップ、blue は設定ファイル置き場の blue-job-map.csv で実行先が解決される

  @atdd_SPEC-004-01-7
  Scenario: SPEC-004-01-7
    Given feature flag のジョブマップの場所のキーに相対パスを書き、feature-flag.env があるディレクトリとは別のディレクトリをカレントディレクトリにしている
    When facade を起動する
    Then feature-flag.env があるディレクトリを基準に解決したパスのジョブマップで実行先が解決される

  @atdd_SPEC-004-01-8
  Scenario: SPEC-004-01-8
    Given feature flag にジョブマップの場所のキーを書いた
    When feature flag の検証コマンドを実行し、同じ設定で facade を起動する
    Then 検証コマンドが所在を検査して表示するジョブマップと、slot runner が実行先の解決に使うジョブマップは、同じファイルである

  @atdd_SPEC-004-01-9
  Scenario: SPEC-004-01-9
    Given feature flag のジョブマップの場所のキーに書いた場所にジョブマップが無い
    When feature flag の検証コマンドを実行する
    Then 非 0 の終了コードで終わり、標準エラーに、ジョブマップが見つからない旨の行が解決した後のパスつきで出る

  @atdd_SPEC-004-01-10
  Scenario: SPEC-004-01-10
    Given feature flag にジョブマップの場所のキーを書いている
    When ジョブマップ単体の検証コマンドに別のパスを渡して実行する
    Then 渡したパスのジョブマップが検証される
