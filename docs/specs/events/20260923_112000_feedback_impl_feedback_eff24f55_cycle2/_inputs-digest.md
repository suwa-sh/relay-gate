design_available: false
event_id: 20260923_112000_feedback_impl_feedback_eff24f55_cycle2

# arch ダイジェスト

- 転写元: `docs/arch/latest/arch-design.yaml`
- source_sha256: `45a30ece498ff31b18cdec055333a172156d453b8d6d4b4f330b716cfc87de04`
- 生成: `extractSections.js`（原文転写。要約・言い換えなし）

## 転写済みセクションのチェックリスト

| セクション | 状態 |
|---|---|
| `technology_context` | 転写済み |
| `domain_architecture` | 転写済み |
| `system_architecture.tiers` | 転写済み |
| `app_architecture.tier_layers` | 転写済み |
| `data_architecture.entities` | 転写済み |

`not_applicable` = 元ファイルにセクション自体が存在しない（フォールバック対象外。元ファイルを読みに行かない）。

## technology_context

```yaml
technology_context:
  languages:
    - "bash(シェルスクリプト。facade / runner / worker / 監視 / 復旧の全スクリプト)"
    - "SQL(管理 DB のジョブキュー操作。RDB クライアント CLI 経由)"
    - "JavaScript(CommonJS。BDD の step 定義のみ。実行時には使用しない)"
  frameworks:
    - "なし(フレームワーク非採用。bash 標準コマンド + ssh + RDB クライアント CLI + OS のメール送信コマンドで構成)"
  constraints:
    - "エアーギャップ環境のオンプレミス Linux。実行時にインターネット接続・外部 SaaS を要求しない"
    - "UI 画面を持たない。CLI(標準出力・標準エラー・終了コード)と定期ジョブとメール通知だけで動作する。presentation 系 tier(frontend / web / ui)は作らない"
    - "HTTP API は無い。IdP / API Gateway / 認可サービスは導入しない(SSH 鍵と OS 権限のみ)"
    - "方針資料の C2/C3/C4 構成(facade / slot runner / rapid-crosscheck runner・worker / final-crosscheck runner・worker / hang-detector / background-rerun / abort-*)と Runner Result Contract(stdout.log / stderr.log / exitcode.txt + execution-spec.json)を spec 都合で変更しない"
    - "設定契約(feature flag / slot ジョブマップ / クロスチェックジョブマップ / 適用文書)の設定所有区分を維持する"
    - "管理 DB は RDB 1 種(ジョブキュー兼管理 DB)。速報側と確報側のデータモデルを分離する"
    - "成果物に特定案件の固有名(製品名・サーバ名・業務名)を記載しない(中立表現)"
    - "実行履歴・監査の正本はジョブスケジューラ。relay-gate はファイル(成果物・実行ログ)と管理レコードを残すだけ"
```

## domain_architecture

```yaml
domain_architecture:
  subdomains:
    - id: "SD-001"
      name: "実装切替(ストラングラーファサード)"
      type: "core"
      investment_policy: "最優先で深いモデリングと継続的リファクタリングに投資。チーム最強の人材を配置"
      related_buc_ids:
        - "実装切替ジョブ実行フロー"
      reason: "システム概要が「feature flag 付きストラングラーファサード型の実行基盤」を目的そのものとしており、同一ジョブ定義から blue / green を並行稼働させ foreground 結果だけを中継する仕組みが差別化の核であるため"
      source_model: "システム概要, BUC: 実装切替ジョブ実行フロー, 条件: facade の責務限定, 実装固有事項の runner への閉じ込め"
      confidence: "medium"
    - id: "SD-002"
      name: "クロスチェック(整合性検証)"
      type: "core"
      investment_policy: "最優先で深いモデリングと継続的リファクタリングに投資。チーム最強の人材を配置"
      related_buc_ids:
        - "速報クロスチェックフロー"
        - "確報クロスチェックフロー"
      reason: "並行稼働の目的は整合性を検証しながら段階的に切り替えることであり、速報(原因調査)と確報(リリース判断の正本)の二段構えの比較規約が基盤の価値を決めるため。比較ツール自体は外部システムに委譲する"
      source_model: "システム概要, BUC: 速報クロスチェックフロー, 確報クロスチェックフロー, 外部システム: 比較ツール"
      confidence: "medium"
    - id: "SD-003"
      name: "background 実行の監視と復旧"
      type: "supporting"
      investment_policy: "good enough な品質で安定運用。標準的なフレームワーク採用"
      related_buc_ids:
        - "background 実行監視フロー"
        - "実行中止フロー"
        - "background 側リランフロー"
      reason: "ジョブスケジューラのジョブステータスに現れない background 異常を補完する運用機能であり、監視は通知のみ・復旧は運用者判断という限定責務のため supporting とする"
      source_model: "BUC: background 実行監視フロー, 実行中止フロー, background 側リランフロー, 条件: 監視は通知のみ"
      confidence: "medium"
    - id: "SD-004"
      name: "適用構成の定義"
      type: "supporting"
      investment_policy: "good enough な品質で安定運用。標準的なフレームワーク採用"
      related_buc_ids:
        - "適用構成定義フロー"
      reason: "feature flag・ジョブマップ・比較定義・適用文書の設定契約を保守する業務で、案件ごとの差し替えを支える。設定所有区分の分離が主要関心であり、差別化要因ではない"
      source_model: "BUC: 適用構成定義フロー, アクター: 基盤適用設計者, 条件: 設定所有区分, 適用側で定義する事項"
      confidence: "medium"
  bounded_contexts:
    - id: "BC-001"
      name: "並行稼働実行コンテキスト"
      ubiquitous_language:
        - term: "run"
          definition: "1 回の並行稼働。run_id({ローカルタイムゾーンの yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}。facade がモードによらず発行する)で成果物・rapid_run・比較依頼を相関付ける。parent_run_id でリラン系譜を追跡する"
        - term: "slot"
          definition: "実装系統(blue / green)の枠。feature flag で実行モード(foreground / background / off)を選ぶ。foreground は同時に 1 slot だけ"
        - term: "Runner Result"
          definition: "slot runner が成果物ディレクトリに残す stdout.log / stderr.log / exitcode.txt(+ started-at.txt。明示中止時のみ aborted.txt)。外部 IF の正本であり、slot 実行の状態は exitcode.txt / aborted.txt の有無と値から導出する"
        - term: "execution-spec"
          definition: "run 開始時にジョブマップから解決して一度だけ確定保存する実行設定。以後のジョブマップ変更に影響されない"
      related_subdomain_id: "SD-001"
      owned_entity_ids:
        - "E-009"
        - "E-010"
        - "E-011"
        - "E-012"
        - "E-013"
        - "E-014"
        - "E-025"
      owned_buc_ids:
        - "実装切替ジョブ実行フロー"
      team_ownership: null
      reason: "状態モデル「並行稼働実行」「slot 実行」が独立して閉じ、facade と slot runner が扱う語彙(run / slot / mode / Runner Result)が他コンテキストと異なるため"
      source_model: "BUC: 実装切替ジョブ実行フロー, 情報: 並行稼働実行(parallel_run), slot 実行, Runner Result, 状態: 並行稼働実行, slot 実行"
      confidence: "medium"
    - id: "BC-002"
      name: "速報クロスチェックコンテキスト"
      ubiquitous_language:
        - term: "完了通知"
          definition: "blue / green runner が自系統の公開 function(blue-completed / green-completed)で送る一方向の完了結果。相手側の状態も自 slot の中止状態(aborted.txt の有無)も判断せず、中止後に実装が走り切った場合も通常どおり送る"
        - term: "両系成功"
          definition: "blue と green の両方が exitcode 0 で完了した状態。このときに限り速報比較依頼を 1 件だけ作成する。ただし中止済み run(並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(成果物ディレクトリに aborted.txt が公開済み)のいずれか)では両系成功でも依頼を作成せず、完了事実だけを記録して実行ログに警告を残す。判定材料は管理 DB の parallel_run.status と slot_executions.status(aborted.txt のミラー)で、この判断は dispatcher(速報クロスチェック runner)が行う"
        - term: "比較依頼"
          definition: "管理 DB 上のジョブキューのレコード。速報では run_id を主キーとし、worker が claim / lease で多重実行を防ぐ"
      related_subdomain_id: "SD-002"
      owned_entity_ids:
        - "E-015"
        - "E-016"
        - "E-017"
        - "E-018"
      owned_buc_ids:
        - "速報クロスチェックフロー"
      team_ownership: null
      reason: "方針資料が「速報と確報の比較規約はそれぞれ別ドメインが所有する」と明示し、rapid_run / rapid_crosscheck_request / comparison_result のモデルが確報側と分離されているため"
      source_model: "BUC: 速報クロスチェックフロー, 情報: 速報実行(rapid_run), 速報比較依頼(rapid_crosscheck_request), 比較結果(comparison_result), 完了通知, slot 実行, 状態: 速報実行の完了状況, クロスチェック依頼, slot 実行, 条件: 中止済み run の比較依頼作成除外, 依頼中止可否判定"
      confidence: "medium"
    - id: "BC-003"
      name: "確報クロスチェックコンテキスト"
      ubiquitous_language:
        - term: "確報比較依頼"
          definition: "business_date と対象カタログの版で登録する日次全量比較の依頼。runner が終端状態まで同期 polling し、保存済み stdout / stderr / exitcode だけを中継する"
        - term: "対象カタログ"
          definition: "全テーブル・全ファイルを target_type / target_identifier と版で定義する比較対象の一覧。リリース判断の正本となる比較範囲"
      related_subdomain_id: "SD-002"
      owned_entity_ids:
        - "E-019"
        - "E-020"
      owned_buc_ids:
        - "確報クロスチェックフロー"
      team_ownership: null
      reason: "条件「速報と確報のモデル分離」により final_crosscheck_request と対象カタログを用い、速報側の rapid_run / rapid_crosscheck_request を作成・変更しないと定義されているため独立 BC とする"
      source_model: "BUC: 確報クロスチェックフロー, 情報: 確報比較依頼(final_crosscheck_request), 対象カタログ, 比較ツール実行結果, 条件: 速報と確報のモデル分離"
      confidence: "medium"
    - id: "BC-004"
      name: "実行監視・復旧コンテキスト"
      ubiquitous_language:
        - term: "ハング疑い"
          definition: "exitcode.txt が未出力のまま started-at.txt からの経過時間が hang_detect_limit_minutes を超えた background role。warning で通知するが状態は変更しない"
        - term: "明示中止"
          definition: "運用者がプロセス停止を自身で確認し、中止スクリプトに yes と答えて ABORTED へ更新すること。中止できる状態は background slot 実行と確報比較依頼が RUNNING のみ、速報比較依頼は REQUESTED / CLAIMED / RUNNING のいずれか(abort-rapid-crosscheck。CLAIMED を放置すると lease 失効で再 claim されるため運用者が止める手段として必要)。slot の中止は成果物ディレクトリへの aborted.txt 書き込みを正本とし、RAPID_CROSSCHECK_MODE が off 以外なら管理 DB の状態も更新する。abort-blue / abort-green は run の中止として、対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があればそれも ABORTED にする。これは両系の完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険であり、dispatcher 側の中止済み run 判定と併用する(CLAIMED / RUNNING の依頼は abort-rapid-crosscheck の対象)。スクリプトはプロセスを停止しない"
        - term: "background 側リラン"
          definition: "完了済みまたは明示中止済みの background slot / 速報比較依頼を、元の execution-spec.json から新しい run_id で再実行すること"
      related_subdomain_id: "SD-003"
      owned_entity_ids:
        - "E-021"
        - "E-022"
        - "E-023"
        - "E-024"
      owned_buc_ids:
        - "background 実行監視フロー"
        - "実行中止フロー"
        - "background 側リランフロー"
      team_ownership: null
      reason: "状態モデル「監視状態」が独立し、hang-detector / background-rerun / abort-* が通常起動の facade から分離された運用スクリプト群として方針資料に定義されているため"
      source_model: "BUC: background 実行監視フロー, 実行中止フロー, background 側リランフロー, 情報: 監視記録, 通知メール, リラン指示, 中止指示, 状態: 監視状態, クロスチェック依頼, 条件: slot 中止可否判定, 依頼中止可否判定, バリエーション: 中止対象種別, 停止確認応答"
      confidence: "medium"
    - id: "BC-005"
      name: "適用構成コンテキスト"
      ubiquitous_language:
        - term: "feature flag"
          definition: "9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)で slot ごとの実行モード・実装版・runner 実体・速報クロスチェックモード(foreground / background / off)と完了通知先・worker 実体を切り替える正本。設定版は持たない。運用モード(並行稼働 / 単独本番 / 次世代並行稼働)を組み合わせで表現する"
        - term: "ジョブマップ"
          definition: "JOB_ID から実行先(host・user・work_dir・script・fixed_params・hang_detect_limit_minutes)を slot ごとに解決する正本。1 行目ヘッダーの CSV(1 行 1 job_id)で、credential_ref / map_version は末尾の任意列"
        - term: "速報クロスチェック設定"
          definition: "速報クロスチェック用の env 設定ファイル(rapid-crosscheck.env)。管理 DB 接続参照名(RAPID_DB_CONN_REF。値は置かず参照名のみ)・lease 期間(RAPID_LEASE_SEC)・worker の poll 間隔(RAPID_POLL_INTERVAL_SEC)を保持し、facade・slot runner・速報クロスチェック runner・worker が読む。RAPID_CROSSCHECK_MODE=off では不要。ハング検知定期ジョブ設定と同型だが所有項目と読み手が異なるため別ファイル"
        - term: "設定所有区分"
          definition: "各設定項目の正本をどこ(feature flag / slot ジョブマップ / クロスチェックジョブマップ / ハング検知定期ジョブ設定 / 速報クロスチェック設定 / 適用文書)が所有するかの区分"
      related_subdomain_id: "SD-004"
      owned_entity_ids:
        - "E-001"
        - "E-002"
        - "E-003"
        - "E-004"
        - "E-005"
        - "E-006"
        - "E-007"
        - "E-008"
        - "E-026"
        - "E-027"
      owned_buc_ids:
        - "適用構成定義フロー"
      team_ownership: null
      reason: "基盤適用設計者だけが扱う設定契約の語彙(feature flag / ジョブマップ / 比較定義 / ハング検知定期ジョブ設定 / 速報クロスチェック設定 / 適用文書)で閉じており、実行系コンテキストは読み取り専用で従うため"
      source_model: "BUC: 適用構成定義フロー, アクター: 基盤適用設計者, 情報: feature flag 設定, ジョブマップ, クロスチェックジョブマップ, ハング検知定期ジョブ設定, 速報クロスチェック設定, 適用構成文書, 条件: 設定所有区分, バリエーション: 設定所有区分"
      confidence: "medium"
  context_map:
    - id: "CM-001"
      from_bc_id: "BC-001"
      to_bc_id: "BC-005"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-001(並行稼働実行)は BC-005 の設定契約(feature flag / slot ジョブマップ)をそのまま読み込み従う。翻訳層は持たず、run 開始時に execution-spec.json へ確定保存することで以後の変更から隔離する"
      integration_events: []
      reason: "facade は設定された runner を起動するだけ、runner はジョブマップで実行先を解決するだけであり、設定契約に変更を加える余地がないため"
      source_model: "条件: 実装固有事項の runner への閉じ込め, ジョブマップ解決条件, 実行設定の確定条件"
      confidence: "medium"
    - id: "CM-002"
      from_bc_id: "BC-001"
      to_bc_id: "BC-002"
      pattern: "ohs"
      direction: "upstream"
      translator_description: "BC-001 が Runner Result Contract と完了通知の公開 function(blue-completed / green-completed)を公開言語として提供し、BC-002 が受け取る。runner は相手側の状態や比較依頼の要否を判断しない"
      integration_events:
        - "blue-completed"
        - "green-completed"
      reason: "完了通知が系統ごとに分かれた一方向の公開 function として方針資料に定義され、比較規約は rapid-crosscheck runner / worker に閉じ込められているため"
      source_model: "情報: 完了通知, Runner Result, 条件: 完了通知の系統独立, 速報クロスチェック有効判定"
      confidence: "medium"
    - id: "CM-003"
      from_bc_id: "BC-002"
      to_bc_id: "BC-003"
      pattern: "shared_kernel"
      direction: "symmetric"
      translator_description: "クロスチェック依頼のライフサイクル(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)、claim / lease 規則、比較ツール終了コード契約(0 / 3 / 6)を共有する。データモデル(レコード)は共有しない"
      integration_events: []
      reason: "条件「依頼状態遷移規則」が速報と確報で同一ライフサイクルを用いると定め、一方でレコードは別モデルに分離されているため、規則のみの共有カーネルとする"
      source_model: "状態: クロスチェック依頼, 条件: 依頼状態遷移規則, lease 失効判定, claim 排他, 比較ツール終了コードの対応, 速報と確報のモデル分離"
      confidence: "medium"
    - id: "CM-004"
      from_bc_id: "BC-004"
      to_bc_id: "BC-001"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-004(監視・復旧)は BC-001 の成果物(started-at.txt / exitcode.txt / execution-spec.json)と slot 実行・parallel_run の状態をそのまま読み、監視は通知のみ、中止は状態更新のみ、リランは execution-spec.json からの復元で新 run を作る"
      integration_events: []
      reason: "hang-detector は Runner Result Contract のファイルを走査し、background-rerun は元の execution-spec.json を正本として復元するため、BC-001 の契約に従う下流である"
      source_model: "条件: ハング検知判定, リランの実行設定復元, リラン系譜の追跡, slot 中止可否判定"
      confidence: "medium"
    - id: "CM-005"
      from_bc_id: "BC-004"
      to_bc_id: "BC-002"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-004 は速報比較依頼の状態と終了コードを読み取り異常を通知し、abort-rapid-crosscheck で REQUESTED / CLAIMED / RUNNING の速報比較依頼を(運用者の worker 停止確認のうえ status IN (REQUESTED, CLAIMED, RUNNING) を条件とする条件付き UPDATE で)ABORTED に、abort-blue / abort-green で対象 run の REQUESTED(未着手)の速報比較依頼を競合窓の保険として ABORTED に更新し、background-rerun(--role rapid-crosscheck)で新 run_id の速報比較依頼を作成する。比較の要否判断(中止済み run の除外を含む)は BC-002 の dispatcher が持ち、CLAIMED で中止された依頼の比較を開始しない規則(CLAIMED → RUNNING の条件付き UPDATE が 0 件なら終了)は BC-002 の worker が持つ。BC-004 は状態遷移規則に従って更新するだけ"
      integration_events: []
      reason: "監視・中止・リランは速報側のモデルを変更せず、その状態遷移規則に従って参照・更新するだけのため"
      source_model: "条件: 速報比較依頼の異常判定, 依頼中止可否判定, slot 中止可否判定, 中止済み run の比較依頼作成除外, リラン事前検証, 状態: クロスチェック依頼, バリエーション: 中止対象種別"
      confidence: "medium"
    - id: "CM-006"
      from_bc_id: "BC-004"
      to_bc_id: "BC-003"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-004 は abort-final-crosscheck で RUNNING の確報比較依頼を ABORTED に更新するだけ。確報の再実行はジョブスケジューラの正規ジョブに委ね、background-rerun の対象にしない"
      integration_events: []
      reason: "条件「復旧手段の選択」が確報の再実行経路をジョブスケジューラ正規ジョブと定めており、監視・復旧側は状態更新以外に関与しないため"
      source_model: "条件: 依頼中止可否判定, 復旧手段の選択"
      confidence: "medium"
    - id: "CM-007"
      from_bc_id: "BC-002"
      to_bc_id: "BC-005"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-002 は BC-005 のクロスチェックジョブマップ(job_id ごとの比較定義)を読み、比較ツールの起動コマンド・比較対象・オプションをそのまま用いる"
      integration_events: []
      reason: "比較定義は適用側が job_id ごとに差し替える設定契約であり、速報 worker はそれに従うだけのため"
      source_model: "条件: 比較定義の選択, 設定所有区分"
      confidence: "medium"
    - id: "CM-008"
      from_bc_id: "BC-003"
      to_bc_id: "BC-005"
      pattern: "conformist"
      direction: "downstream"
      translator_description: "BC-003 は BC-005 の対象カタログ(版付き)を読み、確報比較依頼に版を紐付けて全量比較の範囲を確定する"
      integration_events: []
      reason: "比較対象と対象カタログはクロスチェックのジョブマップで適用側が定義すると条件に定められているため"
      source_model: "条件: 適用側で定義する事項, 設定所有区分"
      confidence: "medium"
  aggregate_hypotheses:
    - id: "AG-001"
      bounded_context_id: "BC-001"
      root_entity_id: "E-013"
      member_entity_ids:
        - "E-014"
        - "E-010"
        - "E-011"
        - "E-012"
      invariants:
        - "blue と green の両方が foreground の構成は許可しない(入力検証でエラー終了し、どの slot も起動しない)"
        - "background slot をすべて起動してから foreground slot を起動し、foreground の PID だけを待機する"
        - "execution-spec.json は run 開始時に一度だけ確定保存し、以後上書きしない。認証情報の値は保存しない"
        - "slot 実行終了時に stdout.log / stderr.log / exitcode.txt が揃う。exitcode.txt は数値 1 行で runner の終了コードと一致する"
        - "ジョブスケジューラへの応答は foreground slot の Runner Result のみ。background と速報の結果は反映しない"
      note: "仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。RAPID_CROSSCHECK_MODE=off では parallel_run を作成せず成果物ファイルだけで動作するため、root の永続化有無はモードに依存する"
      source_model: "情報: 並行稼働実行(parallel_run), slot 実行, 実行設定(execution-spec), Runner Result, 状態: 並行稼働実行, slot 実行, 条件: foreground slot 排他, slot 起動順序, 実行設定の確定条件, Runner Result 完備条件"
      confidence: "low"
    - id: "AG-002"
      bounded_context_id: "BC-002"
      root_entity_id: "E-016"
      member_entity_ids:
        - "E-015"
        - "E-017"
        - "E-018"
      invariants:
        - "blue と green の両方が成功(exitcode 0)したときに限り速報比較依頼を作成する"
        - "中止済み run(並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(aborted.txt 公開済み))では両系成功でも速報比較依頼を作成しない。完了事実(blue_status / green_status / 成果物 URI)だけを rapid_run に記録し、実行ログに警告を残す。判定材料は parallel_run.status と slot_executions.status"
        - "1 つの run_id に対する速報比較依頼は完了順にかかわらず 1 件だけ(run_id 主キー)"
        - "claim 中(lease 有効)の依頼は他 worker が取得できない。lease 失効かつ未開始なら REQUESTED に戻す。lease 期間と poll 間隔は速報クロスチェック設定から読む"
        - "REQUESTED で未着手の速報比較依頼は対象 run の abort-blue / abort-green(競合窓の保険)または abort-rapid-crosscheck で ABORTED になる。CLAIMED / RUNNING の依頼は abort-rapid-crosscheck だけが ABORTED にする(確報比較依頼は RUNNING のみ)"
        - "CLAIMED から RUNNING への遷移は status = CLAIMED を条件とする条件付き UPDATE で行い、更新件数が 0 件(ABORTED 済み)なら worker は比較を開始しない"
        - "依頼状態は比較ツールの exitcode に従う(0=SUCCEEDED / 非 0・実行エラー=FAILED)"
      note: "仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。rapid_run と rapid_crosscheck_request を同一集約に置くか(両系成功→依頼作成の原子性)、依頼を別集約にするか(worker の claim 競合)は実装時に再判断する"
      source_model: "情報: 速報実行(rapid_run), 完了通知, 速報比較依頼(rapid_crosscheck_request), 比較結果(comparison_result), 速報クロスチェック設定, slot 実行, 状態: 速報実行の完了状況, クロスチェック依頼, 並行稼働実行, slot 実行, 条件: 両系成功判定, 中止済み run の比較依頼作成除外, 比較依頼の一意性, claim 排他, lease 失効判定, slot 中止可否判定, 依頼中止可否判定"
      confidence: "low"
    - id: "AG-003"
      bounded_context_id: "BC-003"
      root_entity_id: "E-019"
      member_entity_ids:
        - "E-020"
      invariants:
        - "確報比較依頼は business_date と対象カタログの版を持って REQUESTED で登録する"
        - "ジョブスケジューラへ返すのは保存済みの stdout / stderr / exitcode だけ。状態名や差分件数・レポート URI は返さない"
        - "rapid_run / rapid_crosscheck_request を作成・変更しない"
      note: "仮説。最終確定は dist-spec または ddd-tactical-implementation で行う"
      source_model: "情報: 確報比較依頼(final_crosscheck_request), 比較ツール実行結果, 状態: クロスチェック依頼, 条件: 確報依頼の登録条件, 確報結果の中継制約, 速報と確報のモデル分離"
      confidence: "low"
    - id: "AG-004"
      bounded_context_id: "BC-004"
      root_entity_id: "E-021"
      member_entity_ids:
        - "E-022"
      invariants:
        - "監視は monitor_status / hang_suspected_at / alerted_at を記録し通知するだけ。RUNNING を ABORTED にせず、プロセスを停止せず、新しい実行依頼を作成しない"
        - "hang_detect_limit_minutes が 0 の role と foreground role は検知対象外"
        - "ハング疑いは warning、background 実行エラーと速報クロスチェック異常は error"
      note: "仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。リラン指示・中止指示は状態更新の指示であり、集約というより並行稼働実行 / 依頼に対するコマンドとして扱う可能性が高い"
      source_model: "情報: 監視記録, 通知メール, 状態: 監視状態, 条件: 監視は通知のみ, ハング検知対象の除外, 通知レベルの判定, 警告傾向の記録"
      confidence: "low"
    - id: "AG-005"
      bounded_context_id: "BC-005"
      root_entity_id: "E-003"
      member_entity_ids:
        - "E-004"
      invariants:
        - "JOB_ID の行がジョブマップに存在するときのみ実行先を解決できる。未定義なら runner は非 0 の exitcode.txt と原因を含む stderr.log を出力する"
        - "固定引数は JSON 配列で引数の数と空白・カンマを維持し、その後ろに PARAM を順序を変えずに連結する。空の固定引数は []"
        - "hang_detect_limit_minutes の変更は次回以降の run の execution-spec.json にのみ反映される"
      note: "仮説。最終確定は dist-spec または ddd-tactical-implementation で行う。設定はファイルとして版管理されるため、集約というより不変の設定スナップショットとして扱う"
      source_model: "情報: ジョブマップ, ハング検知上限設定, 条件: ジョブマップ解決条件, 引数連結規則, ハング検知上限の調整基準"
      confidence: "low"
  diagram_mermaid: |
    graph LR
      BC5["適用構成コンテキスト"]
      BC1["並行稼働実行コンテキスト"]
      BC2["速報クロスチェックコンテキスト"]
      BC3["確報クロスチェックコンテキスト"]
      BC4["実行監視・復旧コンテキスト"]
      BC1 -->|Conformist| BC5
      BC2 -->|Conformist| BC5
      BC3 -->|Conformist| BC5
      BC1 -->|OHS+PL| BC2
      BC2 <-->|Shared Kernel| BC3
      BC4 -->|Conformist| BC1
      BC4 -->|Conformist| BC2
      BC4 -->|Conformist| BC3
```

