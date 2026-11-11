# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-04 slot ジョブマップは CSV ファイル(1 行目ヘッダー、1 行 1 job_id)とする。列は元資料の列名 job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes を用い、host と user はローカル実行の slot では省略できる。fixed_params は JSON 配列文字列を格納する CSV セルで、セルは二重引用符で囲み、セル内の二重引用符は二重化する。認証情報の参照名(credential_ref)とマップ版(map_version)は末尾の任意列として許容し必須にしない。実装版の列は持たず、実装版は feature flag(BLUE_IMPL / GREEN_IMPL)が所有する。クロスチェックの設定はジョブ ID ごとの行構造を持つ CSV(クロスチェックジョブマップ)や対象カタログにせず、速報・確報の比較ツール起動コマンドを 1 行の文字列として、それぞれの worker が読む設定ファイルに 1 つずつ定義する(ファイル名・キー名は仕様で確定する。推奨は既存の速報クロスチェック設定と確報クロスチェック worker の設定にキーを 1 つずつ追加する案)。設定検証(validate-config.sh)が起動コマンドに対して行う検証は次の 3 点だけとする: (1) コマンド部分(先頭の語)が絶対パスで、存在し、実行可能であること、(2) 速報の起動コマンドに {job_id} が含まれること、(3) 速報の起動コマンドで {params} を使うなら、引数 1 つ全体がちょうど {params} であること。{job_id} の有無と {params} の位置のほかは、引数部分の内容を検査しない。違反時の文言は CLI 契約(仕様)で確定する

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
    Given 速報の起動コマンドのコマンド部分(先頭の語)が絶対パスで、存在し、実行可能で、文字列に {job_id} を含む
    When validate-config.sh で速報の起動コマンドの設定を検証する
    Then 終了コード 0 で終了し、stderr に error 行が出ない

  @atdd_SPEC-004-04-6
  Scenario: SPEC-004-04-6
    Given 起動コマンドのコマンド部分が絶対パスでない
    When validate-config.sh で検証する
    Then 非 0 の終了コードで終了し、stderr に絶対パスでない旨の error 行がキー名とパスつきで 1 行出る

  @atdd_SPEC-004-04-7
  Scenario: SPEC-004-04-7
    Given 起動コマンドのコマンド部分のファイルが存在しない、または実行可能でない
    When validate-config.sh で検証する
    Then 非 0 の終了コードで終了し、stderr に実行可能でない旨の error 行がキー名とパスつきで 1 行出る

  @atdd_SPEC-004-04-8
  Scenario: SPEC-004-04-8
    Given 速報の起動コマンドに {job_id} が含まれない
    When validate-config.sh で検証する
    Then 非 0 の終了コードで終了し、stderr に {job_id} が無い旨の error 行がキー名と値つきで 1 行出る

  @atdd_SPEC-004-04-9
  Scenario: SPEC-004-04-9
    Given 確報の起動コマンドにプレースホルダが 1 つも無い
    When validate-config.sh で確報の起動コマンドの設定を検証する
    Then 終了コード 0 で終了する(確報の起動コマンドにプレースホルダは要求しない)

  @atdd_SPEC-004-04-10
  Scenario: SPEC-004-04-10
    Given 起動コマンドの引数部分が、{params} を引数の一部に含まない任意の文字列(存在しないパスや未知の語を含む)で、速報の起動コマンドの場合は {job_id} を含む
    When validate-config.sh で検証する
    Then 引数部分を理由とする error 行は出ず、終了コードは引数部分の内容に影響されない

  @atdd_SPEC-004-04-11
  Scenario: SPEC-004-04-11
    Given relay-gate の設定ファイル置き場
    When クロスチェックジョブマップ CSV や対象カタログ CSV を探す
    Then 存在せず、validate-config.sh にそれらを検証する種別も無い

  @atdd_SPEC-004-04-12
  Scenario: SPEC-004-04-12
    Given 速報の起動コマンドの引数の一部に {params} を含む(--args={params})
    When validate-config.sh で速報の起動コマンドの設定を検証する
    Then 非 0 の終了コードで終了し、stderr に {params} が引数全体でない旨の error 行がキー名と値つきで 1 行出る
