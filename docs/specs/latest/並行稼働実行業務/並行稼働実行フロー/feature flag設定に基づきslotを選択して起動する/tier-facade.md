# feature flag設定に基づきslotを選択して起動する - tier-facade仕様

## 変更概要

ジョブスケジューラから受け取ったJOB_ID・追加引数を起点に、feature flag設定（BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODE）を判定してblue/greenのslot起動方式を決定し、execution-spec.jsonを一度だけ確定して保存したうえでSSH経由でslotを起動するCLIコマンドを追加する。

## CLI コマンド仕様

### relaygate concurrent-run select-slot

- **呼び出し形式**: `relaygate concurrent-run select-slot --job-id <JOB_ID> [-- <追加引数...>]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --job-id | string | Yes | ジョブスケジューラから渡されるJOB_ID |
  | -- 追加引数 | string[] | No | ジョブ定義に付随する追加引数。そのままexecution-spec.jsonのadditional_argsに保存する |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_JOB_MAP_PATH | Yes | ジョブマップ（実行先解決定義）のファイルパス |
  | BLUE_MODE | Yes | off/background/foreground のいずれか |
  | GREEN_MODE | Yes | off/background/foreground のいずれか |
  | RAPID_CROSSCHECK_MODE | Yes | on/off のいずれか |
- **標準入力**: なし
- **標準出力契約**: `blue: {off|background|foreground}` / `green: {off|background|foreground}` / `run_id: {run_id}` の3行を含む起動結果テキスト
- **標準エラー契約**: feature flag違反・ジョブマップ未解決時のエラーメッセージ（原因を1文で明示）
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（slot選択・execution-spec.json確定・起動完了） |
  | 1 | 業務エラー（ジョブマップ未解決、起動先実装への接続失敗） |
  | 2 | バリデーションエラー（BLUE_MODE/GREEN_MODE同時foreground、JOB_ID未指定） |

## データモデル変更

### execution_specs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 実行の一意識別子（PK） | 追加 |
| parent_run_id | VARCHAR | リラン時の元run_id参照（nullable） | 追加 |
| job_id | VARCHAR | ジョブスケジューラのJOB_ID | 追加 |
| host | VARCHAR | ジョブマップ解決済みの実行先ホスト | 追加 |
| exec_user | VARCHAR | 実行ユーザー | 追加 |
| script_path | VARCHAR | 実行スクリプトパス | 追加 |
| work_dir | VARCHAR | 作業ディレクトリ | 追加 |
| fixed_args | TEXT | 固定引数（nullable） | 追加 |
| additional_args | TEXT | 追加引数（nullable） | 追加 |
| job_map_version | VARCHAR | マップ版 | 追加 |
| impl_version | VARCHAR | 実装版（blue/greenのバージョン） | 追加 |
| hang_detect_limit_minutes | INT | ハング検知しきい値（分） | 追加 |
| credential_ref | VARCHAR | 認証情報参照名（実値は保存しない、nullable） | 追加 |

### runner_results

選択したslotのforeground role起動と同時に、実行状態を追跡するための初期レコードを作成する。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 本UCで新規発番したrun_id（execution_specs.run_idと同一） | 追加 |
| slot_type | VARCHAR | 選択されたslot（blue/green） | 追加 |
| role_type | VARCHAR | 固定値 foreground | 追加 |
| started_at | DATETIME | 起動時刻 | 追加 |
| status | VARCHAR | 固定値 RUNNING | 追加 |

## ビジネスルール

- BLUE_MODEとGREEN_MODEを同時にforegroundにする組み合わせは拒否する（SR-001 排他的foreground制約）
- 選択したslotの起動と同時にrunner_resultsへrole_type=foreground・status=RUNNINGのレコードを作成する。これにより「foreground roleの標準出力・標準エラー・終了コードを応答する」UCがrole_type='foreground'で本レコードを参照できる
- RAPID_CROSSCHECK_MODE=offの場合、blue/green実装からの完了通知送信・速報管理DBへの接続/書込みは一切行わない
- execution-spec.jsonの内容（run_id/parent_run_id/host/実行ユーザー/スクリプト/作業ディレクトリ/固定引数/追加引数/マップ版/実装版/hang_detect_limit_minutes/認証情報参照名）は起動時に一度だけ確定して保存する。リラン時はこの設定を復元する
- 認証情報は参照名のみを保存し実値は保存しない
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### 起動slot選択画面

- **route**: /cli/concurrent-run/select-slot
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | run_id/job_id/host/script/mapVersion/implVersion/hangDetectLimitMinutes/credentialRefを表示。credentialRefは参照名のみ |
  | エラー・警告バナー | バナー | Banner（error/warning） | BLUE_MODE/GREEN_MODE同時foreground拒否理由を即時表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | 拒否理由バナー | banner-error | background: var(--color-red-100), foreground: var(--color-red-600) |
  | 実行設定カード背景 | var(--semantic-background) | var(--color-white) |
- **UIロジック**:
  - **状態管理**: JOB_ID起動ごとに新規のexecution-spec.jsonが1件確定される（キャッシュしない、冪等性はrun_idの一意性で担保: LR-003）
  - **バリデーション**: CLI引数解析時点でBLUE_MODE/GREEN_MODEの組み合わせ・JOB_ID必須を全て検証する（LP-001）
  - **ローディング**: CLI応答10秒以内。将来ダッシュボードではExecutionSpecCard表示前にローディング表示
  - **エラーハンドリング**: feature flag違反は終了コード2、ジョブマップ未解決・起動先接続失敗は終了コード1で区別する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「共通状態表示パターン」（エラー表示は Banner の error variant）を適用する。ExecutionSpecCard は design-event.yaml 既存コンポーネントをそのまま利用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}, jobId={job_id}, host={host}, script={script_path}, workDir={work_dir}, fixedArgs={fixed_args}, additionalArgs={additional_args}, mapVersion={job_map_version}, implVersion={impl_version}, hangDetectLimitMinutes={hang_detect_limit_minutes}, credentialRef={credential_ref}（参照名のみ） |
| Banner | `@/components/ui/Banner` | variant="error" \| "warning", message={BLUE_MODE/GREEN_MODE同時foreground拒否理由} |

## ティア完了条件（BDD）

```gherkin
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Scenario: 排他制約を満たすfeature flag設定でexecution-spec.jsonを確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on が設定されている
    And JOB_ID "JOB-2026-0817-001" がジョブマップで解決可能である
    When `relaygate concurrent-run select-slot --job-id JOB-2026-0817-001` を実行する
    Then 終了コード 0 で終了する
    And execution_specsテーブルに run_id を持つ1件のレコードがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground が設定されている
    When `relaygate concurrent-run select-slot --job-id JOB-2026-0817-003` を実行する
    Then 終了コード 2 で終了する
    And execution_specsテーブルへのINSERTは発生しない
```