## system_architecture.tiers

```yaml
  tiers:
    - id: "tier-facade"
      name: "facade / slot runner ティア"
      description: "ジョブスケジューラの業務ジョブから JOB_ID [PARAM...] で同期起動される CLI。facade.sh が feature flag(9 キー)で slot と mode を選択し、run_id を発行して blue / green slot runner を起動し、foreground の Runner Result だけを中継する。slot runner はジョブマップ(CSV)で実行先を解決し、SSH で実装スクリプトを実行して Runner Result を出力し、速報有効時(RAPID_CROSSCHECK_MODE が foreground / background)に RAPID_CROSSCHECK_RUNNER へ完了通知を送る。速報有効時の管理 DB 接続参照名は速報クロスチェック設定(rapid-crosscheck.env)から読み、off では読まない"
      technology_candidates:
        - "シェルスクリプト CLI(bash)"
        - "SSH クライアント(リモート実行ホストへの実装スクリプト起動)"
        - "ローカル / 共有ファイルシステム(成果物ディレクトリ facade/<run_id>/)"
        - "RDB クライアント CLI(速報有効時のみ parallel_run を作成。接続先は速報クロスチェック設定の RAPID_DB_CONN_REF で解決)"
      policies:
        - id: "SP-001"
          name: "facade の責務限定と slot 選択"
          description: "facade は JOB_ID [PARAM...] だけを受け取り、feature flag 設定(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の 9 キー。設定版は持たない)を起動のたびに読み込んで blue / green slot ごとに foreground / background / off を選択する。元資料の 9 キーは未知キーとして警告しない。比較対象や実装固有の起動方式は判断せず、設定された runner を起動するだけとする。off の slot は起動しない"
          reason: "条件「facade の責務限定」「slot 起動可否判定」により、ジョブスケジューラ側の定義を実装非依存に保ち runner の差し替えだけで世代交代を可能にするため"
          source_model: "外部システム: ジョブスケジューラ, 情報: ジョブ起動要求, feature flag 設定, 条件: facade の責務限定, slot 起動可否判定, 実装固有事項の runner への閉じ込め, BUC: 実装切替ジョブ実行フロー"
          confidence: "high"
        - id: "SP-002"
          name: "foreground slot 排他の入力検証"
          description: "blue と green の両方が foreground に設定された構成は入力検証で検出し、どの slot も起動せずエラー終了する。foreground は同時に 1 slot だけ許可する"
          reason: "条件「foreground slot 排他」。ジョブスケジューラへ返す結果は 1 系統でなければならないため"
          source_model: "条件: foreground slot 排他, バリエーション: slot 実行モード, 運用モード"
          confidence: "high"
        - id: "SP-003"
          name: "slot 起動順序と foreground 待機"
          description: "background の slot をすべて起動して PID と成果物ディレクトリを確定してから foreground slot を起動し、すべての slot 起動後に foreground の PID だけを待機する。並行稼働実行は STARTED から RUNNING へ遷移する"
          reason: "条件「slot 起動順序」。foreground が長時間実行中でも background slot を同時に実行させるため"
          source_model: "条件: slot 起動順序, 状態: 並行稼働実行, slot 実行"
          confidence: "high"
        - id: "SP-004"
          name: "ジョブスケジューラ応答の無加工中継"
          description: "foreground slot の stdout.log / stderr.log / exitcode.txt をそのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ中継し、中継完了で並行稼働実行を COMPLETED にする。background slot と速報クロスチェックの結果は応答に含めず待機もしない"
          reason: "条件「ジョブスケジューラ応答の決定」「速報結果の位置付け」。並行稼働中も単独本番中も運用者が同じ見え方で結果を判定できるようにするため"
          source_model: "条件: ジョブスケジューラ応答の決定, 速報結果の位置付け, 情報: ジョブスケジューラ応答, アクター: 運用者, NFR B.2.1.1"
          confidence: "high"
        - id: "SP-005"
          name: "確報クロスチェックの非起動"
          description: "確報クロスチェックの制御は feature flag に含めず、facade は確報クロスチェックを起動しない。確報はジョブスケジューラの別ジョブ定義から final-crosscheck-runner を直接起動する"
          reason: "条件「確報クロスチェック非起動」。確報は日次処理後の別タイミングで全量比較を行うため"
          source_model: "条件: 確報クロスチェック非起動, バリエーション: ジョブスケジューラ起動ジョブ種別"
          confidence: "high"
        - id: "SP-006"
          name: "ジョブマップによる実行先解決と引数連結"
          description: "slot runner は自 slot のジョブマップ(1 行目ヘッダーの CSV。列は job_id / host / user / work_dir / script / fixed_params / hang_detect_limit_minutes。credential_ref / map_version は末尾の任意列)に JOB_ID の行が存在するときのみ実行先を解決する。host / user はローカル実行の slot では省略できる。fixed_params は JSON 配列文字列を格納する CSV セル(二重引用符で囲み、セル内の二重引用符は二重化。空は [])で、bash 単独でクォートを解析する。固定引数の後ろに PARAM を順序を変えずに連結し、引数の数と空白・カンマを維持する。JOB_ID 未定義なら非 0 の exitcode.txt と原因を含む stderr.log を出力して終了する"
          reason: "条件「ジョブマップ解決条件」「引数連結規則」。ジョブスケジューラ側の定義に実行先を持たせないため"
          source_model: "条件: ジョブマップ解決条件, 引数連結規則, 情報: ジョブマップ, slot runner 割当, 外部システム: リモート実行ホスト(SSH), 現行実装(blue), 新実装(green)"
          confidence: "high"
        - id: "SP-007"
          name: "execution-spec の一度きりの確定保存"
          description: "run 開始時(並行稼働実行の STARTED 遷移時)に解決済みの実行設定・追加引数・マップ版(ジョブマップ側の任意列 map_version)・実装版(feature flag の BLUE_IMPL / GREEN_IMPL)・role ごとの hang_detect_limit_minutes を facade/<run_id>/execution-spec.json として一時ファイル経由で一度だけ保存する。以後ジョブマップを変更しても上書きしない。認証情報は値を保存せず参照名だけを保存する"
          reason: "条件「実行設定の確定条件」「認証情報の非保存」。ハング検知の判定基準・リランの再現性・障害調査の根拠とするため"
          source_model: "条件: 実行設定の確定条件, 認証情報の非保存, 情報: 実行設定(execution-spec), NFR E.5.1.1, NFR E.6.1.1"
          confidence: "high"
        - id: "SP-008"
          name: "速報クロスチェック有効判定と完了通知の系統独立"
          description: "facade はモードによらず run_id を発行し、RAPID_CROSSCHECK_MODE が foreground または background のときのみ parallel_run を作成する。runner は完了時に RAPID_CROSSCHECK_RUNNER が指す速報クロスチェック runner の自系統の公開 function(blue-completed / green-completed)で run_id・job_id・結果を通知する。off のときは完了通知を送らず、速報管理 DB へ接続も書き込みもせず parallel_run も作成しない。完了通知の送信失敗は自動検知しない: slot runner は実行ログに警告を残し、Runner Result と終了コードは変更しない。復旧は運用者が速報クロスチェック runner を同一引数で再実行する(冪等・先勝ち)。runner は相手側の状態や比較依頼の要否を判断せず、自 slot の中止状態(aborted.txt の有無)も判断しない。中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり完了通知を送り、中止済み run の扱いは速報クロスチェック runner に委ねる。速報有効時の管理 DB 接続は速報クロスチェック設定(rapid-crosscheck.env の RAPID_DB_CONN_REF)の接続参照名で解決し、認証情報の値は持たない"
          reason: "条件「速報クロスチェック有効判定」「完了通知の系統独立」「完了通知失敗の扱い」「中止済み run の比較依頼作成除外」(判断主体は速報クロスチェック runner)と情報「速報クロスチェック設定」。速報 DB 接続設定なしで slot 実行できるようにし、比較規約を rapid-crosscheck 側に閉じ込めるため"
          source_model: "条件: 速報クロスチェック有効判定, 完了通知の系統独立, 完了通知失敗の扱い, 中止済み run の比較依頼作成除外, 情報: 完了通知, 並行稼働実行(parallel_run), feature flag 設定, 速報クロスチェック設定, 実行ログ, バリエーション: 速報クロスチェックモード, NFR C.3.1.1, NFR C.3.3.1"
          confidence: "high"
      rules:
        - id: "SR-001"
          name: "Runner Result 完備"
          description: "slot 実行が終了したとき成果物ディレクトリに stdout.log / stderr.log / exitcode.txt を揃える。exitcode.txt は数値 1 行で runner の終了コードと一致させる。起動失敗・ジョブマップ未定義・SSH 失敗でも可能な限り 3 ファイルを出力する。started-at.txt は起動時に出力し、aborted.txt(中止日時 1 行)は明示中止時のみ abort-blue / abort-green が出力する。slot 実行の状態はファイル正本から導出する: exitcode.txt があれば SUCCEEDED(0)/ FAILED(非 0)、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING。background slot のリラン由来 run では、runner が終端時に parallel_run を COMPLETED にする(速報有効時)"
          reason: "条件「Runner Result 完備条件」「slot 実行の状態導出規則」。ジョブスケジューラ応答・完了通知・ハング検知・中止・リラン・障害調査が同じファイルを共通利用し、RAPID_CROSSCHECK_MODE=off でも状態を判定できるようにするため"
          source_model: "条件: Runner Result 完備条件, slot 実行の状態導出規則, 情報: Runner Result, 状態: slot 実行, 並行稼働実行, バリエーション: Runner Result 成果物種別"
          confidence: "high"
        - id: "SR-002"
          name: "実装固有事項の runner への閉じ込め"
          description: "実装固有の起動方式・ホスト・OS・プロトコル・SSH 接続方法は slot の runner 実体スクリプトに閉じ込める。facade と速報 / 確報の比較規約、ハング検知、リラン、中止の各スクリプトは runner を差し替えても変更しない"
          reason: "条件「実装固有事項の runner への閉じ込め」と NFR F.1.1.1(実装側の OS 差異は runner に閉じ込める)への対応"
          source_model: "条件: 実装固有事項の runner への閉じ込め, 情報: slot runner 割当, 適用構成文書, NFR F.1.1.1, NFR D.2.1.1"
          confidence: "high"
    - id: "tier-rapid-crosscheck"
      name: "速報クロスチェックティア"
      description: "rapid-crosscheck-runner(dispatcher。runner から完了通知を受ける一回ごとの起動スクリプト)と rapid-crosscheck-worker(管理 DB のジョブキューを継続的に poll / claim し、比較ツールでジョブ単位比較を実行して結果を登録する worker)で構成する。管理 DB 接続参照名・lease 期間・worker の poll 間隔は速報クロスチェック設定(rapid-crosscheck.env)から読む"
      technology_candidates:
        - "シェルスクリプト CLI(bash。dispatcher は都度起動、worker は常駐ループまたは定期起動。poll 間隔は速報クロスチェック設定の RAPID_POLL_INTERVAL_SEC)"
        - "RDB クライアント CLI(ジョブキュー: rapid_run / rapid_crosscheck_request / comparison_result。接続先は速報クロスチェック設定の RAPID_DB_CONN_REF で解決)"
        - "比較ツール起動アダプタ(job_id ごとの比較定義に従うコマンド実行)"
      policies:
        - id: "SP-009"
          name: "両系成功判定と比較依頼の一意作成"
          description: "dispatcher は完了通知を受けて rapid_run の blue_status / green_status を更新し、blue と green の両方が成功(exitcode 0)で完了したときに限り、完了順にかかわらず run_id を主キーとする速報比較依頼を 1 件だけ REQUESTED で作成する。いずれかが失敗した場合は作成しない。中止済み run(並行稼働実行(parallel_run)が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(成果物ディレクトリに aborted.txt が公開済み)のいずれか)では、完了通知を受けても両系成功でも依頼を作成せず、完了事実(blue_status / green_status と成果物 URI)だけを rapid_run に記録して実行ログに警告を残す。判定材料は管理 DB の parallel_run.status と slot_executions.status(ファイル正本 aborted.txt のミラー)。並行稼働実行は foreground slot の結果を中継した時点で COMPLETED になるため、foreground 完了後に background slot を abort-blue / abort-green で中止した典型経路は slot 実行 ABORTED の側で除外する。この判断は dispatcher が持ち、slot runner には持たせない。速報有効時(foreground / background)だけに適用する"
          reason: "条件「両系成功判定」「比較依頼の一意性」「中止済み run の比較依頼作成除外」(判定キー: 並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)。失敗結果同士や片方失敗の比較と重複作成を防ぎ、中止後に実装が走り切った run の比較を止めるため。並行稼働実行だけを見ると foreground 完了後の background 中止が除外されないため slot 実行の状態も判定材料にする。比較の要否判断を方針資料どおり速報クロスチェック側に閉じ込める"
          source_model: "条件: 両系成功判定, 比較依頼の一意性, 中止済み run の比較依頼作成除外, 状態: 速報実行の完了状況, 並行稼働実行, slot 実行, 情報: 速報実行(rapid_run), 速報比較依頼(rapid_crosscheck_request), 完了通知, slot 実行, 実行ログ, BUC: 速報クロスチェックフロー, NFR C.3.3.1"
          confidence: "high"
        - id: "SP-010"
          name: "worker の poll / claim / lease による多重実行防止"
          description: "worker は管理 DB を poll し、REQUESTED の依頼を worker_id と lease_until 付きで CLAIMED にする。lease 有効中は他の worker が同じ依頼を取得できない。lease が失効しかつ比較が未開始なら REQUESTED に戻し、別の worker が再取得できるようにする。lease 期間(RAPID_LEASE_SEC)と poll 間隔(RAPID_POLL_INTERVAL_SEC)は速報クロスチェック設定から読み、コードに埋め込まない。worker はサーバ追加で水平に増やせる"
          reason: "条件「claim 排他」「lease 失効判定」と情報「速報クロスチェック設定」、NFR B.3.1.1(スケールアウト)への対応"
          source_model: "条件: claim 排他, lease 失効判定, 状態: クロスチェック依頼, 情報: 速報クロスチェック設定, NFR B.3.1.1, NFR B.1.2.1"
          confidence: "high"
        - id: "SP-011"
          name: "比較定義に従うジョブ単位比較と結果登録"
          description: "claim した worker は依頼を status = CLAIMED を条件とする条件付き UPDATE で RUNNING にし、更新件数が 0 件(abort-rapid-crosscheck で ABORTED 済み)なら比較を開始せず終了する(comparison_result も登録しない)。RUNNING にできたときだけクロスチェックジョブマップ(CSV)の job_id ごとの比較定義に従って比較ツールでジョブ単位比較を実行する。比較ツールの stdout / stderr / exitcode を依頼に保存し、exitcode 0 で SUCCEEDED、非 0(3=比較 NG / 6=実行エラー)または実行エラーで FAILED とする。comparison_result は比較ツールを起動して終了コードを得たときだけ登録し、比較定義なし・起動失敗では登録せず依頼だけを FAILED(exit_code=6 相当、error_summary に理由)で終端する。速報比較依頼だけを新規作成したリラン由来の parallel_run は、依頼が終端状態(SUCCEEDED / FAILED)になった時点で worker が COMPLETED にする"
          reason: "条件「比較定義の選択」「依頼状態遷移規則」「比較ツール終了コードの対応」「比較結果の登録条件」「依頼中止可否判定」(CLAIMED 中止時の競合規則)と状態モデル「クロスチェック依頼」(CLAIMED → RUNNING は条件付き UPDATE)「並行稼働実行」(リラン由来 run の COMPLETED 到達)。比較実装は外部ツールに委譲し、規約だけを worker に閉じ込める。claim 後に abort-rapid-crosscheck で中止された依頼の比較を開始しないため"
          source_model: "条件: 比較定義の選択, 依頼状態遷移規則, 比較ツール終了コードの対応, 比較結果の登録条件, 依頼中止可否判定, 外部システム: 比較ツール, 情報: 比較定義, 比較結果(comparison_result), 比較ツール実行結果, 状態: 並行稼働実行, クロスチェック依頼"
          confidence: "high"
        - id: "SP-012"
          name: "速報結果の位置付け(原因調査用)"
          description: "速報クロスチェックの exitcode や失敗は通常業務ジョブの結果としてジョブスケジューラへ返さない。比較結果(comparison_result)と依頼の stdout / stderr / exitcode は運用者が run_id で参照し、両実装の差分の原因調査に使う。リリース判断の正本には用いない"
          reason: "条件「速報結果の位置付け」。速報は非同期の background 処理であり本番結果に影響させないため"
          source_model: "条件: 速報結果の位置付け, アクター: 運用者, バリエーション: 比較結果ステータス, クロスチェック種別"
          confidence: "high"
      rules:
        - id: "SR-003"
          name: "速報側データモデルの所有"
          description: "rapid_run / rapid_crosscheck_request / comparison_result は速報クロスチェックティアだけが作成・更新する。確報側および facade は参照・作成しない。parallel_run の作成は facade と background-rerun が行い、速報クロスチェックティアはリラン由来 run の COMPLETED 更新だけを行う"
          reason: "方針資料「速報と確報の比較規約はそれぞれ別ドメインが所有する」への対応。管理 DB は relay-gate 内部のジョブキュー兼管理 DB として速報側 / 確報側のテーブルを分離する"
          source_model: "条件: 速報と確報のモデル分離, システム概要: ジョブキュー兼管理 DB(内部データストア), 状態: 並行稼働実行"
          confidence: "high"
    - id: "tier-final-crosscheck"
      name: "確報クロスチェックティア"
      description: "ジョブスケジューラの別ジョブ定義から起動される final-crosscheck-runner(依頼登録 → 終端状態まで同期 polling → 保存済み結果の中継)と、DB セグメントで依頼を poll / claim して全テーブル・全ファイルの日次全量比較を実行する final-crosscheck-worker で構成する"
      technology_candidates:
        - "シェルスクリプト CLI(bash。runner は都度起動、worker は DB セグメント上の常駐ループまたは定期起動)"
        - "RDB クライアント CLI(ジョブキュー: final_crosscheck_request / 対象カタログ)"
        - "比較ツール起動アダプタ(対象カタログに基づく全量比較)"
      policies:
        - id: "SP-013"
          name: "確報比較依頼の登録と同期 polling"
          description: "runner はジョブスケジューラから起動されたとき business_date と対象カタログの版を持つ確報比較依頼を REQUESTED で登録し、SUCCEEDED / FAILED / ABORTED の終端状態になるまで同期 polling する。日次確報は夜間バッチウィンドウ内(8 時間以内)に完了させる"
          reason: "条件「確報依頼の登録条件」と NFR B.2.2.1(バッチ処理時間)への対応"
          source_model: "条件: 確報依頼の登録条件, 情報: 確報比較依頼(final_crosscheck_request), 対象カタログ, 外部システム: ジョブスケジューラ, BUC: 確報クロスチェックフロー, NFR B.2.2.1"
          confidence: "high"
        - id: "SP-014"
          name: "確報結果の無加工中継"
          description: "runner は依頼に保存された stdout / stderr / exitcode だけをそのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ返す。チェック結果・差分件数・レポート URI などの追加連携データや依頼の状態名は返さない。比較 OK=0 / 比較 NG=3(警告終了) / 実行エラー=6(エラー終了)の終了コードをそのまま中継する"
          reason: "条件「確報結果の中継制約」「比較ツール終了コードの対応」。ジョブスケジューラ側の判定を比較ツールの終了コード契約に委ねるため"
          source_model: "条件: 確報結果の中継制約, 比較ツール終了コードの対応, 外部システム: 比較ツール, バリエーション: 比較ツール終了コード, アクター: 運用者"
          confidence: "high"
        - id: "SP-015"
          name: "確報 worker の DB セグメント実行と claim / lease"
          description: "worker は DB セグメントで管理 DB を poll し、REQUESTED の確報比較依頼を worker_id と lease_until 付きで CLAIMED にし、RUNNING で対象カタログに従う全量比較を実行して stdout / stderr / exitcode を保存する。lease 失効かつ未開始なら REQUESTED に戻す規則は速報と同一とする"
          reason: "条件「依頼状態遷移規則」「claim 排他」「lease 失効判定」。DB セグメント経由の配置制約を worker 側に閉じ込めるため"
          source_model: "条件: 依頼状態遷移規則, claim 排他, lease 失効判定, 状態: クロスチェック依頼, 情報: 比較ツール実行結果, 適用構成文書"
          confidence: "high"
      rules:
        - id: "SR-004"
          name: "速報と確報のモデル分離"
          description: "確報クロスチェックは final_crosscheck_request と対象カタログだけを用い、rapid_run / rapid_crosscheck_request を作成・変更しない。確報の再実行はジョブスケジューラの正規ジョブを直接再実行し、background-rerun を使わない"
          reason: "条件「速報と確報のモデル分離」「復旧手段の選択」への対応"
          source_model: "条件: 速報と確報のモデル分離, 復旧手段の選択, バリエーション: 再実行経路"
          confidence: "high"
    - id: "tier-ops"
      name: "実行監視・復旧ティア"
      description: "hang-detector(ジョブスケジューラの定期ジョブ)、background-rerun(専用ジョブ)、abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck(運用者が配置ディレクトリから直接起動する対話 CLI)で構成する。監視は通知のみ、中止は状態更新(slot は aborted.txt の書き込みを正本とする)のみ、リランは execution-spec.json からの復元で行う。通知先・送信コマンド・件名プレフィックス・管理 DB 接続参照名はハング検知定期ジョブ設定から読む"
      technology_candidates:
        - "シェルスクリプト CLI(bash。定期ジョブ / 専用ジョブ / 対話 CLI)"
        - "OS 標準のメール送信コマンド(warning / error 通知。コマンドと宛先はハング検知定期ジョブ設定で指定)"
        - "RDB クライアント CLI(監視記録・状態更新・parallel_run 作成。RAPID_CROSSCHECK_MODE=off では使わない)"
        - "ファイルシステム走査・書き込み(started-at.txt / exitcode.txt / aborted.txt / execution-spec.json)"
      policies:
        - id: "SP-016"
          name: "ハング検知判定と対象除外"
          description: "定期ジョブ(5 分ごとなど)として未終端の background role を走査し、started-at.txt と execution-spec.json の hang_detect_limit_minutes から経過時間を判定する。exitcode.txt があり 0 なら正常終了、非 0 なら background 実行エラーとして通知、無く aborted.txt があれば中止済みとして監視記録を終端、どちらも無く上限以内なら継続監視、上限超過ならハング疑いとして通知する。ハング疑い通知済みの対象も再判定し、正常終了(exitcode 0)・実行エラー(非 0)・比較異常(速報比較依頼が NG / FAILED)・中止済みで監視記録を終端する。hang_detect_limit_minutes が 0 の role と foreground role は検知対象から除外する。RAPID_CROSSCHECK_MODE=off でも管理 DB なしで slot 成果物ファイルだけを走査する。完了通知の送信失敗は検知対象に含めない"
          reason: "条件「ハング検知判定」「ハング検知対象の除外」「slot 実行の状態導出規則」「完了通知失敗の扱い」と状態モデル「監視状態」(通知後・中止後の終端遷移)、NFR C.1.3.1(アプリケーション監視)・C.3.1.1(自動検知+自動通知+自動記録)への対応"
          source_model: "条件: ハング検知判定, ハング検知対象の除外, slot 実行の状態導出規則, 完了通知失敗の扱い, 状態: 監視状態, 情報: 監視記録, Runner Result, BUC: background 実行監視フロー, NFR C.1.3.1, NFR C.3.1.1, NFR C.1.1.1, NFR C.1.3.2"
          confidence: "high"
        - id: "SP-017"
          name: "速報比較依頼の異常判定"
          description: "速報比較依頼が FAILED または比較 NG のとき速報クロスチェック異常として通知し、RUNNING のときは状態を変更せずハング疑いとして通知する"
          reason: "条件「速報比較依頼の異常判定」。ジョブスケジューラ応答に現れない速報異常を見落とさないため"
          source_model: "条件: 速報比較依頼の異常判定, バリエーション: 速報クロスチェック監視判定"
          confidence: "high"
        - id: "SP-018"
          name: "監視は通知のみ・通知レベル・警告傾向の記録"
          description: "監視は monitor_status(監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了)/ hang_suspected_at / alerted_at を記録して運用者へメール通知するだけとし、RUNNING を ABORTED にせず、プロセスを停止せず、新しい実行依頼を作成しない。ハング疑いは warning、background 実行エラーと速報クロスチェック異常は error で送る。宛先・送信コマンド・件名プレフィックスはハング検知定期ジョブ設定(ALERT_MAIL_TO / ALERT_MAIL_CMD / ALERT_SUBJECT_PREFIX)から読む。通知後に正常終了した実行(通知後正常終了)についても警告時の経過時間を記録し、hang_detect_limit_minutes の調整根拠にする"
          reason: "条件「監視は通知のみ」「通知レベルの判定」「警告傾向の記録」と情報「ハング検知定期ジョブ設定」。静観か対処かの判断を運用者に委ねるため"
          source_model: "条件: 監視は通知のみ, 通知レベルの判定, 警告傾向の記録, 外部システム: メール通知, 情報: 通知メール, 監視記録, ハング検知定期ジョブ設定, アクター: 運用者, バリエーション: 監視状態, NFR C.5.1.1, NFR C.3.2.1"
          confidence: "high"
        - id: "SP-019"
          name: "ハング検知上限の調整基準"
          description: "hang_detect_limit_minutes は導入時に全ジョブ 60 分とし、正常終了パターンの警告が出そろった時点で運用者がジョブごとに最後の警告の経過時間を基準に調整する。調整はジョブマップの列値を更新して行い、調整日時と調整根拠(警告時経過時間)の記録は適用構成文書に残す(ジョブマップの列には持たない)。変更は次回以降の run の execution-spec.json にのみ反映される"
          reason: "条件「ハング検知上限の調整基準」と情報「適用構成文書」(運用者の調整記録)への対応"
          source_model: "条件: ハング検知上限の調整基準, 情報: ハング検知上限設定, 適用構成文書, 監視記録, バリエーション: ハング検知上限設定"
          confidence: "high"
        - id: "SP-020"
          name: "background 側リランの事前検証と復元"
          description: "background-rerun は --source-run-id と --role を受け、元の execution-spec.json とファイル正本の状態(exitcode.txt / aborted.txt)を事前検証し、速報有効時は管理 DB の状態も照合する。--role blue / green は元の slot mode が background のときだけ新しい run_id で再実行し、foreground または off ならエラー終了する。--role rapid-crosscheck は業務ジョブを再実行せず速報比較依頼だけを新規作成する。未対応の role、元の実行が見つからない、元の実行が RUNNING(exitcode.txt も aborted.txt も無い)または中止未確認ならエラー終了する。RAPID_CROSSCHECK_MODE=off でも aborted.txt があれば管理 DB なしで background slot をリランできる。最新のジョブマップは再解決せず、元の execution-spec.json から実行パラメータ・host・user・script・work_dir を復元する。新しい parallel_run の parent_run_id には直前のリラン元 run_id を設定し、background slot のリラン由来 run は runner が終端時に、速報比較依頼だけのリラン由来 run は worker が依頼終端時に COMPLETED にする"
          reason: "条件「リラン事前検証」「リランの実行設定復元」「リラン系譜の追跡」「slot 実行の状態導出規則」と状態モデル「並行稼働実行」(リラン由来 run の COMPLETED 到達)、NFR A.4.1.1 / A.4.1.2 / A.4.1.3(execution-spec と Runner Result からの復旧。縮退運転 off でも中止・リランが成立)への対応"
          source_model: "条件: リラン事前検証, リランの実行設定復元, リラン系譜の追跡, slot 実行の状態導出規則, 情報: リラン指示, Runner Result, 状態: 並行稼働実行, BUC: background 側リランフロー, NFR A.4.1.1, NFR A.4.1.2, NFR A.4.1.3"
          confidence: "high"
        - id: "SP-021"
          name: "復旧手段の選択"
          description: "background slot 実行と速報比較依頼は専用ジョブの background-rerun で再実行し、foreground slot 実行と確報クロスチェックはジョブスケジューラの正規ジョブを直接再実行する。RUNNING の background 実行は運用者が明示中止してからリランする"
          reason: "条件「復旧手段の選択」への対応"
          source_model: "条件: 復旧手段の選択, バリエーション: 再実行経路, リラン対象 role"
          confidence: "high"
        - id: "SP-022"
          name: "中止スクリプトの可否判定と停止確認応答"
          description: "abort-blue / abort-green は対象 slot が background かつ RUNNING(exitcode.txt も aborted.txt も無い)のときだけ、abort-rapid-crosscheck は対象の速報比較依頼が REQUESTED / CLAIMED / RUNNING のいずれかのとき、abort-final-crosscheck は対象の確報比較依頼が RUNNING のときだけ ABORTED へ遷移できる(確報の未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中であり runner 側の polling 上限で扱う)。それ以外(終端済み、または確報で RUNNING 以外)は状態を変更せずエラー終了する。現在状態を表示後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と対話確認し、yes のときだけ状態を更新する。abort-rapid-crosscheck は worker のプロセス停止を運用者に確認したうえで status IN (REQUESTED, CLAIMED, RUNNING) を条件とする条件付き UPDATE で ABORTED にする(CLAIMED を放置すると lease 失効で REQUESTED に戻り別の worker が再 claim して比較が実行されるため、中止済み run の依頼を運用者が止める手段。claim 済み worker は RUNNING への条件付き UPDATE が 0 件になり比較を開始しない)。slot の中止は成果物ディレクトリへ aborted.txt(中止日時 1 行)を一時ファイル経由で書くことを正本とし、RAPID_CROSSCHECK_MODE が off でも成立する。off 以外なら管理 DB の slot 実行と並行稼働実行(STARTED / RUNNING のどちらからでも)も ABORTED に更新し、対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があればそれも ABORTED にする(両系の完了通知で依頼が REQUESTED で作成された直後に slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定(SP-009)と併用する。CLAIMED / RUNNING の依頼は変更せず abort-rapid-crosscheck の対象とする。速報比較依頼のみで確報比較依頼には適用しない)。スクリプト自身はプロセス・Pod・SSH 接続先の処理を停止しない。指示者と応答は実行ログに残す"
          reason: "条件「slot 中止可否判定」「依頼中止可否判定」(速報比較依頼は REQUESTED / CLAIMED / RUNNING、確報比較依頼は RUNNING のみ。CLAIMED 中止時の競合規則)「停止確認応答」「slot 実行の状態導出規則」と状態モデル「並行稼働実行」(STARTED → ABORTED)「クロスチェック依頼」(REQUESTED / CLAIMED / RUNNING → ABORTED)、バリエーション「中止対象種別」、NFR E.7.1.1(運用操作の記録)・A.4.1.3(縮退運転 off でも中止が成立)・C.3.3.1(手動復旧)への対応。CLAIMED の依頼を運用者が止められず lease 失効後に比較が実行される抜けと、両 slot 完了直後に中止した場合に未着手依頼だけが残る競合窓を塞ぐため"
          source_model: "条件: slot 中止可否判定, 依頼中止可否判定, 停止確認応答, slot 実行の状態導出規則, 中止済み run の比較依頼作成除外, 情報: 中止指示, Runner Result, 速報比較依頼(rapid_crosscheck_request), 確報比較依頼(final_crosscheck_request), BUC: 実行中止フロー, 状態: slot 実行, 並行稼働実行, クロスチェック依頼, バリエーション: 中止対象種別, 停止確認応答, NFR E.7.1.1, NFR A.4.1.3, NFR C.3.3.1"
          confidence: "high"
      rules:
        - id: "SR-005"
          name: "監視・復旧スクリプトの facade からの分離"
          description: "hang-detector / background-rerun / abort-* は通常起動の facade から分離し、ジョブスケジューラの別ジョブ定義または運用者の直接起動で動かす。facade の実行経路にこれらの処理を混ぜない"
          reason: "方針資料「ハング監視と background 側の選択リランは通常起動の facade から分離する」への対応"
          source_model: "バリエーション: ジョブスケジューラ起動ジョブ種別, 外部システム: ジョブスケジューラ"
          confidence: "high"
    - id: "tier-datastore"
      name: "データストアティア"
      description: "管理 DB(RDB。relay-gate 内部のジョブキュー兼管理 DB。外部システムではない)、成果物ディレクトリ(facade/<run_id>/ 配下の Runner Result と execution-spec.json)、設定ファイル(feature flag / ジョブマップ / クロスチェックジョブマップ / 対象カタログ / ハング検知定期ジョブ設定 / 速報クロスチェック設定 / 適用文書)、実行ログファイルで構成する"
      technology_candidates:
        - "RDB(単一インスタンス。速報側と確報側のテーブルを分離)"
        - "ローカル / 共有ファイルシステム(成果物ディレクトリ・設定ファイル・実行ログ)"
      policies:
        - id: "SP-023"
          name: "管理 DB をジョブキューとして使う"
          description: "MQ を導入せず、管理 DB の依頼レコード(rapid_crosscheck_request / final_crosscheck_request)を worker が poll / claim するジョブキューとして使う。速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)のテーブルを分離し、監視記録もここに保持する"
          reason: "システム概要で管理 DB(RDB)が relay-gate 内部のジョブキュー兼管理 DB と定義され、NFR B.2.1.2(〜10 TPS)の低頻度書き込みで十分なため。エアーギャップ環境で追加ミドルウェアを増やさない"
          source_model: "システム概要: ジョブキュー兼管理 DB(内部データストア), 条件: 速報と確報のモデル分離, claim 排他, NFR B.2.1.2, NFR B.1.1.1, NFR B.1.1.3, NFR A.2.5.1"
          confidence: "high"
        - id: "SP-024"
          name: "成果物ファイルを外部 IF の正本にする"
          description: "Runner Result(started-at.txt / stdout.log / stderr.log / exitcode.txt。中止時のみ aborted.txt)と execution-spec.json はファイルとして成果物ディレクトリに残し、ジョブスケジューラ応答・完了通知・ハング検知・中止・リラン・障害調査が共通に参照する。slot 実行の状態はこのファイル正本から導出し、RAPID_CROSSCHECK_MODE=off では管理 DB なしにファイルだけで slot 実行・監視・中止・リランが成立する"
          reason: "Runner Result Contract と条件「実行履歴はジョブスケジューラの責務」「slot 実行の状態導出規則」への対応。DB 喪失時も execution-spec.json と Runner Result からリランできる(NFR A.3.1.1 / A.4.1.1 / A.4.1.3)"
          source_model: "情報: Runner Result, 実行設定(execution-spec), 条件: 実行履歴はジョブスケジューラの責務, slot 実行の状態導出規則, NFR A.3.1.1, NFR A.3.1.2, NFR A.4.1.1, NFR A.4.1.3, NFR F.1.2.2"
          confidence: "high"
        - id: "SP-025"
          name: "設定所有区分に基づく設定ファイル配置"
          description: "実装スロット・実装版(BLUE_IMPL / GREEN_IMPL)・runner と完了通知先・worker 実体の割当は feature flag(env 形式 9 キー)、実行先とハング検知上限は該当 slot のジョブマップ(CSV)、比較対象と対象カタログはクロスチェックジョブマップ(CSV)、通知先メールアドレス・送信コマンド・件名プレフィックス・管理 DB 接続参照名はハング検知定期ジョブ設定(env 形式)、速報クロスチェックの管理 DB 接続参照名(RAPID_DB_CONN_REF)・lease 期間(RAPID_LEASE_SEC)・worker の poll 間隔(RAPID_POLL_INTERVAL_SEC)は速報クロスチェック設定(env 形式 rapid-crosscheck.env。facade・slot runner・速報クロスチェック runner・worker が読み、RAPID_CROSSCHECK_MODE=off では不要)、外部 IF 方針・ネットワーク制約・ホスト配置・hang_detect_limit_minutes の調整記録は適用文書が所有する。所有者はいずれも基盤適用設計者。接続参照名は値を置かず参照名のみとする。feature flag は設定版を持たず、実装版は BLUE_IMPL / GREEN_IMPL、マップ版はジョブマップ側の任意列 map_version、カタログ版・文書版はそれぞれのファイルが持ち、適用側が版管理する"
          reason: "条件「設定所有区分」「適用側で定義する事項」と元の方針資料の設定契約(9 キー・CSV 列名)への対応。正本を一意に定め、relay-gate のスクリプトを変更せずに案件・世代を切り替えるため"
          source_model: "条件: 設定所有区分, 適用側で定義する事項, ジョブマップ解決条件, 認証情報の非保存, 情報: feature flag 設定, ジョブマップ, クロスチェックジョブマップ, 対象カタログ, ハング検知定期ジョブ設定, 速報クロスチェック設定, 適用構成文書, バリエーション: 設定所有区分, アクター: 基盤適用設計者, BUC: 適用構成定義フロー, NFR C.2.2.1, NFR C.1.2.2, NFR E.5.1.1"
          confidence: "high"
        - id: "SP-026"
          name: "バックアップと復旧地点"
          description: "管理 DB は日次のフル+差分バックアップを取り、数時間以内の復旧地点(RPO)と半日以内の復旧(RTO)を目標にする。成果物ディレクトリと管理 DB は最低限のミラーリング(RAID1 相当)に置く。遠隔地の災害対策は基盤単体では持たない"
          reason: "NFR C.1.2.1(フル+差分バックアップ日次)、A.4.1.1(RPO 数時間)、A.4.1.2(RTO 半日)、A.2.5.1(ストレージ冗長化)、A.3.1.1(災害対策なし)への対応"
          source_model: "NFR C.1.2.1, NFR A.4.1.1, NFR A.4.1.2, NFR A.2.5.1, NFR A.3.1.1, NFR A.2.1.1"
          confidence: "medium"
      rules:
        - id: "SR-006"
          name: "機密データ非保持"
          description: "管理 DB と成果物には認証情報の値を保存しない(参照名のみ)。保管時暗号化は要求しない。成果物の stdout / stderr に業務データが含まれるかは適用側で確認し、必要ならファイルシステムの OS 権限で保護する"
          reason: "条件「認証情報の非保存」と NFR E.6.1.1(保管時暗号化なし)・E.5.2.1(OS 権限によるアクセス制御)への対応"
          source_model: "条件: 認証情報の非保存, NFR E.6.1.1, NFR E.5.2.1"
          confidence: "high"
```

