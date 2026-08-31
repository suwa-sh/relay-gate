# foreground slot の結果をジョブスケジューラへ中継する - facade / slot runner ティア仕様

## 変更概要

`facade.sh` の中継フェーズ: presentation(無加工中継)、usecase(完備確認 → 中継 → (on) COMPLETED 更新)、repository(Runner Result 参照、parallel_runs 更新)、gateway(RDB)を新規実装する。UC「slot 実行モードを選択して runner を起動する」の `wait` 完了後に続けて実行される。

## コマンド契約

### facade.sh(中継フェーズ)

- **書式**: `facade.sh JOB_ID [PARAM...]`(前 UC と同一プロセス)
- **アクセス権**: ジョブスケジューラの業務ジョブ定義

#### 引数・オプション

前 UC と同じ。中継フェーズ固有の引数は無い。

- **stdin**: なし

## 出力契約

ui-design.md「適用範囲と適用外」のとおり、この経路は **出力規約の適用外(無加工)**。

- **stdout**: `facade/<run_id>/<fg_role>/stdout.log` の全バイト。先頭・末尾に何も付けない。改行の有無もファイルどおり
- **stderr**: `facade/<run_id>/<fg_role>/stderr.log` の全バイト。relay-gate 自身の `info:` / `warn:` は出さない(実行ログへ)
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| exitcode.txt の値(0〜255) | foreground の結果をそのまま | 3 ファイル完備 |
| 6 | 実行エラー(relay-gate 自身) | exitcode.txt が無い / 数値 1 行でない / stdout.log・stderr.log が読めない。stderr に `error: foreground runner result incomplete run_id=... role=...` と、次行に `artifact_dir: <path>` の 2 行。この stderr 出力は relay-gate 自身のエラーであり中継内容ではない |

- **parallel_runs 更新失敗の終了コードの区別**(契約 facade.sh exit 6 との整合): runner 起動前〜foreground 待機前の管理 DB 書き込み失敗(parallel_runs INSERT(STARTED)/ STARTED→RUNNING UPDATE。UC「slot 実行モードを選択して runner を起動する」)は終了コード 6。**中継後の RUNNING→COMPLETED UPDATE 失敗は終了コードに反映しない**(業務結果を優先。実行ログに `ERROR management db update failed table=parallel_runs run_id=...`。契約 facade.sh execution_log)

## UC ロジック

- **バリデーション**: `exitcode.txt` が存在し `^[0-9]+$` かつ 0〜255。それ以外は完備違反
- **確認プロンプト**: なし
- **冪等性**: 中継は 1 回。同じ run の中継を再実行する経路は無い(facade の再起動 = 新 run)。COMPLETED 更新は条件付き UPDATE(`status='RUNNING'`)で二重更新しない
- **エラーハンドリング**: 中継前の relay-gate エラー(完備違反)は ui-design.md の 4 分類に従い終了コード 6。中継開始後(stdout を流し始めた後)の read エラーは実行ログに ERROR を残し、終了コードは exitcode.txt の値を維持する(部分的に流れた出力を取り消せないため。仮採用)
- **中継の実装方針**: `cat stdout.log >&1; cat stderr.log >&2; exit "$(cat exitcode.txt)"`。バッファリングの変換・文字コード変換・改行変換をしない。大きなファイルもメモリに読み込まず流す
- **クラッシュ耐性**:
  - 中継中に facade が落ちた場合: ジョブスケジューラには facade の異常終了コード(1 または signal)が伝わる。parallel_runs は RUNNING のまま。運用者は成果物ディレクトリの 3 ファイルで結果を確認し、必要ならジョブスケジューラの正規ジョブを再実行する
  - COMPLETED 更新前に落ちた場合: parallel_runs は RUNNING のまま残る。hang-detector は parallel_runs.status を監視対象の判定に使わず、slot の成果物と依頼状態で判定するため誤通知は発生しない
- **実行ログ**: `relay started run_id=... role=blue exit_code=0 stdout_bytes=... stderr_bytes=...` / `relay finished run_id=... duration_ms=...` / `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=...`(on)/ `ERROR management db update failed table=parallel_runs run_id=...`(中継後の COMPLETED UPDATE 失敗。終了コードは変えない)
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## 設定契約

追加の設定は無い。`RAPID_CROSSCHECK_MODE` を feature flag から読む(前 UC で読み込み済みの値を使う)。

## データモデル変更

### parallel_runs(on のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING → COMPLETED | 追加 |
| completed_at | datetime | 中継完了日時(UTC) | 追加 |

### ファイル(読み込み)

| ファイル | 説明 |
|---|---|
| `facade/<run_id>/<fg_role>/stdout.log` | 標準出力へ |
| `facade/<run_id>/<fg_role>/stderr.log` | 標準エラーへ |
| `facade/<run_id>/<fg_role>/exitcode.txt` | 終了コードへ |

## ビジネスルール

- ジョブスケジューラへ返す標準出力・標準エラー・終了コードは foreground の 3 ファイルをそのまま中継したもの。background と速報の結果は反映しない。中継完了で並行稼働実行を COMPLETED にする(条件: ジョブスケジューラ応答の決定)
- 速報の exitcode や失敗を業務ジョブの結果として返さない(条件: 速報結果の位置付け)
- 応答は CLI の 3 チャネルだけ(条件: CLI とメールによる提示)
- off では管理 DB に触れない(条件: 速報クロスチェック有効判定)

## ティア完了条件(BDD)

```gherkin
Feature: foreground slot の結果をジョブスケジューラへ中継する - facade / slot runner ティア

  Scenario: facade_sh は stdout.log / stderr.log / exitcode.txt をバイト単位で無加工中継する
    Given スタブ runner が blue/stdout.log に "line1\nline2"(末尾改行なし)、stderr.log に "e1\n"、exitcode.txt に "3\n" を書いて終了コード 3 で終了する
    And feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=off がある
    When `facade.sh JOB001` を実行し stdout と stderr をそれぞれファイルに保存する
    Then 終了コード 3 で終了する
    And 保存した stdout は blue/stdout.log と cmp で一致する
    And 保存した stderr は blue/stderr.log と cmp で一致する

  Scenario: facade_sh はバイナリを含む stdout.log を変換しない
    Given スタブ runner が blue/stdout.log に 0x00 と 0xFF を含む 1 MB のデータを書く
    When `facade.sh JOB001` を実行する
    Then 保存した stdout の sha256 は blue/stdout.log と一致する

  Scenario: facade_sh は exitcode.txt が無いと終了コード 6 で終了する
    Given スタブ runner が blue/started-at.txt だけを書いて終了コード 1 で終了する
    When `facade.sh JOB001` を実行する
    Then 終了コード 6 で stderr に "error: foreground runner result incomplete run_id=<run_id> role=blue" が出る

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=on で中継後に parallel_runs を COMPLETED にする
    Given 管理 DB が起動しており feature-flag.env に RAPID_CROSSCHECK_MODE=on がある
    When `facade.sh JOB001` を実行する
    Then parallel_runs の run_id の行は status=COMPLETED で completed_at が設定されている
    And 実行ログに "parallel_run status changed from=RUNNING to=COMPLETED" が出る

  Scenario: facade_sh は parallel_runs の更新に失敗しても exitcode.txt の値で終了する
    Given RAPID_CROSSCHECK_MODE=on で、中継後に管理 DB が停止している
    And スタブ runner は exitcode.txt に 0 を書く
    When `facade.sh JOB001` を実行する
    Then 終了コード 0 で終了し、実行ログに "ERROR management db update failed table=parallel_runs run_id=<run_id>" が出る
```
