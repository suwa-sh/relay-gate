# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-04 slot ジョブマップ・クロスチェックジョブマップ・対象カタログは CSV ファイル(1 行目ヘッダー、1 行 1 job_id)とする。slot ジョブマップの列は元資料の列名 job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes を用い、host と user はローカル実行の slot では省略できる。fixed_params は JSON 配列文字列を格納する CSV セルで、セルは二重引用符で囲み、セル内の二重引用符は二重化する。認証情報の参照名(credential_ref)とマップ版(map_version)は末尾の任意列として許容し必須にしない。実装版の列は持たず、実装版は feature flag(BLUE_IMPL / GREEN_IMPL)が所有する

  REQ-004: ジョブスケジューラのジョブ定義に実行先(ホスト・実行ユーザー・スクリプトパス)を持たせず、slot runner が実装固有のジョブマップで JOB_ID から実行先を解決し、解決結果を execution-spec.json として保存すること

  @atdd_SPEC-004-04-1
  Scenario: SPEC-004-04-1
    Given 元資料どおりの列名(job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes)の CSV ジョブマップ
    When runner が JOB_ID を解決する
    Then 列名の読み替えなしに host・user・script・work_dir・fixed_params・hang_detect_limit_minutes が得られる

  @atdd_SPEC-004-04-2
  Scenario: SPEC-004-04-2
    Given fixed_params セルに p1 と p2 p3 の 2 要素の JSON 配列を、二重引用符で囲み内部の二重引用符を二重化して書いた
    When runner が固定引数を解析する
    Then 空白とカンマを維持した 2 引数として得られる

  @atdd_SPEC-004-04-3
  Scenario: SPEC-004-04-3
    Given host と user の列を持たないローカル実行用の slot ジョブマップ
    When runner が JOB_ID を解決する
    Then ローカル実行として解決される

  @atdd_SPEC-004-04-4
  Scenario: SPEC-004-04-4
    Given credential_ref と map_version の列を持たないジョブマップ
    When 設定を検証する
    Then エラーにならず、両列がある場合は末尾の任意列として読み込まれる

  @atdd_SPEC-004-04-5
  Scenario: SPEC-004-04-5
    Given クロスチェックジョブマップと対象カタログ
    When ファイル形式を確認する
    Then slot ジョブマップと同じ CSV 形式である