## app_architecture.tier_layers

```yaml
  tier_layers:
    - tier_id: "tier-facade"
      layers:
        - id: "L-facade-presentation"
          name: "プレゼンテーション層(CLI エントリ)"
          responsibility: "facade.sh / blue-runner / green-runner の CLI 入口。JOB_ID [PARAM...] と feature flag の入力検証(foreground slot 排他を含む)、終了コードの決定、foreground の Runner Result の標準出力・標準エラー・終了コードへの無加工中継"
          allowed_dependencies:
            - "L-facade-usecase"
          policies:
            - id: "LP-001"
              name: "入力検証で拒否する構成"
              description: "両 slot foreground、未知の実行モード、JOB_ID 欠落は入力検証でエラー終了し、どの slot も起動しない。原因は stderr に英語で出す"
              reason: "条件「foreground slot 排他」への対応"
              source_model: "条件: foreground slot 排他, 情報: ジョブ起動要求"
              confidence: "high"
            - id: "LP-002"
              name: "応答の無加工中継"
              description: "presentation は foreground の stdout.log / stderr.log / exitcode.txt を加工せず中継する。background slot と速報の結果は応答に反映しない"
              reason: "条件「ジョブスケジューラ応答の決定」への対応"
              source_model: "条件: ジョブスケジューラ応答の決定, 情報: ジョブスケジューラ応答"
              confidence: "high"
          rules: []
        - id: "L-facade-usecase"
          name: "ユースケース層"
          responsibility: "slot 起動フロー(background 起動 → foreground 起動 → foreground 待機 → 中継)、run_id 発行(モードによらず)と parallel_run 作成(速報有効時のみ)、実行先解決 → execution-spec 確定保存 → 実装実行 → Runner Result 公開 → 完了通知(送信失敗は警告ログのみ)→ リラン由来 run の parallel_run COMPLETED 更新のフロー制御"
          allowed_dependencies:
            - "L-facade-domain"
            - "L-facade-repository"
          policies:
            - id: "LP-003"
              name: "起動順序の固定"
              description: "usecase は background slot をすべて起動して PID と成果物ディレクトリを確定してから foreground slot を起動し、foreground の PID だけを待機する"
              reason: "条件「slot 起動順序」への対応"
              source_model: "条件: slot 起動順序, 状態: 並行稼働実行"
              confidence: "high"
            - id: "LP-004"
              name: "速報有効時のみ管理 DB に触れる"
              description: "RAPID_CROSSCHECK_MODE=off のとき usecase は parallel_run 作成・完了通知を行わず、管理 DB の repository を呼ばない。run_id の発行と成果物ディレクトリの作成はモードによらず行う。foreground / background のときは完了通知の送信失敗を警告ログに残すだけで、Runner Result と終了コードは変更しない"
              reason: "条件「速報クロスチェック有効判定」「完了通知失敗の扱い」への対応"
              source_model: "条件: 速報クロスチェック有効判定, 完了通知の系統独立, 完了通知失敗の扱い, 情報: 実行ログ"
              confidence: "high"
          rules: []
        - id: "L-facade-domain"
          name: "ドメイン層"
          responsibility: "slot 実行モードの判定表(起動可否・foreground 排他)、feature flag 9 キーの検証、run_id の生成規則、並行稼働実行と slot 実行の状態遷移、CSV セル(fixed_params)の解析と引数連結規則、exitcode.txt / aborted.txt → SUCCEEDED / FAILED / ABORTED / RUNNING の状態導出など、副作用を持たない純粋関数"
          allowed_dependencies: []
          policies:
            - id: "LP-005"
              name: "状態遷移と判定表をドメインに集約"
              description: "STARTED → RUNNING → COMPLETED / ABORTED、STARTED → ABORTED、RUNNING → SUCCEEDED / FAILED / ABORTED の遷移と、slot 起動可否・引数連結規則・slot 実行の状態導出規則(exitcode.txt があれば SUCCEEDED / FAILED、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING)・run_id 生成規則({ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex})の判定はドメイン層の関数として実装し、テスト可能にする。ドメイン層は直接ログ出力を行わない"
              reason: "条件「slot 起動可否判定」「引数連結規則」「slot 実行の状態導出規則」と状態モデル「並行稼働実行」「slot 実行」、情報「並行稼働実行(parallel_run)」の run_id 形式への対応"
              source_model: "条件: slot 起動可否判定, 引数連結規則, slot 実行の状態導出規則, 状態: 並行稼働実行, slot 実行, 情報: 並行稼働実行(parallel_run)"
              confidence: "high"
          rules: []
        - id: "L-facade-repository"
          name: "リポジトリ層"
          responsibility: "parallel_run(管理 DB)、execution-spec / Runner Result(成果物ディレクトリ。aborted.txt の有無を含む)、feature flag(env 形式 9 キー)/ ジョブマップ(CSV。credential_ref / map_version は任意列)/ 速報クロスチェック設定(env 形式 rapid-crosscheck.env。速報有効時のみ読み、RAPID_DB_CONN_REF で管理 DB の接続先を解決する)の読み書きを集約単位で提供する"
          allowed_dependencies:
            - "L-facade-domain"
            - "L-facade-gateway"
          policies:
            - id: "LP-006"
              name: "execution-spec の一度きり保存"
              description: "repository は execution-spec.json を一時ファイル → リネームで一度だけ作成し、既存ファイルがあれば上書きしない。認証情報は参照名のみを書く"
              reason: "条件「実行設定の確定条件」「認証情報の非保存」「成果物公開判定」への対応"
              source_model: "条件: 実行設定の確定条件, 認証情報の非保存, 成果物公開判定, 情報: 実行設定(execution-spec)"
              confidence: "high"
          rules: []
        - id: "L-facade-gateway"
          name: "ゲートウェイ層"
          responsibility: "SSH アダプタ(リモート実行ホストで実装スクリプトを作業ディレクトリ・引数付きで実行。host / user 省略時はローカル実行)、ファイルシステムアダプタ(一時ファイル書き込みとリネーム、started-at.txt / exitcode.txt 出力)、RDB クライアントアダプタ(速報クロスチェック設定の接続参照名で接続)、速報クロスチェック runner 呼び出しアダプタ(RAPID_CROSSCHECK_RUNNER が指す実体の blue-completed / green-completed。自 slot の中止状態は判断しない)"
          allowed_dependencies: []
          policies:
            - id: "LP-007"
              name: "異常時も 3 ファイルを揃える"
              description: "SSH 失敗・起動失敗・ジョブマップ未定義でも gateway は可能な限り stdout.log / stderr.log / exitcode.txt を出力し、失敗理由を stderr.log に残す"
              reason: "条件「Runner Result 完備条件」「ジョブマップ解決条件」への対応"
              source_model: "条件: Runner Result 完備条件, ジョブマップ解決条件, 外部システム: リモート実行ホスト(SSH)"
              confidence: "high"
            - id: "LP-022"
              name: "完了通知の送信失敗は警告のみ"
              description: "完了通知アダプタの失敗(速報クロスチェック runner の起動失敗・非 0 終了)は技術例外として usecase に返し、usecase は実行ログに warning を残すだけで Runner Result と slot runner の終了コードを変更しない。再送は行わず、復旧は運用者が同一引数で速報クロスチェック runner を再実行する"
              reason: "条件「完了通知失敗の扱い」への対応。通知失敗で業務ジョブの結果を変えないため"
              source_model: "条件: 完了通知失敗の扱い, 情報: 完了通知, 実行ログ, NFR C.3.3.1"
              confidence: "high"
          rules: []
      cross_layer_policies:
        - id: "CLP-001"
          name: "IF なし(直接依存)"
          description: "レイヤー間は bash の source による関数呼び出しで直接依存し、抽象 IF は置かない。RDB 製品や比較ツールの差し替えは gateway アダプタの差し替えで吸収する"
          reason: "シェルスクリプトであり抽象化の手段が限られるため。一般的なベストプラクティスとして適用"
          source_model: "なし"
          confidence: "default"
        - id: "CLP-002"
          name: "実行ログの出力方針"
          description: "usecase 層が run_id 付きの実行ログ(スクリプト名 / run_id / 日時 / レベル / メッセージ)をファイルへ出力する集約ポイントとする。gateway は外部呼び出し(SSH / RDB / 比較ツール / メール)の開始・終了・所要時間・成否を記録し、失敗は技術例外として非 0 で返す。domain 層はログを出さない。ログ出力先は stdout / stderr を汚さない専用ファイルとする。ログの日時はホストのローカルタイムゾーン(プロセスの TZ 環境変数に従う)で ISO 8601 秒精度、タイムゾーン指示子(Z / オフセット)なしとし、run_id の時刻部と同じ時刻軸にそろえる。UTC への統一は行わない。管理 DB の *_at 列は RDB のタイムスタンプ型に委ね、CLI が stdout に表示する日時もローカル時刻で出す。テスト用の時刻注入(RELAY_GATE_NOW)は UTC の Z 付きで受け付け、内部でローカル時刻へ変換してから使う。この方針は全ティアの実行ログ方針に共通し(CLP-004 / CLP-006 が参照)、tier-ops の運用操作記録(CLP-008)も同じ日時規則に従う"
          reason: "利用者指定: run_id の時刻部(ローカルタイムゾーン)と実行ログの日時を同じ時刻軸にそろえ、障害調査で運用者が時差を読み替えずに突き合わせられるようにする。NFR C.6.1.1(ログ保管)・C.3.1.1(自動記録)・E.7.1.1(監査)への対応"
          source_model: "情報: 実行ログ, 並行稼働実行(parallel_run), NFR C.6.1.1, NFR C.3.1.1, NFR E.7.1.1"
          confidence: "high"
      cross_layer_rules:
        - id: "CLR-001"
          name: "エラーハンドリングと終了コード"
          description: "set -euo pipefail を基本とし、domain / repository / gateway のエラーは usecase で 1 回だけログ出力して presentation へ返し、presentation が終了コードを決める。catch の握り潰しと多重ログを禁止する"
          reason: "レイヤー責務の分離。一般的なベストプラクティスとして適用"
          source_model: "なし"
          confidence: "default"
      diagram_mermaid: |
        graph TD
          P[presentation: facade.sh / runner CLI] --> U[usecase: slot 起動フロー]
          U --> D[domain: 判定表・状態遷移]
          U --> R[repository: parallel_run / execution-spec / Runner Result / 設定]
          R --> D
          R --> G[gateway: SSH / filesystem / RDB / completed 通知]
    - tier_id: "tier-rapid-crosscheck"
      layers:
        - id: "L-rapid-presentation"
          name: "プレゼンテーション層(CLI エントリ)"
          responsibility: "rapid-crosscheck-runner の公開 function(blue-completed / green-completed)の引数検証と、rapid-crosscheck-worker の起動口(poll ループ / 1 回実行)。終了コードの決定"
          allowed_dependencies:
            - "L-rapid-usecase"
          policies:
            - id: "LP-008"
              name: "系統ごとの公開 function"
              description: "完了通知の受け口は blue-completed / green-completed の 2 つに分け、run_id・job_id・終了コード・成果物ディレクトリ(artifact_uri)を受け取る"
              reason: "条件「完了通知の系統独立」への対応"
              source_model: "条件: 完了通知の系統独立, 情報: 完了通知"
              confidence: "high"
          rules: []
        - id: "L-rapid-usecase"
          name: "ユースケース層"
          responsibility: "完了通知の登録 → 中止済み run 判定(並行稼働実行と完了通知の対象 slot の slot 実行の状態)→ 両系成功判定 → 比較依頼の一意作成(dispatcher。中止済み run では依頼を作成せず完了事実の記録と警告ログだけ)、poll → claim → RUNNING(条件付き UPDATE。0 件なら比較を開始せず終了)→ 比較実行 → 結果保存 → comparison_result 登録(比較ツールの終了コードを得たときだけ)→ リラン由来 parallel_run の COMPLETED 更新(worker)のフロー制御"
          allowed_dependencies:
            - "L-rapid-domain"
            - "L-rapid-repository"
          policies:
            - id: "LP-009"
              name: "依頼作成と claim の原子性"
              description: "両系成功 → 比較依頼作成、REQUESTED → CLAIMED の遷移は 1 トランザクション(条件付き UPDATE / INSERT)で行い、重複作成と二重 claim を防ぐ"
              reason: "条件「比較依頼の一意性」「claim 排他」への対応"
              source_model: "条件: 比較依頼の一意性, claim 排他, 状態: 速報実行の完了状況"
              confidence: "high"
            - id: "LP-023"
              name: "中止済み run では依頼を作成しない"
              description: "dispatcher の usecase は完了通知を登録した後、同じトランザクション内で並行稼働実行(parallel_run.status)と完了通知の対象 slot の slot 実行(slot_executions.status。ファイル正本 aborted.txt のミラー)の状態を読み、いずれかが ABORTED なら中止済み run として両系成功でも速報比較依頼を作成せず、rapid_run の完了事実(blue_status / green_status / 成果物 URI)だけを保存して実行ログに warning を残し、正常終了する。並行稼働実行は foreground 中継完了で COMPLETED になるため、foreground 完了後の background 中止は slot 実行 ABORTED の側で除外される。slot runner に中止判定を持たせない。速報有効時だけの規則で、off では完了通知自体が存在しない"
              reason: "条件「中止済み run の比較依頼作成除外」(判定キー: 並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)への対応。判断主体を速報クロスチェック runner に置き、方針資料の責務分担(blue / green runner は比較依頼を判断しない)を守るため"
              source_model: "条件: 中止済み run の比較依頼作成除外, 両系成功判定, 状態: 並行稼働実行, slot 実行, 速報実行の完了状況, 情報: 速報実行(rapid_run), 完了通知, slot 実行, 実行ログ"
              confidence: "high"
            - id: "LP-024"
              name: "claim 後の比較開始は条件付き UPDATE で判定する"
              description: "worker の usecase は claim した依頼を比較開始前に status = CLAIMED(かつ自 worker_id)を条件とする条件付き UPDATE で RUNNING にし、更新件数が 0 件(abort-rapid-crosscheck で ABORTED 済み)なら比較ツールを起動せず comparison_result も登録せずに正常終了し、その旨を実行ログに残す。RUNNING にできたときだけ比較を実行する"
              reason: "条件「依頼中止可否判定」(CLAIMED の速報比較依頼を中止する際の競合規則)と状態モデル「クロスチェック依頼」(CLAIMED → RUNNING の条件付き UPDATE、CLAIMED → ABORTED)への対応。運用者が worker 停止を確認して中止した依頼を、停止漏れの worker が比較してしまう競合を DB の条件付き UPDATE で閉じるため"
              source_model: "条件: 依頼中止可否判定, 依頼状態遷移規則, claim 排他, 状態: クロスチェック依頼, 情報: 速報比較依頼(rapid_crosscheck_request), 実行ログ"
              confidence: "high"
          rules: []
        - id: "L-rapid-domain"
          name: "ドメイン層"
          responsibility: "速報実行の完了状況(両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み)の遷移、中止済み run の依頼作成除外判定(並行稼働実行の状態 × 対象 slot の slot 実行の状態 × 両系成功判定)、クロスチェック依頼のライフサイクル(REQUESTED / CLAIMED / RUNNING → ABORTED と、CLAIMED → RUNNING の条件付き遷移を含む)、lease 失効判定、比較ツール終了コード → 依頼状態の対応表"
          allowed_dependencies: []
          policies:
            - id: "LP-010"
              name: "両系成功判定表"
              description: "blue の結果 × green の結果の表で成功 × 成功のみ両系成功とする。exitcode 0 = SUCCEEDED / 3・6・その他非 0 = FAILED の対応表もドメインに置く。依頼作成可否は中止済み判定(並行稼働実行 ABORTED / 対象 slot の slot 実行 ABORTED / いずれでもない)× 両系成功判定の結果の表で決め、中止済みの行は両系成功でも作成不可とする"
              reason: "条件「両系成功判定」「中止済み run の比較依頼作成除外」(判定表の縦軸: 並行稼働実行 ABORTED / 対象 slot の slot 実行 ABORTED / いずれでもない)「比較ツール終了コードの対応」「依頼状態遷移規則」「lease 失効判定」への対応"
              source_model: "条件: 両系成功判定, 中止済み run の比較依頼作成除外, 比較ツール終了コードの対応, 依頼状態遷移規則, lease 失効判定, 状態: 速報実行の完了状況, クロスチェック依頼, 並行稼働実行, slot 実行"
              confidence: "high"
          rules: []
        - id: "L-rapid-repository"
          name: "リポジトリ層"
          responsibility: "rapid_run / rapid_crosscheck_request / comparison_result の読み書きと parallel_run・slot 実行(slot_executions)の状態参照(管理 DB)、クロスチェックジョブマップの比較定義の読み取り(設定ファイル)、速報クロスチェック設定(env 形式 rapid-crosscheck.env: RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC)の読み取り"
          allowed_dependencies:
            - "L-rapid-domain"
            - "L-rapid-gateway"
          policies: []
          rules: []
        - id: "L-rapid-gateway"
          name: "ゲートウェイ層"
          responsibility: "RDB クライアントアダプタ(poll / claim と CLAIMED → RUNNING の条件付き UPDATE。更新件数を usecase に返す。接続先は速報クロスチェック設定の接続参照名で解決)、比較ツール起動アダプタ(比較定義のコマンドを実行し stdout / stderr / exitcode を取得)"
          allowed_dependencies: []
          policies:
            - id: "LP-011"
              name: "比較ツール呼び出しの分離"
              description: "比較ツールの起動コマンド・オプションは job_id ごとの比較定義から受け取り、gateway は実行と結果取得だけを行う。ツール固有の終了コード解釈は domain の対応表に委ねる"
              reason: "条件「比較定義の選択」への対応。比較ツールを差し替え可能にするため"
              source_model: "条件: 比較定義の選択, 外部システム: 比較ツール, 情報: 比較定義"
              confidence: "high"
          rules: []
      cross_layer_policies:
        - id: "CLP-003"
          name: "IF なし(直接依存)"
          description: "tier-facade と同じく直接依存とし、gateway アダプタの差し替えで製品差異を吸収する"
          reason: "一般的なベストプラクティスとして適用"
          source_model: "なし"
          confidence: "default"
        - id: "CLP-004"
          name: "実行ログの出力方針"
          description: "tier-facade の CLP-002 と同一(日時はホストのローカルタイムゾーン、タイムゾーン指示子なし)。worker は claim した依頼の run_id と worker_id をログに含め、RUNNING への条件付き UPDATE が 0 件で比較を開始しなかったこともログに残す。dispatcher は中止済み run(並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)で依頼を作成しなかったことを warning で残す"
          reason: "NFR C.6.1.1・C.3.1.1 への対応"
          source_model: "情報: 実行ログ, NFR C.6.1.1, NFR C.3.1.1"
          confidence: "medium"
      cross_layer_rules:
        - id: "CLR-002"
          name: "エラーハンドリングと終了コード"
          description: "tier-facade の CLR-001 と同一。比較ツールの非 0 は例外ではなく結果として扱い FAILED を保存する"
          reason: "レイヤー責務の分離"
          source_model: "条件: 比較ツール終了コードの対応"
          confidence: "default"
      diagram_mermaid: |
        graph TD
          P[presentation: blue-completed / green-completed / worker 起動口] --> U[usecase: dispatcher / worker フロー]
          U --> D[domain: 両系成功判定・依頼ライフサイクル]
          U --> R[repository: rapid_run / request / comparison_result / 比較定義]
          R --> D
          R --> G[gateway: RDB / 比較ツール]
    - tier_id: "tier-final-crosscheck"
      layers:
        - id: "L-final-presentation"
          name: "プレゼンテーション層(CLI エントリ)"
          responsibility: "final-crosscheck-runner の起動口(business_date・対象カタログ版の引数検証)と worker の起動口。保存済み stdout / stderr / exitcode の無加工中継と終了コードの決定"
          allowed_dependencies:
            - "L-final-usecase"
          policies:
            - id: "LP-012"
              name: "中継制約"
              description: "presentation は依頼に保存された stdout / stderr / exitcode だけを返し、状態名・差分件数・レポート URI を出力に追加しない"
              reason: "条件「確報結果の中継制約」への対応"
              source_model: "条件: 確報結果の中継制約, 情報: ジョブスケジューラ応答"
              confidence: "high"
          rules: []
        - id: "L-final-usecase"
          name: "ユースケース層"
          responsibility: "依頼登録 → 終端状態までの同期 polling → 結果中継(runner)、poll → claim → RUNNING → 全量比較 → 結果保存(worker)のフロー制御"
          allowed_dependencies:
            - "L-final-domain"
            - "L-final-repository"
          policies:
            - id: "LP-013"
              name: "同期 polling の間隔と上限"
              description: "runner は終端状態まで一定間隔で polling し、夜間ウィンドウ(8 時間)を超える場合の扱いは設定で指定できるようにする。polling 中は状態を変更しない"
              reason: "条件「確報依頼の登録条件」と NFR B.2.2.1 への対応"
              source_model: "条件: 確報依頼の登録条件, NFR B.2.2.1"
              confidence: "medium"
          rules: []
        - id: "L-final-domain"
          name: "ドメイン層"
          responsibility: "クロスチェック依頼のライフサイクル(速報と共有する規則)、lease 失効判定、比較ツール終了コード → 依頼状態の対応表、終端状態の判定"
          allowed_dependencies: []
          policies:
            - id: "LP-014"
              name: "依頼ライフサイクル規則の共有"
              description: "REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED の遷移規則と終了コード対応表は速報側と同一の規則として実装し、レコードは final_crosscheck_request に分離する"
              reason: "条件「依頼状態遷移規則」「速報と確報のモデル分離」への対応"
              source_model: "条件: 依頼状態遷移規則, 速報と確報のモデル分離, 状態: クロスチェック依頼"
              confidence: "high"
          rules: []
        - id: "L-final-repository"
          name: "リポジトリ層"
          responsibility: "final_crosscheck_request と対象カタログの読み書き(管理 DB)。速報側のテーブルには触れない"
          allowed_dependencies:
            - "L-final-domain"
            - "L-final-gateway"
          policies: []
          rules: []
        - id: "L-final-gateway"
          name: "ゲートウェイ層"
          responsibility: "RDB クライアントアダプタ(DB セグメントからの poll / claim)、比較ツール起動アダプタ(対象カタログに基づく全テーブル・全ファイル比較)"
          allowed_dependencies: []
          policies:
            - id: "LP-015"
              name: "対象カタログに基づく全量比較の起動"
              description: "gateway は対象カタログ(target_type / target_identifier / 比較条件 / business_date の扱い)を比較ツールの入力に変換して起動し、stdout / stderr / exitcode を取得する"
              reason: "条件「適用側で定義する事項」への対応"
              source_model: "条件: 適用側で定義する事項, 情報: 対象カタログ, 外部システム: 比較ツール"
              confidence: "high"
          rules: []
      cross_layer_policies:
        - id: "CLP-005"
          name: "IF なし(直接依存)"
          description: "tier-facade と同じく直接依存とする"
          reason: "一般的なベストプラクティスとして適用"
          source_model: "なし"
          confidence: "default"
        - id: "CLP-006"
          name: "実行ログの出力方針"
          description: "tier-facade の CLP-002 と同一。final_crosscheck_id と business_date をログに含める"
          reason: "NFR C.6.1.1・C.3.1.1 への対応"
          source_model: "情報: 実行ログ, NFR C.6.1.1, NFR C.3.1.1"
          confidence: "medium"
      cross_layer_rules:
        - id: "CLR-003"
          name: "エラーハンドリングと終了コード"
          description: "tier-facade の CLR-001 と同一。依頼登録失敗・polling 中の DB 障害は非 0 で終了し原因を stderr に出す"
          reason: "レイヤー責務の分離"
          source_model: "なし"
          confidence: "default"
      diagram_mermaid: |
        graph TD
          P[presentation: final runner / worker 起動口] --> U[usecase: 登録・polling・中継 / 比較実行]
          U --> D[domain: 依頼ライフサイクル・終了コード対応]
          U --> R[repository: final_crosscheck_request / 対象カタログ]
          R --> D
          R --> G[gateway: RDB / 比較ツール]
    - tier_id: "tier-ops"
      layers:
        - id: "L-ops-presentation"
          name: "プレゼンテーション層(CLI エントリ)"
          responsibility: "hang-detector / background-rerun(--source-run-id, --role) / abort-*(--run-id)の引数検証、現在状態の表示、停止確認の対話プロンプト、終了コードの決定"
          allowed_dependencies:
            - "L-ops-usecase"
          policies:
            - id: "LP-016"
              name: "停止確認の対話"
              description: "abort-* は現在状態を表示後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と確認し、yes 以外は状態を変更せず終了する"
              reason: "条件「停止確認応答」への対応"
              source_model: "条件: 停止確認応答, 情報: 中止指示, バリエーション: 停止確認応答"
              confidence: "high"
          rules: []
        - id: "L-ops-usecase"
          name: "ユースケース層"
          responsibility: "監視走査 → 判定 → 監視記録保存 → 通知(hang-detector)、事前検証 → execution-spec 復元 → 新 run 作成 → background slot / 比較依頼の起動(background-rerun)、可否判定 → 停止確認 → 状態更新(abort-*。abort-blue / abort-green は slot・並行稼働実行に加えて対象 run の未着手の速報比較依頼の ABORTED 化(競合窓の保険)を含む。abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING の速報比較依頼、abort-final-crosscheck は RUNNING の確報比較依頼を中止する)のフロー制御"
          allowed_dependencies:
            - "L-ops-domain"
            - "L-ops-repository"
          policies:
            - id: "LP-017"
              name: "監視は通知のみ"
              description: "hang-detector の usecase は状態更新・プロセス停止・依頼作成を呼ばない。監視記録の保存とメール送信だけを行う"
              reason: "条件「監視は通知のみ」「警告傾向の記録」への対応"
              source_model: "条件: 監視は通知のみ, 警告傾向の記録, 状態: 監視状態"
              confidence: "high"
            - id: "LP-018"
              name: "リランの復元元の固定"
              description: "background-rerun の usecase は最新ジョブマップの repository を呼ばず、元 run の execution-spec.json からのみ実行設定を復元し、新 run_id の parallel_run に parent_run_id を設定する"
              reason: "条件「リランの実行設定復元」「リラン系譜の追跡」「リラン事前検証」への対応"
              source_model: "条件: リランの実行設定復元, リラン系譜の追跡, リラン事前検証, 情報: リラン指示"
              confidence: "high"
          rules: []
        - id: "L-ops-domain"
          name: "ドメイン層"
          responsibility: "slot 実行の状態導出(exitcode.txt / aborted.txt の有無・値)、ハング検知判定表(導出状態 × 経過時間と上限)、速報比較依頼の異常判定表、通知レベル対応表、監視状態の遷移(6 値。通知後・中止後の終端を含む)、リラン事前検証表(role × 元 mode × 導出状態)、中止可否判定表(slot は mode × 導出状態、比較依頼はクロスチェック種別 × 依頼状態(速報は REQUESTED / CLAIMED / RUNNING、確報は RUNNING のみ)。abort-blue / abort-green が併せて中止する速報比較依頼の状態条件(REQUESTED で未着手のみ)を含む)、復旧手段の選択表"
          allowed_dependencies: []
          policies:
            - id: "LP-019"
              name: "判定表をドメインに集約"
              description: "slot 実行の状態導出・ハング検知判定・対象除外・異常判定・通知レベル・監視状態の遷移(ハング疑い通知済み → 正常終了 / 実行エラー通知済み / 比較異常通知済み、監視中・ハング疑い通知済み → 正常終了(中止済み))・リラン事前検証・中止可否(slot 実行モード × 導出状態、およびクロスチェック種別 × 依頼状態。速報比較依頼は REQUESTED / CLAIMED / RUNNING、確報比較依頼は RUNNING のみ中止可)・復旧手段の各判定表を純粋関数として実装し、テスト可能にする"
              reason: "条件「slot 実行の状態導出規則」「ハング検知判定」「ハング検知対象の除外」「速報比較依頼の異常判定」「通知レベルの判定」「リラン事前検証」「slot 中止可否判定」「依頼中止可否判定」(縦軸クロスチェック種別 × 横軸依頼状態の判定表)「復旧手段の選択」と状態モデル「監視状態」「クロスチェック依頼」(REQUESTED / CLAIMED / RUNNING → ABORTED)、バリエーション「中止対象種別」への対応"
              source_model: "条件: slot 実行の状態導出規則, ハング検知判定, ハング検知対象の除外, 速報比較依頼の異常判定, 通知レベルの判定, リラン事前検証, slot 中止可否判定, 依頼中止可否判定, 復旧手段の選択, 状態: 監視状態, クロスチェック依頼, バリエーション: ハング検知判定結果, 監視状態, 中止対象種別, クロスチェック依頼状態"
              confidence: "high"
          rules: []
        - id: "L-ops-repository"
          name: "リポジトリ層"
          responsibility: "監視記録(管理 DB)、slot 実行・parallel_run・比較依頼の状態(管理 DB)、Runner Result / execution-spec.json / aborted.txt(成果物ディレクトリ)、ハング検知上限設定(execution-spec 経由)、ハング検知定期ジョブ設定(env 形式の設定ファイル)の読み書き"
          allowed_dependencies:
            - "L-ops-domain"
            - "L-ops-gateway"
          policies:
            - id: "LP-020"
              name: "管理 DB なしでの監視・中止・リラン"
              description: "RAPID_CROSSCHECK_MODE=off のとき repository は管理 DB に接続せず、成果物ディレクトリの走査だけで監視対象を列挙し、slot 実行の状態は exitcode.txt / aborted.txt から導出する。abort-blue / abort-green の中止は aborted.txt の書き込みだけで成立し、background-rerun も成果物ファイルだけで事前検証する"
              reason: "条件「ハング検知判定」「slot 実行の状態導出規則」と方針資料「off の場合も slot 成果物だけで監視・中止・リラン」への対応"
              source_model: "条件: ハング検知判定, 速報クロスチェック有効判定, slot 実行の状態導出規則, 情報: 監視記録, ハング検知上限設定, Runner Result"
              confidence: "high"
          rules: []
        - id: "L-ops-gateway"
          name: "ゲートウェイ層"
          responsibility: "メール送信アダプタ(ハング検知定期ジョブ設定の送信コマンド・宛先・件名プレフィックスを使う OS 標準コマンド呼び出し。warning / error)、RDB クライアントアダプタ(条件付き UPDATE による ABORTED 遷移)、ファイルシステム走査・書き込みアダプタ(aborted.txt の一時ファイル → リネーム出力を含む)、slot runner / 速報クロスチェック runner 起動アダプタ(リラン)"
          allowed_dependencies: []
          policies:
            - id: "LP-021"
              name: "条件付き状態更新と aborted.txt の原子的書き込み"
              description: "slot の中止は aborted.txt を一時ファイルへ書いて確定名へリネームすることを正本とし、既に exitcode.txt または aborted.txt があれば書かずにエラーを返す。管理 DB の ABORTED への更新(off 以外)は WHERE 句で現在状態(slot 実行は RUNNING かつ background、並行稼働実行は STARTED または RUNNING)を条件にし、競合時は更新件数 0 をエラーとして返す。abort-blue / abort-green が併せて行う速報比較依頼の ABORTED 更新は WHERE status = REQUESTED(worker_id 未設定)を条件にし、該当なし(依頼が無い、または既に CLAIMED / RUNNING 以降)は更新件数 0 を正常として扱い、その依頼には触れない(競合窓の保険であり、dispatcher 側の中止済み run 判定と併用する)。abort-rapid-crosscheck の ABORTED 更新は WHERE status IN ('REQUESTED', 'CLAIMED', 'RUNNING') を条件にし、更新件数 0(終端済み)はエラーとして返す。abort-final-crosscheck は WHERE status = RUNNING を条件にする"
              reason: "条件「slot 中止可否判定」「依頼中止可否判定」(CLAIMED 中止時の競合規則: status IN 条件の条件付き UPDATE)「slot 実行の状態導出規則」「成果物公開判定」と状態モデル「クロスチェック依頼」(REQUESTED / CLAIMED / RUNNING → ABORTED)への対応。二重実行と worker の claim との競合を DB のトランザクションで防ぐため"
              source_model: "条件: slot 中止可否判定, 依頼中止可否判定, slot 実行の状態導出規則, 成果物公開判定, claim 排他, 状態: クロスチェック依頼, システム概要: ジョブキュー兼管理 DB(内部データストア), 外部システム: メール通知, 情報: ハング検知定期ジョブ設定, 速報比較依頼(rapid_crosscheck_request)"
              confidence: "high"
          rules: []
      cross_layer_policies:
        - id: "CLP-007"
          name: "IF なし(直接依存)"
          description: "tier-facade と同じく直接依存とする"
          reason: "一般的なベストプラクティスとして適用"
          source_model: "なし"
          confidence: "default"
        - id: "CLP-008"
          name: "運用操作の記録"
          description: "中止・リランの運用操作は指示者(実行ユーザー)・応答・対象 run_id・role を実行ログに残し、監視記録には monitor_status(6 値)/ hang_suspected_at / alerted_at / 警告時経過時間を残す。hang_detect_limit_minutes の調整記録は監視記録ではなく適用構成文書に残す"
          reason: "条件「警告傾向の記録」と NFR E.7.1.1(監査ログ)・C.3.1.1(自動記録)への対応"
          source_model: "条件: 警告傾向の記録, 情報: 実行ログ, 監視記録, NFR E.7.1.1, NFR C.3.1.1, NFR C.6.1.1"
          confidence: "high"
      cross_layer_rules:
        - id: "CLR-004"
          name: "エラーハンドリングと終了コード"
          description: "tier-facade の CLR-001 と同一。事前検証エラー・中止不可は状態を変更せず非 0 で終了し、原因を stderr に出す"
          reason: "レイヤー責務の分離"
          source_model: "なし"
          confidence: "default"
      diagram_mermaid: |
        graph TD
          P[presentation: hang-detector / background-rerun / abort-* CLI] --> U[usecase: 監視・リラン・中止フロー]
          U --> D[domain: 判定表・監視状態遷移]
          U --> R[repository: 監視記録 / 状態 / 成果物 / execution-spec]
          R --> D
          R --> G[gateway: メール / RDB / filesystem / runner 起動]
```

## data_architecture.entities

```yaml
  entities:
    - id: "E-001"
      name: "feature flag 設定"
      source_info: "情報: feature flag 設定"
      model_type: "resource_mutable"
      attributes:
        - name: "blue_mode"
          type: "string"
          description: "BLUE_MODE: blue slot 実行モード(foreground / background / off)"
          nullable: false
          primary_key: false
        - name: "green_mode"
          type: "string"
          description: "GREEN_MODE: green slot 実行モード(foreground / background / off)"
          nullable: false
          primary_key: false
        - name: "rapid_crosscheck_mode"
          type: "string"
          description: "RAPID_CROSSCHECK_MODE(foreground / background / off)。foreground / background は runner が完了通知を送信し速報管理 DB へ書き込む。off は完了通知を送信せず速報管理 DB へ接続も書込みもしない"
          nullable: false
          primary_key: false
        - name: "blue_impl"
          type: "string"
          description: "BLUE_IMPL: blue の実装版(execution-spec.json の実装版の出所)"
          nullable: false
          primary_key: false
        - name: "green_impl"
          type: "string"
          description: "GREEN_IMPL: green の実装版(execution-spec.json の実装版の出所)"
          nullable: false
          primary_key: false
        - name: "blue_runner"
          type: "string"
          description: "BLUE_RUNNER: blue runner 実体スクリプトパス"
          nullable: false
          primary_key: false
        - name: "green_runner"
          type: "string"
          description: "GREEN_RUNNER: green runner 実体スクリプトパス"
          nullable: false
          primary_key: false
        - name: "rapid_crosscheck_runner"
          type: "string"
          description: "RAPID_CROSSCHECK_RUNNER: slot runner が完了通知(blue-completed / green-completed)を送る速報クロスチェック runner の実体パス"
          nullable: false
          primary_key: false
        - name: "rapid_crosscheck_worker"
          type: "string"
          description: "RAPID_CROSSCHECK_WORKER: 速報クロスチェック worker の実体パス"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-002"
          type: "1:N"
          description: "feature flag が slot ごとの runner 割当(BLUE_RUNNER / GREEN_RUNNER)を所有する"
        - target_entity: "E-010"
          type: "1:N"
          description: "BLUE_IMPL / GREEN_IMPL が execution-spec の実装版として確定保存される"
    - id: "E-002"
      name: "slot runner 割当"
      source_info: "情報: slot runner 割当"
      model_type: "resource_scd2"
      attributes:
        - name: "slot"
          type: "string"
          description: "slot(blue / green)"
          nullable: false
          primary_key: true
        - name: "runner_script_path"
          type: "string"
          description: "runner 実体スクリプトパス"
          nullable: false
          primary_key: false
        - name: "job_map_location"
          type: "string"
          description: "対応するジョブマップの所在"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-003"
          type: "1:1"
          description: "slot の runner が参照するジョブマップ"
    - id: "E-003"
      name: "ジョブマップ"
      source_info: "情報: ジョブマップ"
      model_type: "resource_scd2"
      attributes:
        - name: "slot"
          type: "string"
          description: "slot(blue / green)"
          nullable: false
          primary_key: true
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: true
        - name: "host"
          type: "string"
          description: "実行先ホスト(CSV 列 host。ローカル実行の slot では省略可)"
          nullable: true
          primary_key: false
        - name: "user"
          type: "string"
          description: "実行ユーザー(CSV 列 user。ローカル実行の slot では省略可)"
          nullable: true
          primary_key: false
        - name: "work_dir"
          type: "string"
          description: "作業ディレクトリ(CSV 列 work_dir)"
          nullable: false
          primary_key: false
        - name: "script"
          type: "string"
          description: "実装スクリプトパス(CSV 列 script)"
          nullable: false
          primary_key: false
        - name: "fixed_params"
          type: "text"
          description: "固定引数(CSV 列 fixed_params。JSON 配列文字列を格納するセルで、二重引用符で囲みセル内の二重引用符は二重化する。空は [])"
          nullable: false
          primary_key: false
        - name: "hang_detect_limit_minutes"
          type: "integer"
          description: "ハング検知上限(CSV 列 hang_detect_limit_minutes。E-004 として扱う)"
          nullable: false
          primary_key: false
        - name: "credential_ref"
          type: "string"
          description: "認証情報参照名(末尾の任意列。値は保持しない)"
          nullable: true
          primary_key: false
        - name: "map_version"
          type: "string"
          description: "マップ版(末尾の任意列。execution-spec のマップ版の出所)"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-004"
          type: "1:N"
          description: "role ごとの hang_detect_limit_minutes を所有する"
        - target_entity: "E-010"
          type: "1:N"
          description: "run 開始時に実行設定として確定保存される"
    - id: "E-004"
      name: "ハング検知上限設定"
      source_info: "情報: ハング検知上限設定"
      model_type: "resource_scd2"
      attributes:
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: true
        - name: "role"
          type: "string"
          description: "role(blue / green / rapid-crosscheck)"
          nullable: false
          primary_key: true
        - name: "hang_detect_limit_minutes"
          type: "integer"
          description: "ハング疑いの判定上限(導入時 60。foreground role は 0 で対象外)。調整日時・調整根拠はここに持たず適用構成文書に記録する"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-021"
          type: "1:N"
          description: "監視記録の警告時経過時間を調整根拠にする"
        - target_entity: "E-005"
          type: "N:1"
          description: "調整記録(調整日時・調整根拠)は適用構成文書が保持する"
    - id: "E-005"
      name: "適用構成文書"
      source_info: "情報: 適用構成文書"
      model_type: "resource_mutable"
      attributes:
        - name: "project_id"
          type: "string"
          description: "案件識別"
          nullable: false
          primary_key: true
        - name: "document_version"
          type: "string"
          description: "文書版"
          nullable: false
          primary_key: true
        - name: "external_if_policy"
          type: "text"
          description: "外部 IF の送受信方針"
          nullable: true
          primary_key: false
        - name: "network_constraints"
          type: "text"
          description: "ネットワーク制約"
          nullable: true
          primary_key: false
        - name: "host_placement"
          type: "text"
          description: "ホスト配置・実行ユーザー方針・DB セグメント構成"
          nullable: true
          primary_key: false
        - name: "runner_location"
          type: "text"
          description: "runner 実体の所在"
          nullable: true
          primary_key: false
        - name: "hang_limit_adjustment_records"
          type: "text"
          description: "運用者の hang_detect_limit_minutes 調整記録(job_id / role ごとの調整日時と、調整根拠となる警告時経過時間)"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-003"
          type: "1:N"
          description: "案件固有事項がジョブマップ定義の根拠となる"
        - target_entity: "E-004"
          type: "1:N"
          description: "ハング検知上限の調整記録を保持する"
    - id: "E-006"
      name: "比較定義"
      source_info: "情報: 比較定義"
      model_type: "resource_scd2"
      attributes:
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: true
        - name: "definition_version"
          type: "string"
          description: "定義版"
          nullable: false
          primary_key: true
        - name: "comparison_type"
          type: "string"
          description: "比較種別"
          nullable: false
          primary_key: false
        - name: "targets"
          type: "text"
          description: "比較対象(テーブル・ファイル)"
          nullable: false
          primary_key: false
        - name: "tool_command"
          type: "string"
          description: "比較ツール起動コマンド"
          nullable: false
          primary_key: false
        - name: "tool_options"
          type: "text"
          description: "比較オプション"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-007"
          type: "N:1"
          description: "クロスチェックジョブマップに属する"
    - id: "E-007"
      name: "クロスチェックジョブマップ"
      source_info: "情報: クロスチェックジョブマップ"
      model_type: "resource_scd2"
      attributes:
        - name: "map_version"
          type: "string"
          description: "マップ版"
          nullable: false
          primary_key: true
        - name: "target_list"
          type: "text"
          description: "比較対象一覧"
          nullable: false
          primary_key: false
        - name: "catalog_ref"
          type: "string"
          description: "対象カタログ参照(版)"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-006"
          type: "1:N"
          description: "job_id ごとの比較定義を保持する"
        - target_entity: "E-008"
          type: "1:1"
          description: "確報用の対象カタログを参照する"
    - id: "E-008"
      name: "対象カタログ"
      source_info: "情報: 対象カタログ"
      model_type: "resource_scd2"
      attributes:
        - name: "catalog_version"
          type: "string"
          description: "カタログ版"
          nullable: false
          primary_key: true
        - name: "target_type"
          type: "string"
          description: "target_type(テーブル / ファイル)"
          nullable: false
          primary_key: true
        - name: "target_identifier"
          type: "string"
          description: "target_identifier"
          nullable: false
          primary_key: true
        - name: "comparison_condition"
          type: "text"
          description: "比較条件"
          nullable: true
          primary_key: false
        - name: "business_date_handling"
          type: "string"
          description: "business_date の扱い"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-019"
          type: "1:N"
          description: "確報比較依頼がカタログ版を紐付ける"
    - id: "E-009"
      name: "ジョブ起動要求"
      source_info: "情報: ジョブ起動要求"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "起動により facade が発行した run_id(モードによらず発行。形式は E-013 と同じ)"
          nullable: false
          primary_key: true
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "params"
          type: "text"
          description: "PARAM...(追加引数。順序保持)"
          nullable: false
          primary_key: false
        - name: "source_job_definition"
          type: "string"
          description: "起動元ジョブ定義"
          nullable: true
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "起動日時"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "1:1"
          description: "並行稼働実行を開始する"
        - target_entity: "E-001"
          type: "N:1"
          description: "起動時に読み込む feature flag"
    - id: "E-010"
      name: "実行設定(execution-spec)"
      source_info: "情報: 実行設定(execution-spec)"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: true
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "slot"
          type: "string"
          description: "slot"
          nullable: false
          primary_key: false
        - name: "role"
          type: "string"
          description: "role"
          nullable: false
          primary_key: false
        - name: "host"
          type: "string"
          description: "ホスト(ジョブマップ列 host。ローカル実行では null)"
          nullable: true
          primary_key: false
        - name: "user"
          type: "string"
          description: "実行ユーザー(ジョブマップ列 user。ローカル実行では null)"
          nullable: true
          primary_key: false
        - name: "work_dir"
          type: "string"
          description: "作業ディレクトリ(ジョブマップ列 work_dir)"
          nullable: false
          primary_key: false
        - name: "script"
          type: "string"
          description: "スクリプトパス(ジョブマップ列 script)"
          nullable: false
          primary_key: false
        - name: "fixed_params"
          type: "text"
          description: "固定引数(ジョブマップ列 fixed_params の JSON 配列)"
          nullable: false
          primary_key: false
        - name: "params"
          type: "text"
          description: "追加引数(PARAM)"
          nullable: false
          primary_key: false
        - name: "map_version"
          type: "string"
          description: "マップ版(ジョブマップ側の任意列 map_version。無ければ null)"
          nullable: true
          primary_key: false
        - name: "impl_version"
          type: "string"
          description: "実装版(feature flag の BLUE_IMPL / GREEN_IMPL)"
          nullable: false
          primary_key: false
        - name: "hang_detect_limits"
          type: "text"
          description: "role ごとの hang_detect_limit_minutes"
          nullable: false
          primary_key: false
        - name: "credential_ref"
          type: "string"
          description: "認証情報参照名(値は保存しない)"
          nullable: true
          primary_key: false
        - name: "spec_uri"
          type: "string"
          description: "保存先 URI(facade/<run_id>/execution-spec.json)"
          nullable: false
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "確定保存日時"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "1:1"
          description: "parallel_run.execution_spec_uri が参照する"
        - target_entity: "E-003"
          type: "N:1"
          description: "解決元のジョブマップ(任意列 map_version 付き)"
        - target_entity: "E-001"
          type: "N:1"
          description: "実装版の出所(BLUE_IMPL / GREEN_IMPL)"
    - id: "E-011"
      name: "Runner Result"
      source_info: "情報: Runner Result"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: true
        - name: "role"
          type: "string"
          description: "成果物ディレクトリ区分(blue / green / rapid-crosscheck / final-crosscheck)"
          nullable: false
          primary_key: true
        - name: "artifact_dir"
          type: "string"
          description: "成果物ディレクトリ"
          nullable: false
          primary_key: false
        - name: "started_at"
          type: "datetime"
          description: "started-at.txt(開始時刻)"
          nullable: false
          primary_key: false
        - name: "stdout_path"
          type: "string"
          description: "stdout.log のパス"
          nullable: false
          primary_key: false
        - name: "stderr_path"
          type: "string"
          description: "stderr.log のパス"
          nullable: false
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "exitcode.txt(数値 1 行。未終了・中止済みでは無い)"
          nullable: true
          primary_key: false
        - name: "aborted_at"
          type: "datetime"
          description: "aborted.txt(中止日時 1 行。abort-blue / abort-green による明示中止時のみ生成)"
          nullable: true
          primary_key: false
        - name: "finalized"
          type: "boolean"
          description: "確定リネーム完了フラグ"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-014"
          type: "1:1"
          description: "slot 実行の終了結果。slot 実行の状態は exitcode.txt / aborted.txt の有無と値から導出する"
    - id: "E-012"
      name: "ジョブスケジューラ応答"
      source_info: "情報: ジョブスケジューラ応答"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id(または final_crosscheck_id)"
          nullable: false
          primary_key: true
        - name: "stdout_source"
          type: "string"
          description: "標準出力の中継元(foreground の stdout.log / 依頼の stdout)"
          nullable: false
          primary_key: false
        - name: "stderr_source"
          type: "string"
          description: "標準エラーの中継元"
          nullable: false
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "終了コード(応答日時は持たない。実行履歴はジョブスケジューラの責務)"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-011"
          type: "1:1"
          description: "foreground の Runner Result を無加工で中継する"
        - target_entity: "E-019"
          type: "N:1"
          description: "確報では依頼に保存された結果を中継する"
    - id: "E-013"
      name: "並行稼働実行(parallel_run)"
      source_info: "情報: 並行稼働実行(parallel_run)"
      model_type: "event_snapshot"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id({ローカルタイムゾーンの yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}。例 20260830T203000-JOB001-3f9a1c2e。タイムゾーン指示子なし。成果物ディレクトリ名と同じ値)"
          nullable: false
          primary_key: true
        - name: "parent_run_id"
          type: "string"
          description: "リラン元 run_id(数珠つなぎ)"
          nullable: true
          primary_key: false
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "parameters"
          type: "text"
          description: "parameters(JSON)"
          nullable: false
          primary_key: false
        - name: "execution_spec_uri"
          type: "string"
          description: "execution-spec.json の URI"
          nullable: false
          primary_key: false
        - name: "status"
          type: "string"
          description: "STARTED / RUNNING / COMPLETED / ABORTED(STARTED → RUNNING → COMPLETED、STARTED / RUNNING → ABORTED。COMPLETED は foreground 中継完了、background slot リラン由来 run では runner の終端時、速報比較依頼だけのリラン由来 run では依頼終端時に worker が更新する)"
          nullable: false
          primary_key: false
        - name: "requested_at"
          type: "datetime"
          description: "requested_at"
          nullable: false
          primary_key: false
        - name: "completed_at"
          type: "datetime"
          description: "completed_at"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-014"
          type: "1:N"
          description: "run に属する blue / green の slot 実行"
        - target_entity: "E-016"
          type: "1:1"
          description: "速報実行(rapid_run)と相関する"
        - target_entity: "E-013"
          type: "N:1"
          description: "parent_run_id でリラン元を追跡する"
    - id: "E-014"
      name: "slot 実行"
      source_info: "情報: slot 実行"
      model_type: "event_snapshot"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: true
        - name: "slot"
          type: "string"
          description: "slot(blue / green)"
          nullable: false
          primary_key: true
        - name: "mode"
          type: "string"
          description: "mode(foreground / background / off)"
          nullable: false
          primary_key: false
        - name: "pid"
          type: "integer"
          description: "PID"
          nullable: true
          primary_key: false
        - name: "artifact_dir"
          type: "string"
          description: "成果物ディレクトリ"
          nullable: false
          primary_key: false
        - name: "status"
          type: "string"
          description: "RUNNING / SUCCEEDED / FAILED / ABORTED(ファイル正本から導出: exitcode.txt があれば SUCCEEDED(0)/ FAILED(非 0)、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING。速報有効時は管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した場合、管理 DB は ABORTED のまま残し、ファイル正本の導出値(exitcode.txt 優先)へ再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料として使う)"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "N:1"
          description: "並行稼働実行に属する"
        - target_entity: "E-011"
          type: "1:1"
          description: "Runner Result を出力する"
        - target_entity: "E-015"
          type: "1:1"
          description: "完了時に完了通知を送る(速報有効時)"
    - id: "E-015"
      name: "完了通知"
      source_info: "情報: 完了通知"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: true
        - name: "slot"
          type: "string"
          description: "slot(blue / green)"
          nullable: false
          primary_key: true
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "notification_type"
          type: "string"
          description: "通知種別(blue-completed / green-completed)"
          nullable: false
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "終了コード"
          nullable: false
          primary_key: false
        - name: "artifact_uri"
          type: "string"
          description: "成果物ディレクトリまたは artifact_uri"
          nullable: false
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "完了日時(ホストのローカルタイムゾーン、タイムゾーン指示子なし)"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-016"
          type: "N:1"
          description: "速報実行に集約される。slot runner は自 slot の中止状態を判断せず、中止後に実装が走り切った場合も通常どおり送る"
        - target_entity: "E-027"
          type: "N:1"
          description: "速報有効時の管理 DB 接続参照名を速報クロスチェック設定から得る"
    - id: "E-016"
      name: "速報実行(rapid_run)"
      source_info: "情報: 速報実行(rapid_run)"
      model_type: "event_snapshot"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: true
        - name: "blue_status"
          type: "string"
          description: "blue_status"
          nullable: true
          primary_key: false
        - name: "green_status"
          type: "string"
          description: "green_status"
          nullable: true
          primary_key: false
        - name: "blue_artifact_uri"
          type: "string"
          description: "blue_artifact_uri"
          nullable: true
          primary_key: false
        - name: "green_artifact_uri"
          type: "string"
          description: "green_artifact_uri"
          nullable: true
          primary_key: false
        - name: "completion_status"
          type: "string"
          description: "完了状況(両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み)。中止済み run(並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED)では両系成功でも比較依頼作成済みへ進めず、完了事実だけを記録する"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "1:1"
          description: "並行稼働実行と相関する。parallel_run.status が ABORTED なら中止済み run として速報比較依頼を作成しない(dispatcher が判定)"
        - target_entity: "E-014"
          type: "1:N"
          description: "完了通知の対象 slot の slot 実行(slot_executions.status。aborted.txt のミラー)が ABORTED なら中止済み run として速報比較依頼を作成しない(dispatcher が判定。foreground 完了後の background 中止はこの側で除外される)"
        - target_entity: "E-017"
          type: "1:1"
          description: "両系成功時に速報比較依頼を 1 件作成する(中止済み run(並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED)を除く)"
        - target_entity: "E-025"
          type: "1:N"
          description: "中止済み run で依頼を作成しなかったことを実行ログに警告として残す"
    - id: "E-017"
      name: "速報比較依頼(rapid_crosscheck_request)"
      source_info: "情報: 速報比較依頼(rapid_crosscheck_request)"
      model_type: "event_snapshot"
      attributes:
        - name: "run_id"
          type: "string"
          description: "run_id(主キー)"
          nullable: false
          primary_key: true
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "status"
          type: "string"
          description: "REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED(REQUESTED → ABORTED は対象 run の abort-blue / abort-green による未着手依頼の中止(競合窓の保険)または abort-rapid-crosscheck、CLAIMED → ABORTED と RUNNING → ABORTED は abort-rapid-crosscheck(運用者の worker 停止確認のうえ status IN (REQUESTED, CLAIMED, RUNNING) 条件の条件付き UPDATE)。CLAIMED → RUNNING は status = CLAIMED 条件の条件付き UPDATE で、更新件数 0 なら worker は比較を開始しない。CLAIMED / RUNNING の依頼は abort-blue / abort-green では変更しない)"
          nullable: false
          primary_key: false
        - name: "worker_id"
          type: "string"
          description: "worker_id"
          nullable: true
          primary_key: false
        - name: "lease_until"
          type: "datetime"
          description: "lease_until(claim 時刻 + 速報クロスチェック設定の lease 期間 RAPID_LEASE_SEC)"
          nullable: true
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "比較ツールの exit_code"
          nullable: true
          primary_key: false
        - name: "stdout"
          type: "text"
          description: "比較ツールの stdout"
          nullable: true
          primary_key: false
        - name: "stderr"
          type: "text"
          description: "比較ツールの stderr"
          nullable: true
          primary_key: false
        - name: "error_summary"
          type: "string"
          description: "error_summary"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-016"
          type: "1:1"
          description: "速報実行から作成される"
        - target_entity: "E-018"
          type: "1:N"
          description: "比較結果を生む"
        - target_entity: "E-006"
          type: "N:1"
          description: "job_id ごとの比較定義に従う"
        - target_entity: "E-027"
          type: "N:1"
          description: "claim の lease 期間と worker の poll 間隔を速報クロスチェック設定から得る"
    - id: "E-018"
      name: "比較結果(comparison_result)"
      source_info: "情報: 比較結果(comparison_result)"
      model_type: "event"
      attributes:
        - name: "comparison_result_id"
          type: "string"
          description: "comparison_result_id"
          nullable: false
          primary_key: true
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: false
        - name: "comparison_type"
          type: "string"
          description: "comparison_type"
          nullable: false
          primary_key: false
        - name: "status"
          type: "string"
          description: "比較 OK / 比較 NG / FAILED"
          nullable: false
          primary_key: false
        - name: "difference_count"
          type: "integer"
          description: "difference_count"
          nullable: true
          primary_key: false
        - name: "report_uri"
          type: "string"
          description: "report_uri"
          nullable: true
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "compared_at"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-017"
          type: "N:1"
          description: "速報比較依頼に属する"
    - id: "E-019"
      name: "確報比較依頼(final_crosscheck_request)"
      source_info: "情報: 確報比較依頼(final_crosscheck_request)"
      model_type: "event_snapshot"
      attributes:
        - name: "final_crosscheck_id"
          type: "string"
          description: "final_crosscheck_id"
          nullable: false
          primary_key: true
        - name: "business_date"
          type: "date"
          description: "business_date"
          nullable: false
          primary_key: false
        - name: "catalog_version"
          type: "string"
          description: "対象カタログの版"
          nullable: false
          primary_key: false
        - name: "status"
          type: "string"
          description: "REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED"
          nullable: false
          primary_key: false
        - name: "worker_id"
          type: "string"
          description: "worker_id"
          nullable: true
          primary_key: false
        - name: "lease_until"
          type: "datetime"
          description: "lease_until"
          nullable: true
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "比較ツールの exit_code"
          nullable: true
          primary_key: false
        - name: "stdout"
          type: "text"
          description: "比較ツールの stdout"
          nullable: true
          primary_key: false
        - name: "stderr"
          type: "text"
          description: "比較ツールの stderr"
          nullable: true
          primary_key: false
        - name: "error_summary"
          type: "string"
          description: "error_summary"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-008"
          type: "N:1"
          description: "対象カタログの版を紐付ける"
        - target_entity: "E-020"
          type: "1:1"
          description: "比較ツール実行結果を保存する"
    - id: "E-020"
      name: "比較ツール実行結果"
      source_info: "情報: 比較ツール実行結果"
      model_type: "event"
      attributes:
        - name: "request_id"
          type: "string"
          description: "依頼 ID(run_id または final_crosscheck_id)"
          nullable: false
          primary_key: true
        - name: "crosscheck_type"
          type: "string"
          description: "比較種別(速報 / 確報)"
          nullable: false
          primary_key: true
        - name: "stdout"
          type: "text"
          description: "stdout"
          nullable: false
          primary_key: false
        - name: "stderr"
          type: "text"
          description: "stderr"
          nullable: false
          primary_key: false
        - name: "exit_code"
          type: "integer"
          description: "exitcode(0=比較 OK / 3=比較 NG / 6=実行エラー)"
          nullable: false
          primary_key: false
        - name: "started_at"
          type: "datetime"
          description: "実行開始日時"
          nullable: false
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "実行終了日時"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-017"
          type: "1:1"
          description: "速報比較依頼に保存される"
        - target_entity: "E-019"
          type: "1:1"
          description: "確報比較依頼に保存される"
    - id: "E-021"
      name: "監視記録"
      source_info: "情報: 監視記録"
      model_type: "event_snapshot"
      attributes:
        - name: "run_id"
          type: "string"
          description: "監視対象 run_id"
          nullable: false
          primary_key: true
        - name: "role"
          type: "string"
          description: "監視対象 role"
          nullable: false
          primary_key: true
        - name: "target_type"
          type: "string"
          description: "監視対象種別(background slot / 速報比較依頼)"
          nullable: false
          primary_key: false
        - name: "monitor_status"
          type: "string"
          description: "監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了(状態モデル「監視状態」の 6 値。ハング疑い通知済みからは正常終了(通知後正常終了)/ 実行エラー通知済み / 比較異常通知済みへ終端し、監視対象が ABORTED になった場合は監視中・ハング疑い通知済みから正常終了(中止済み)で終端する)"
          nullable: false
          primary_key: false
        - name: "started_at"
          type: "datetime"
          description: "開始時刻(started-at.txt)"
          nullable: false
          primary_key: false
        - name: "elapsed_minutes"
          type: "integer"
          description: "経過時間"
          nullable: false
          primary_key: false
        - name: "hang_detect_limit_minutes"
          type: "integer"
          description: "hang_detect_limit_minutes"
          nullable: false
          primary_key: false
        - name: "hang_suspected_at"
          type: "datetime"
          description: "hang_suspected_at"
          nullable: true
          primary_key: false
        - name: "alerted_at"
          type: "datetime"
          description: "alerted_at"
          nullable: true
          primary_key: false
        - name: "elapsed_at_alert_minutes"
          type: "integer"
          description: "警告時の経過時間"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-014"
          type: "N:1"
          description: "background slot 実行を監視する"
        - target_entity: "E-017"
          type: "N:1"
          description: "速報比較依頼を監視する"
        - target_entity: "E-022"
          type: "1:N"
          description: "通知メールを送る"
    - id: "E-022"
      name: "通知メール"
      source_info: "情報: 通知メール"
      model_type: "event"
      attributes:
        - name: "notification_id"
          type: "string"
          description: "通知 ID"
          nullable: false
          primary_key: true
        - name: "severity"
          type: "string"
          description: "重要度(warning / error)"
          nullable: false
          primary_key: false
        - name: "notification_type"
          type: "string"
          description: "通知種別(ハング疑い / background 実行エラー / 速報クロスチェック異常)"
          nullable: false
          primary_key: false
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: false
          primary_key: false
        - name: "job_id"
          type: "string"
          description: "JOB_ID"
          nullable: false
          primary_key: false
        - name: "role"
          type: "string"
          description: "role"
          nullable: false
          primary_key: false
        - name: "elapsed_minutes"
          type: "integer"
          description: "経過時間"
          nullable: true
          primary_key: false
        - name: "recipient"
          type: "string"
          description: "宛先(運用者。ハング検知定期ジョブ設定の通知先メールアドレス)"
          nullable: false
          primary_key: false
        - name: "subject"
          type: "string"
          description: "件名(ハング検知定期ジョブ設定の件名プレフィックス + 通知種別 + run_id)"
          nullable: false
          primary_key: false
        - name: "body"
          type: "text"
          description: "本文"
          nullable: false
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "送信日時"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-021"
          type: "N:1"
          description: "監視記録から送られる"
        - target_entity: "E-026"
          type: "N:1"
          description: "宛先・送信コマンド・件名プレフィックスの出所"
    - id: "E-023"
      name: "リラン指示"
      source_info: "情報: リラン指示"
      model_type: "event"
      attributes:
        - name: "new_run_id"
          type: "string"
          description: "新 run_id"
          nullable: false
          primary_key: true
        - name: "source_run_id"
          type: "string"
          description: "--source-run-id"
          nullable: false
          primary_key: false
        - name: "role"
          type: "string"
          description: "--role(blue / green / rapid-crosscheck)"
          nullable: false
          primary_key: false
        - name: "parent_run_id"
          type: "string"
          description: "parent_run_id(直前のリラン元)"
          nullable: false
          primary_key: false
        - name: "source_job_definition"
          type: "string"
          description: "起動元専用ジョブ"
          nullable: true
          primary_key: false
        - name: "precheck_result"
          type: "text"
          description: "事前検証結果(元の mode / 元の状態 / role 妥当性)"
          nullable: false
          primary_key: false
        - name: "occurred_at"
          type: "datetime"
          description: "指示日時"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "1:1"
          description: "新しい並行稼働実行を作成する"
        - target_entity: "E-010"
          type: "N:1"
          description: "元の execution-spec から復元する"
    - id: "E-024"
      name: "中止指示"
      source_info: "情報: 中止指示"
      model_type: "event"
      attributes:
        - name: "run_id"
          type: "string"
          description: "--run-id"
          nullable: false
          primary_key: true
        - name: "abort_target"
          type: "string"
          description: "中止対象種別(abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck)"
          nullable: false
          primary_key: true
        - name: "occurred_at"
          type: "datetime"
          description: "指示日時"
          nullable: false
          primary_key: true
        - name: "displayed_status"
          type: "string"
          description: "表示した現在状態"
          nullable: false
          primary_key: false
        - name: "confirmation"
          type: "string"
          description: "停止確認応答(yes / no)"
          nullable: false
          primary_key: false
        - name: "operator"
          type: "string"
          description: "指示者(実行ユーザー)"
          nullable: false
          primary_key: false
        - name: "resulting_status"
          type: "string"
          description: "更新後状態(ABORTED。yes 以外なら変更なし。abort-blue / abort-green では対象 run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(競合窓の保険)。abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING の速報比較依頼を status IN 条件の条件付き UPDATE で ABORTED にする)"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-014"
          type: "N:1"
          description: "background slot 実行を中止する"
        - target_entity: "E-017"
          type: "N:1"
          description: "速報比較依頼を中止する(abort-rapid-crosscheck は REQUESTED / CLAIMED / RUNNING の依頼、abort-blue / abort-green は対象 run の REQUESTED で未着手の依頼。競合窓の保険)"
        - target_entity: "E-019"
          type: "N:1"
          description: "確報比較依頼を中止する(abort-final-crosscheck。RUNNING のときだけ)"

    - id: "E-025"
      name: "実行ログ"
      source_info: "情報: 実行ログ"
      model_type: "event"
      attributes:
        - name: "log_file_path"
          type: "string"
          description: "ログファイルパス"
          nullable: false
          primary_key: true
        - name: "occurred_at"
          type: "datetime"
          description: "出力日時(ホストのローカルタイムゾーン、ISO 8601 秒精度、タイムゾーン指示子なし。run_id の時刻部と同じ時刻軸)"
          nullable: false
          primary_key: true
        - name: "script_name"
          type: "string"
          description: "スクリプト名(facade / runner / クロスチェック runner・worker / ハング検知 / background-rerun / 中止スクリプト)"
          nullable: false
          primary_key: false
        - name: "run_id"
          type: "string"
          description: "run_id"
          nullable: true
          primary_key: false
        - name: "level"
          type: "string"
          description: "ログレベル"
          nullable: false
          primary_key: false
        - name: "message"
          type: "text"
          description: "メッセージ"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-013"
          type: "N:1"
          description: "run_id をキーに並行稼働実行を追跡する"
    - id: "E-026"
      name: "ハング検知定期ジョブ設定"
      source_info: "情報: ハング検知定期ジョブ設定"
      model_type: "resource_mutable"
      attributes:
        - name: "alert_mail_to"
          type: "string"
          description: "通知先メールアドレス(ALERT_MAIL_TO)"
          nullable: false
          primary_key: false
        - name: "alert_mail_cmd"
          type: "string"
          description: "送信コマンド(ALERT_MAIL_CMD。OS 標準のメール送信コマンド)"
          nullable: false
          primary_key: false
        - name: "alert_subject_prefix"
          type: "string"
          description: "件名プレフィックス(ALERT_SUBJECT_PREFIX)"
          nullable: false
          primary_key: false
        - name: "db_conn_ref"
          type: "string"
          description: "管理 DB 接続参照名(HANG_DB_CONN_REF。認証情報の値は置かず参照名のみ)"
          nullable: true
          primary_key: false
      relationships:
        - target_entity: "E-022"
          type: "1:N"
          description: "通知メールの宛先・送信コマンド・件名プレフィックスを与える"
        - target_entity: "E-021"
          type: "1:N"
          description: "監視記録の保存先(管理 DB 接続参照名)を与える"
    - id: "E-027"
      name: "速報クロスチェック設定"
      source_info: "情報: 速報クロスチェック設定"
      model_type: "resource_mutable"
      attributes:
        - name: "db_conn_ref"
          type: "string"
          description: "管理 DB 接続参照名(RAPID_DB_CONN_REF。認証情報の値は置かず参照名のみ)"
          nullable: false
          primary_key: false
        - name: "lease_sec"
          type: "integer"
          description: "依頼の claim に付与する lease 期間(秒。RAPID_LEASE_SEC)"
          nullable: false
          primary_key: false
        - name: "poll_interval_sec"
          type: "integer"
          description: "worker が依頼を poll する間隔(秒。RAPID_POLL_INTERVAL_SEC)"
          nullable: false
          primary_key: false
      relationships:
        - target_entity: "E-017"
          type: "1:N"
          description: "速報比較依頼の claim の lease 期間と poll 間隔を与える"
        - target_entity: "E-013"
          type: "1:N"
          description: "facade が parallel_run を作成する管理 DB の接続参照名を与える(速報有効時のみ)"
        - target_entity: "E-015"
          type: "1:N"
          description: "完了通知の登録先(管理 DB)の接続参照名を与える"
        - target_entity: "E-026"
          type: "1:1"
          description: "ハング検知定期ジョブ設定と同型(env 形式・接続参照名)だが、所有項目と読み手が異なるため別ファイル"
```

## 追加転写元: `docs/nfr/latest/nfr-grade.yaml`

- 転写元: `docs/nfr/latest/nfr-grade.yaml`
- source_sha256: `5a7c72400cfc8c65de278dc284e656a73d60b643a91f69ecfa44688a0824b653`
- 生成: `extractSections.js`（原文転写。要約・言い換えなし）

### 転写済みセクションのチェックリスト

| セクション | 状態 |
|---|---|
| `categories[id=A]` | 転写済み |
| `categories[id=B]` | 転写済み |
| `categories[id=E]` | 転写済み |

`not_applicable` = 元ファイルにセクション自体が存在しない（フォールバック対象外。元ファイルを読みに行かない）。

### categories[id=A]

```yaml
  - id: "A"
    name: "可用性"
    subcategories:
      - id: "A.1"
        name: "継続性"
        items:
          - id: "A.1.1"
            name: "運用スケジュール"
            important: true
            metrics:
              - id: "A.1.1.1"
                name: "運用時間(通常)"
                important: true
                grade: 3
                grade_description: "1時間程度の停止(9時〜翌8時)"
                reason: "業務ジョブはジョブスケジューラの起動時刻に依存し、確報クロスチェックが日次処理後(夜間)に、ハング検知が 5 分ごとの定期ジョブとして動作するため、ほぼ終日稼働で短時間の停止のみ許容する"
                source_model: "外部システム: ジョブスケジューラ / BUC: 確報クロスチェックフロー、background 実行監視フロー"
                confidence: "medium"
              - id: "A.1.1.2"
                name: "運用時間(特定日)"
                important: false
                grade: 0
                grade_description: "規定なし"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
              - id: "A.1.1.3"
                name: "計画停止の有無"
                important: true
                grade: 2
                grade_description: "不定期に計画停止あり(事前通知1週間前)"
                reason: "計画停止はジョブスケジューラの実行計画(夜間バッチ・日次確報)と調整して行う必要があり、月次固定ではなく事前通知つきの不定期停止が現実的なため"
                source_model: "外部システム: ジョブスケジューラ / バリエーション: ジョブスケジューラ起動ジョブ種別"
                confidence: "medium"
      - id: "A.2"
        name: "耐障害性"
        items:
          - id: "A.2.1"
            name: "サーバ"
            important: true
            metrics:
              - id: "A.2.1.1"
                name: "サーバ内の冗長化"
                important: true
                grade: 2
                grade_description: "電源・ディスク冗長化"
                reason: "ユーザー指定: 2026-09-05 に利用者が既定値として確定(適用先ごとに見直す運用パラメータであり、適用側で上書き可能な既定値)。facade・runner はジョブスケジューラの実行ホスト上で動作し、ジョブキュー兼管理 DB は単一 RDB 構成のため、部品レベルの冗長化を既定値とする"
                source_model: "システム概要: ジョブキュー兼管理 DB(relay-gate 内部のデータストア)"
                confidence: "user"
          - id: "A.2.2"
            name: "端末"
            important: false
            metrics:
              - id: "A.2.2.1"
                name: "端末の冗長化"
                important: false
                grade: 1
                grade_description: "冗長化なし"
                reason: "モデルシステム1のデフォルト値を適用(運用者端末はターミナルのみ)"
                source_model: ""
                confidence: "default"
          - id: "A.2.3"
            name: "ネットワーク機器"
            important: true
            metrics:
              - id: "A.2.3.1"
                name: "ネットワーク機器の冗長化"
                important: true
                grade: 1
                grade_description: "冗長化なし"
                reason: "モデルシステム1のデフォルト値を適用(ネットワーク構成は適用文書の所有事項)"
                source_model: "情報: 適用構成文書"
                confidence: "default"
          - id: "A.2.4"
            name: "ネットワーク回線"
            important: false
            metrics:
              - id: "A.2.4.1"
                name: "回線の冗長化"
                important: false
                grade: 1
                grade_description: "冗長化なし"
                reason: "モデルシステム1のデフォルト値を適用(閉域網内のみで外部回線を持たない)"
                source_model: ""
                confidence: "default"
          - id: "A.2.5"
            name: "ストレージ"
            important: true
            metrics:
              - id: "A.2.5.1"
                name: "ストレージの冗長化"
                important: true
                grade: 1
                grade_description: "RAID1(ミラーリング)"
                reason: "モデルシステム1のデフォルト値を適用。成果物ディレクトリと管理 DB を保持する最低限のミラーリング"
                source_model: "情報: Runner Result / システム概要: ジョブキュー兼管理 DB(relay-gate 内部のデータストア)"
                confidence: "default"
          - id: "A.2.6"
            name: "建物・電源"
            important: false
            metrics:
              - id: "A.2.6.1"
                name: "建物の耐震・免震"
                important: false
                grade: 1
                grade_description: "一般建築基準"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
              - id: "A.2.6.2"
                name: "電源の冗長化"
                important: true
                grade: 1
                grade_description: "冗長化なし"
                reason: "モデルシステム1のデフォルト値を適用(設置環境は適用側の責務)"
                source_model: ""
                confidence: "default"
      - id: "A.3"
        name: "災害対策"
        items:
          - id: "A.3.1"
            name: "災害対策"
            important: true
            metrics:
              - id: "A.3.1.1"
                name: "災害対策の範囲"
                important: true
                grade: 0
                grade_description: "対策なし"
                reason: "ユーザー指定: 2026-09-05 に利用者が既定値として確定(適用先ごとに見直す運用パラメータであり、適用側で上書き可能な既定値)。実行履歴・監査はジョブスケジューラの責務であり、relay-gate の成果物と execution-spec.json からリラン可能なため、基盤単体の遠隔地対策は不要とする"
                source_model: "条件: 実行履歴はジョブスケジューラの責務 / 条件: リランの実行設定復元"
                confidence: "user"
              - id: "A.3.1.2"
                name: "業務継続の要否"
                important: true
                grade: 0
                grade_description: "業務継続不要"
                reason: "ユーザー指定: 2026-09-05 に利用者が既定値として確定(適用先ごとに見直す運用パラメータであり、適用側で上書き可能な既定値)。被災時は業務ジョブ自体の継続計画(実装側・ジョブスケジューラ側)に従い、relay-gate 単体の継続要件は規定しない(A.3.1.1 と対)"
                source_model: "条件: 実行履歴はジョブスケジューラの責務"
                confidence: "user"
      - id: "A.4"
        name: "回復性"
        items:
          - id: "A.4.1"
            name: "目標復旧水準"
            important: true
            metrics:
              - id: "A.4.1.1"
                name: "RPO(目標復旧地点)"
                important: true
                grade: 2
                grade_description: "数時間前まで"
                reason: "管理 DB はジョブキュー兼監視記録であり、失われても execution-spec.json と Runner Result からリランできるが、当日分の background 実行の追跡を失わないよう数時間以内の復旧地点とする"
                source_model: "情報: 実行設定(execution-spec)、Runner Result、並行稼働実行(parallel_run)"
                confidence: "medium"
              - id: "A.4.1.2"
                name: "RTO(目標復旧時間)"
                important: true
                grade: 2
                grade_description: "半日以内"
                reason: "foreground slot の結果は本番業務ジョブの結果としてジョブスケジューラへ中継されるため、次回のバッチウィンドウまでに復旧する必要がある"
                source_model: "BUC: 実装切替ジョブ実行フロー(foreground 結果の中継)"
                confidence: "medium"
              - id: "A.4.1.3"
                name: "RLO(目標復旧レベル)"
                important: false
                grade: 1
                grade_description: "縮退運転(主要機能のみ)"
                reason: "RAPID_CROSSCHECK_MODE=off にすると parallel_run を作らず、管理 DB なしで slot 実行・ハング検知・中止(aborted.txt をファイル正本に書く)・background 側リランが動作する縮退運転が設計上用意されているため(slot 実行の状態は exitcode.txt / aborted.txt の有無から導出する)"
                source_model: "条件: 速報クロスチェック有効判定 / 条件: slot 実行の状態導出規則 / バリエーション: 速報クロスチェックモード(foreground / background / off)"
                confidence: "high"
```

### categories[id=B]

```yaml
  - id: "B"
    name: "性能・拡張性"
    subcategories:
      - id: "B.1"
        name: "業務処理量"
        items:
          - id: "B.1.1"
            name: "通常時の業務量"
            important: true
            metrics:
              - id: "B.1.1.1"
                name: "同時アクセス数"
                important: true
                grade: 1
                grade_description: "〜100"
                reason: "利用者は運用部門の少人数(運用者・基盤適用設計者)で、CLI と定期ジョブのみのため"
                source_model: "アクター: 運用者、基盤適用設計者 / 条件: CLI とメールによる提示"
                confidence: "high"
              - id: "B.1.1.2"
                name: "データ量"
                important: false
                grade: 1
                grade_description: "〜100万件/年(parallel_run・slot 実行・比較依頼・監視記録の管理レコード)。CSV 形式の設定ファイルの共通前提: slot ジョブマップ・クロスチェックジョブマップ・対象カタログは、1 ファイルあたりの想定最大行数をヘッダー行を除いて 5,000 行とする。内容の最悪条件は、全行で任意列を含む全列に値があり、キー列(job_id、対象カタログは target_identifier)が全行一意で、版の列(map_version、カタログ版)の値が全行異なるもの。設定ファイルを読む処理は、行数に比例する時間で処理できる実装を前提とする。機能ごとの仕様・検証は、行数と内容の条件をこの共通前提から引き、機能ごとに再決定しない"
                reason: "ユーザー指定: 2026-09-21 に利用者が確定。管理レコードは年間 100 万件以内の想定を据え置く。設定ファイルの規模は元の方針資料に記載が無い新規の決定で、1 つのジョブマップに 3,000 ジョブ程度はあり得るという利用者の見立てに余裕を持たせて 5,000 行とした。閾値を機能ごとに考え直さない方針のため、同じ CSV 形式の設定ファイル 3 種に共通の前提として 1 か所に定める。2026-09-21 の実測(現状のジョブマップ検証、最悪条件)は 1,000 行 2.2 秒、2,000 行 6.6 秒、3,000 行 13.8 秒、5,000 行 36 秒で、典型の内容(map_version 全行同一)は 3,000 行 2.5 秒。現状の実装は 5,000 行の最悪条件で性能目標値(B.2.1.1)を超えるため、版の列の集計を行数の 2 乗の比較から行数に比例する処理へ改める実装改善を前提とする"
                source_model: "情報: 並行稼働実行(parallel_run)、slot 実行、速報比較依頼、監視記録、ジョブマップ、クロスチェックジョブマップ、対象カタログ / 条件: ジョブマップ解決条件"
                confidence: "user"
              - id: "B.1.1.3"
                name: "オンラインリクエスト件数"
                important: true
                grade: 1
                grade_description: "〜1,000件/日(facade 起動・定期監視・CLI 操作の合計)"
                reason: "オンライン画面は無く、リクエストに相当するのはジョブスケジューラからの facade 起動と 5 分ごとの監視ジョブのため"
                source_model: "バリエーション: ジョブスケジューラ起動ジョブ種別"
                confidence: "medium"
              - id: "B.1.1.4"
                name: "バッチ処理件数"
                important: false
                grade: 2
                grade_description: "確報は全テーブル・全ファイルの日次全量比較(対象件数は適用側の対象カタログで定義)"
                reason: "確報クロスチェックが business_date 単位で全テーブル・全ファイルを比較する大量バッチのため"
                source_model: "BUC: 確報クロスチェックフロー / 情報: 対象カタログ"
                confidence: "medium"
          - id: "B.1.2"
            name: "ピーク時の業務量"
            important: false
            metrics:
              - id: "B.1.2.1"
                name: "ピーク時同時アクセス数"
                important: true
                grade: 2
                grade_description: "通常時の2倍"
                reason: "並行稼働モードでは blue と green の 2 系統が同時実行され、速報クロスチェックも追加で動くため、単独本番時に対して 2 倍の同時実行を見込む"
                source_model: "バリエーション: 運用モード / 条件: slot 起動順序"
                confidence: "medium"
              - id: "B.1.2.2"
                name: "ピーク時データ量"
                important: false
                grade: 1
                grade_description: "並行稼働時は成果物(Runner Result)が blue / green の 2 倍"
                reason: "並行稼働時は slot ごとに成果物ディレクトリを生成するため"
                source_model: "情報: Runner Result / バリエーション: 実装スロット"
                confidence: "medium"
      - id: "B.2"
        name: "性能目標値"
        items:
          - id: "B.2.1"
            name: "オンライン"
            important: true
            metrics:
              - id: "B.2.1.1"
                name: "レスポンスタイム"
                important: true
                grade: 2
                grade_description: "10秒以内(facade のオーバーヘッド・中止/リラン CLI の応答)。CSV 形式の設定ファイルを読む CLI と facade の設定読み込みは、B.1.1.2 の共通前提(1 ファイルあたり想定最大 5,000 行、最悪条件を含め内容によらず)で 10 秒以内に収める"
                reason: "ユーザー指定: 2026-09-21 に利用者が確定。運用者向けの CLI 操作と facade の起動・中継のオーバーヘッドが対象で、業務ジョブ本体の処理時間は実装側の責務のため。目標を満たす行数と内容の条件は B.1.1.2 の共通前提の 1 か所から引き、内容によらず(最悪条件を含めて)10 秒以内とすることで、性能の合否を機能ごとに再決定せず判定できるようにする"
                source_model: "条件: facade の責務限定 / 条件: CLI とメールによる提示 / 条件: ジョブマップ解決条件 / 情報: ジョブマップ、クロスチェックジョブマップ、対象カタログ"
                confidence: "user"
              - id: "B.2.1.2"
                name: "スループット"
                important: true
                grade: 1
                grade_description: "〜10 TPS"
                reason: "ジョブキュー兼管理 DB への書き込みはジョブ起動・完了通知・claim・監視記録が中心で低頻度のため"
                source_model: "システム概要: ジョブキュー兼管理 DB(relay-gate 内部のデータストア)"
                confidence: "high"
              - id: "B.2.1.3"
                name: "ターンアラウンドタイム"
                important: false
                grade: 1
                grade_description: "foreground 結果は slot 終了後に即時中継。速報クロスチェックは非同期で応答に影響させない"
                reason: "facade は foreground の PID だけを待機し、background や速報の完了を待たずに応答する設計のため"
                source_model: "条件: ジョブスケジューラ応答の決定 / 条件: 速報結果の位置付け"
                confidence: "high"
          - id: "B.2.2"
            name: "バッチ"
            important: true
            metrics:
              - id: "B.2.2.1"
                name: "バッチ処理時間"
                important: true
                grade: 2
                grade_description: "8時間以内(日次確報クロスチェックは夜間ウィンドウ内に完了)"
                reason: "確報クロスチェックは日次処理が落ち着いた後に起動しリリース判断に用いるため、翌日の業務開始前に完了する必要がある。導入時のハング検知上限 60 分から個々のジョブは 1 時間程度と想定"
                source_model: "BUC: 確報クロスチェックフロー / バリエーション: ハング検知上限設定"
                confidence: "medium"
              - id: "B.2.2.2"
                name: "バッチ処理量"
                important: false
                grade: 1
                grade_description: "速報はジョブ単位、確報は対象カタログの全テーブル・全ファイル"
                reason: "比較種別が速報(ジョブ単位比較)と確報(全量比較)に分かれ、対象は適用側が定義するため"
                source_model: "バリエーション: 比較種別 / 情報: 対象カタログ"
                confidence: "medium"
      - id: "B.3"
        name: "リソース拡張性"
        items:
          - id: "B.3.1"
            name: "CPU"
            important: true
            metrics:
              - id: "B.3.1.1"
                name: "CPU拡張性"
                important: true
                grade: 2
                grade_description: "スケールアウト(サーバ追加)"
                reason: "クロスチェック worker は管理 DB を poll / claim し worker_id と lease で多重実行を防ぐ設計のため、worker を追加して水平に拡張できる。lease 期間と poll 間隔は速報クロスチェック設定(RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC)で適用側が調整する"
                source_model: "条件: claim 排他 / 条件: lease 失効判定 / 情報: 速報クロスチェック設定"
                confidence: "high"
          - id: "B.3.2"
            name: "メモリ"
            important: false
            metrics:
              - id: "B.3.2.1"
                name: "メモリ拡張性"
                important: false
                grade: 1
                grade_description: "スケールアップ"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
          - id: "B.3.3"
            name: "ストレージ"
            important: false
            metrics:
              - id: "B.3.3.1"
                name: "ストレージ拡張性"
                important: false
                grade: 1
                grade_description: "スケールアップ(成果物ディレクトリ・実行ログの増加に応じて拡張)"
                reason: "run ごとに成果物ディレクトリと実行ログを蓄積するため、保管期間に応じたストレージ増設が必要"
                source_model: "情報: Runner Result、実行ログ"
                confidence: "medium"
          - id: "B.3.4"
            name: "ネットワーク"
            important: false
            metrics:
              - id: "B.3.4.1"
                name: "ネットワーク拡張性"
                important: false
                grade: 1
                grade_description: "特別な要件なし"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
      - id: "B.4"
        name: "性能品質保証"
        items:
          - id: "B.4.1"
            name: "性能テスト"
            important: true
            metrics:
              - id: "B.4.1.1"
                name: "性能テスト"
                important: true
                grade: 1
                grade_description: "単体での性能テスト"
                reason: "relay-gate のオーバーヘッド(起動・中継・poll)の確認に限定し、業務ジョブ本体の性能は実装側の責務のため"
                source_model: "条件: facade の責務限定"
                confidence: "medium"
```

### categories[id=E]

```yaml
  - id: "E"
    name: "セキュリティ"
    subcategories:
      - id: "E.1"
        name: "前提条件・制約条件"
        items:
          - id: "E.1.1"
            name: "セキュリティポリシー"
            important: true
            metrics:
              - id: "E.1.1.1"
                name: "セキュリティポリシー"
                important: true
                grade: 2
                grade_description: "組織のセキュリティポリシーに準拠"
                reason: "エアーギャップ環境のオンプレミスで運用する前提から、組織のセキュリティポリシーが存在しそれに準拠すると推定"
                source_model: "システム概要(エアーギャップ前提)"
                confidence: "medium"
          - id: "E.1.2"
            name: "セキュリティ関連法規"
            important: false
            metrics:
              - id: "E.1.2.1"
                name: "準拠すべき法規・基準"
                important: false
                grade: 0
                grade_description: "基盤として特定なし(業務データに関する法規は実装側・適用側の責務)"
                reason: "relay-gate は業務データ本体を保持せず、成果物と管理レコードのみ扱うため"
                source_model: "条件: 適用側で定義する事項"
                confidence: "default"
      - id: "E.2"
        name: "セキュリティリスク分析"
        items:
          - id: "E.2.1"
            name: "リスク分析"
            important: true
            metrics:
              - id: "E.2.1.1"
                name: "セキュリティリスク分析"
                important: true
                grade: 1
                grade_description: "簡易チェックリストによる確認"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
      - id: "E.3"
        name: "セキュリティ診断"
        items:
          - id: "E.3.1"
            name: "セキュリティ診断"
            important: true
            metrics:
              - id: "E.3.1.1"
                name: "セキュリティ診断"
                important: true
                grade: 0
                grade_description: "診断なし"
                reason: "モデルシステム1のデフォルト値を適用(閉域網内の CLI のみで外部公開面がない)"
                source_model: ""
                confidence: "default"
      - id: "E.4"
        name: "セキュリティリスク管理"
        items:
          - id: "E.4.1"
            name: "リスク管理"
            important: false
            metrics:
              - id: "E.4.1.1"
                name: "リスク管理プロセス"
                important: false
                grade: 1
                grade_description: "組織の運用ルールに従う"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
      - id: "E.5"
        name: "アクセス・利用制限"
        items:
          - id: "E.5.1"
            name: "認証"
            important: true
            metrics:
              - id: "E.5.1.1"
                name: "認証方式"
                important: true
                grade: 1
                grade_description: "OS アカウントと SSH 鍵による認証。認証情報(SSH・管理 DB 接続)は値を保存せず参照名で管理"
                reason: "実行先ホストへは実行ユーザーで SSH 接続し、execution-spec.json には認証情報の参照名のみを保存し、管理 DB への接続も速報クロスチェック設定の接続参照名(RAPID_DB_CONN_REF)で解決して値を置かない設計のため"
                source_model: "外部システム: リモート実行ホスト(SSH) / 条件: 認証情報の非保存 / 情報: 速報クロスチェック設定"
                confidence: "high"
          - id: "E.5.2"
            name: "アクセス制御"
            important: true
            metrics:
              - id: "E.5.2.1"
                name: "アクセス制御"
                important: true
                grade: 1
                grade_description: "ユーザ単位の制御(ジョブマップの user 列で解決する実行ユーザーと OS 権限。ローカル実行の slot では host / user を省略でき起動ユーザーの権限で実行)"
                reason: "ジョブマップ(CSV)が job_id ごとに host / user 列で実行先と実行ユーザーを解決し、OS 権限で制御するため。ロール概念は RDRA に無い"
                source_model: "情報: ジョブマップ(host / user 列) / 条件: ジョブマップ解決条件"
                confidence: "high"
          - id: "E.5.3"
            name: "利用制限"
            important: false
            metrics:
              - id: "E.5.3.1"
                name: "利用制限"
                important: false
                grade: 1
                grade_description: "閉域網内のジョブスケジューラ実行ホストと運用者端末に限定。インターネット接続なし"
                reason: "エアーギャップ環境で、起動口はジョブスケジューラのジョブ定義と運用者の CLI のみのため"
                source_model: "バリエーション: ジョブスケジューラ起動ジョブ種別 / システム概要(エアーギャップ前提)"
                confidence: "high"
      - id: "E.6"
        name: "データ秘匿"
        items:
          - id: "E.6.1"
            name: "暗号化"
            important: true
            metrics:
              - id: "E.6.1.1"
                name: "データ暗号化(保管時)"
                important: true
                grade: 0
                grade_description: "暗号化なし"
                reason: "認証情報の値を保存しない設計であり、管理 DB と成果物に機密データを持たないため保管時暗号化を要求しない。成果物の stdout / stderr に業務データが含まれるかは適用側で確認する"
                source_model: "条件: 認証情報の非保存 / 情報: Runner Result"
                confidence: "medium"
              - id: "E.6.1.2"
                name: "データ暗号化(通信時)"
                important: true
                grade: 1
                grade_description: "外部通信のみ暗号化(SSH 経路)。管理 DB 接続は閉域セグメント内"
                reason: "実行先ホストへの通信は SSH で暗号化され、relay-gate 内部のジョブキュー兼管理 DB への接続は閉域網内のため"
                source_model: "外部システム: リモート実行ホスト(SSH) / システム概要: ジョブキュー兼管理 DB(relay-gate 内部のデータストア)"
                confidence: "medium"
          - id: "E.6.2"
            name: "データマスキング"
            important: false
            metrics:
              - id: "E.6.2.1"
                name: "データマスキング"
                important: false
                grade: 0
                grade_description: "なし"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
      - id: "E.7"
        name: "不正追跡・監視"
        items:
          - id: "E.7.1"
            name: "監査ログ"
            important: true
            metrics:
              - id: "E.7.1.1"
                name: "監査ログ"
                important: true
                grade: 2
                grade_description: "運用操作(中止・リラン)と状態遷移を run_id 付きの実行ログ・管理レコードで記録。監査の正本はジョブスケジューラ"
                reason: "中止指示に指示者と応答を記録し、実行ログに run_id を残す設計だが、監査はジョブスケジューラの責務と定義されているため"
                source_model: "情報: 中止指示、実行ログ / 条件: 実行履歴はジョブスケジューラの責務"
                confidence: "medium"
          - id: "E.7.2"
            name: "不正監視"
            important: false
            metrics:
              - id: "E.7.2.1"
                name: "不正監視"
                important: false
                grade: 0
                grade_description: "なし(閉域網・OS 側の責務)"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
      - id: "E.8"
        name: "ネットワーク対策"
        items:
          - id: "E.8.1"
            name: "ファイアウォール"
            important: true
            metrics:
              - id: "E.8.1.1"
                name: "ファイアウォール"
                important: true
                grade: 1
                grade_description: "パケットフィルタリング"
                reason: "モデルシステム1のデフォルト値を適用(ネットワーク制約は適用文書の所有事項)"
                source_model: "情報: 適用構成文書"
                confidence: "default"
          - id: "E.8.2"
            name: "IDS/IPS"
            important: false
            metrics:
              - id: "E.8.2.1"
                name: "IDS/IPS"
                important: false
                grade: 0
                grade_description: "なし"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
          - id: "E.8.3"
            name: "ネットワーク分離"
            important: false
            metrics:
              - id: "E.8.3.1"
                name: "ネットワーク分離"
                important: false
                grade: 1
                grade_description: "適用文書で定義するセグメント分離(DB セグメント経由の実行など)を前提"
                reason: "適用構成文書がネットワーク制約・ホスト配置・DB セグメント構成を所有し、リモート実行ホストが案件固有の配置を吸収する設計のため"
                source_model: "情報: 適用構成文書 / 外部システム: リモート実行ホスト(SSH)"
                confidence: "medium"
      - id: "E.9"
        name: "マルウェア対策"
        items:
          - id: "E.9.1"
            name: "マルウェア対策"
            important: true
            metrics:
              - id: "E.9.1.1"
                name: "マルウェア対策"
                important: true
                grade: 1
                grade_description: "ウイルス対策ソフト導入"
                reason: "モデルシステム1のデフォルト値を適用(定義ファイルの更新はエアーギャップのためオフライン持ち込み)"
                source_model: ""
                confidence: "default"
      - id: "E.10"
        name: "Web対策"
        items:
          - id: "E.10.1"
            name: "WAF"
            important: true
            metrics:
              - id: "E.10.1.1"
                name: "WAF"
                important: true
                grade: 0
                grade_description: "WAFなし"
                reason: "UI 画面や HTTP API を持たず CLI と定期ジョブのみのため対象外"
                source_model: "条件: CLI とメールによる提示 / システム概要(interface_kind: cli)"
                confidence: "high"
          - id: "E.10.2"
            name: "Webアプリケーション対策"
            important: false
            metrics:
              - id: "E.10.2.1"
                name: "Webアプリケーション対策"
                important: false
                grade: 0
                grade_description: "対象外(Web なし)。代わりにシェル引数は JSON 配列で数・空白・カンマを維持して安全に連結する"
                reason: "Web アプリケーションが存在しないため。引数連結規則がコマンドインジェクション対策に相当する"
                source_model: "条件: 引数連結規則"
                confidence: "high"
      - id: "E.11"
        name: "セキュリティインシデント対応"
        items:
          - id: "E.11.1"
            name: "インシデント対応"
            important: true
            metrics:
              - id: "E.11.1.1"
                name: "インシデント対応計画"
                important: true
                grade: 1
                grade_description: "基本的な連絡体制のみ"
                reason: "モデルシステム1のデフォルト値を適用"
                source_model: ""
                confidence: "default"
```
