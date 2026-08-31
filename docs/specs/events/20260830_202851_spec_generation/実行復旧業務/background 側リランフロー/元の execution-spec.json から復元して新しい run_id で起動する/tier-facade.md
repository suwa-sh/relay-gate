# 元の execution-spec.json から復元して新しい run_id で起動する - facade / slot runner ティア仕様

## 変更概要

slot runner IF(`$BLUE_RUNNER` / `$GREEN_RUNNER`)の **`--execution-spec <path>` 入力モード**を本 UC がどう使うかを定める。runner IF そのもの(オプション集合・終了コード・Runner Result)の定義元は UC「slot runner の実体スクリプトを割り当てる」(適用構成業務)であり、本 UC は `uses` 側として `--execution-spec` 指定時の振る舞いを規定する。指定時は実行先の解決元を execution-spec.json に固定し、ジョブマップを読まない。runner の他の振る舞い(started-at.txt / Runner Result の出力、完了通知)は通常起動と同一である(他 UC「実装スクリプトを実行して Runner Result を出力する」「速報クロスチェック runner へ完了通知を送信する」)。

## コマンド契約

### slot runner IF(`$BLUE_RUNNER` / `$GREEN_RUNNER`)— execution-spec 入力モード

- **書式**: `<runner> --run-id <RUN_ID> --job-id <JOB_ID> --role blue|green --mode background --execution-spec <path>`
- **アクセス権**: 内部呼び出し(`background-rerun.sh`)。運用者は直接起動しない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--run-id` | string | Yes | なし | 新 run_id。execution-spec.json の `run_id` と一致しなければ終了コード 2 |
| `--job-id` | string | Yes | なし | JOB_ID。execution-spec.json の `job_id` と一致しなければ終了コード 2 |
| `--role` | enum(blue / green) | Yes | なし | runner 自身の系統。spec の `slots.{role}` を使う |
| `--mode` | enum(foreground / background) | Yes | なし | リランでは `background` のみ(background-rerun が渡す)。`foreground` を渡した場合も runner は動作するが、本 UC の経路では使わない |
| `--execution-spec` | string(パス) | No(指定時に入力モード切替) | なし | 実行設定の正本。指定時はジョブマップを読まず、`--` 以降の PARAM も受け付けない(渡されたら終了コード 2) |

- **stdin**: なし

## 出力契約

- **stdout / stderr**: runner 自身の stdout / stderr は空(実装の出力は `facade/<run_id>/<role>/stdout.log` / `stderr.log` へ)。runner 自身のエラー(SSH 失敗・spec 不整合・PARAM 併用)は runner プロセスの stderr ではなく `facade/<run_id>/<role>/stderr.log` の末尾に `error:` 1 行として残す(契約 `$BLUE_RUNNER / $GREEN_RUNNER` の stderr 規約と同じ。background-rerun は非同期起動のため runner の stderr を読まない)
- **成果物**: `facade/<run_id>/<role>/{started-at.txt, stdout.log, stderr.log, exitcode.txt}`(Runner Result Contract。一時ファイル → mv)。`execution-spec.json` は **読むだけで書かない**(background-rerun が作成済み)
- **終了コード**(runner プロセス自身。background-rerun は待たない):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 実装スクリプトが終了コード 0(exitcode.txt=0) |
  | 2 | 入力エラー | `--execution-spec` のファイルが無い / 読めない / run_id・job_id 不一致 / PARAM が渡された |
  | 6 | 実行エラー | SSH 接続失敗、成果物書き込み失敗。可能な限り exitcode.txt に 6 と stderr.log に理由を残す |
  | その他 | 実装の終了コード | 実装スクリプトの終了コードをそのまま(exitcode.txt と一致) |

## UC ロジック

- **入力モード判定(presentation)**: `--execution-spec` が指定されていればジョブマップ解決(usecase「実行先の解決」)をスキップし、spec 読み取りへ進む。未指定なら通常起動(ジョブマップ解決 + execution-spec.json 確定保存)
- **spec の検証**: `run_id` / `job_id` が引数と一致すること、`slots.{role}` に host / exec_user / script_path / work_dir / fixed_args / hang_detect_limit_minutes / credential_ref があること。不一致・欠落は 2(exitcode.txt=2 と stderr.log も出す)
- **実行**: spec の `slots.{role}` の値で SSH 実行。引数は `fixed_args` の後ろに spec の `params` を順序を変えずに連結(条件「引数連結規則」と同じ。ジョブスケジューラからの PARAM は受け取らない)
- **確認プロンプト**: なし
- **冪等性**: 同じ `--run-id` で 2 回起動しない前提(background-rerun が新 run_id を発行する)。`started-at.txt` が既に存在する場合は二重起動として 2 で終了する
- **エラーハンドリング**: 通常起動と同一(LP-007。異常時も 3 ファイルを揃える)
- **クラッシュ耐性**: started-at.txt 出力後に落ちた場合、exitcode.txt が無いため hang-detector が上限超過でハング疑いとして通知する。運用者が abort → 再リランで復旧する

## 設定契約

- feature flag `BLUE_RUNNER` / `GREEN_RUNNER` の実体が `--execution-spec` を受け付けること(runner IF の必須オプション。`validate-config.sh --feature-flag` は実体の存在・実行権限を検証するが、オプション対応は runner 実体の実装契約とする)
- ジョブマップは読まない(`RELAY_GATE_CONFIG_DIR` のジョブマップが変更・削除されていても影響しない)

## データモデル変更

### execution-spec.json(読み取りのみ)

| キー | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 引数 `--run-id` と一致必須 | 追加(参照) |
| parent_run_id / restored_at | string / datetime | リラン由来(runner は使わない) | 追加(参照) |
| job_id | string | 引数 `--job-id` と一致必須 | 追加(参照) |
| slots.{role}.host / exec_user / script_path / work_dir | string | 実行先 | 追加(参照) |
| slots.{role}.fixed_args | JSON 配列 | 固定引数(slot 単位) | 追加(参照) |
| params | JSON 配列 | ジョブスケジューラから渡された追加引数(run 単位。fixed_args の後ろに順序を変えずに連結) | 追加(参照) |
| slots.{role}.hang_detect_limit_minutes | integer | hang-detector が読む(runner は使わない) | 追加(参照) |
| slots.{role}.credential_ref | string | 認証情報の参照名 | 追加(参照) |

### Runner Result(ファイル。書き込み)

| ファイル | 説明 | 変更種別 |
|---|---|---|
| `facade/<run_id>/<role>/started-at.txt` | 起動時刻(UTC ISO 8601) | 追加 |
| `facade/<run_id>/<role>/stdout.log` / `stderr.log` / `exitcode.txt` | Runner Result Contract | 追加 |

## ビジネスルール

- `--execution-spec` 指定時はジョブマップを再解決しない(条件「リランの実行設定復元」)
- Runner Result の 3 ファイルは異常時も可能な限り揃える(条件「Runner Result 完備条件」、LP-007)
- 成果物は一時ファイル → リネーム(条件「成果物公開判定」)
- 完了通知(blue-completed / green-completed)は RAPID_CROSSCHECK_MODE=on のときだけ送る(条件「速報クロスチェック有効判定」。他 UC)

## ティア完了条件(BDD)

```gherkin
Feature: 元の execution-spec.json から復元して新しい run_id で起動する - facade / slot runner ティア

  Scenario: --execution-spec 指定時はジョブマップを読まない
    Given /var/relay-gate/facade/20260830T124500Z-JOB001-7b2d9e01/execution-spec.json が run_id=20260830T124500Z-JOB001-7b2d9e01 job_id=JOB001 green.script_path=/opt/app/v1/batch.sh で存在する
    And green slot ジョブマップの JOB001 行の script_path は /opt/app/v2/batch.sh である
    When `$GREEN_RUNNER --run-id 20260830T124500Z-JOB001-7b2d9e01 --job-id JOB001 --role green --mode background --execution-spec /var/relay-gate/facade/20260830T124500Z-JOB001-7b2d9e01/execution-spec.json` を実行する
    Then リモート実行ホストで /opt/app/v1/batch.sh が実行され、facade/20260830T124500Z-JOB001-7b2d9e01/green/ に started-at.txt / stdout.log / stderr.log / exitcode.txt が揃う
    And ジョブマップファイルは開かれない

  Scenario: run_id 不一致は終了コード 2
    Given execution-spec.json の run_id が 20260830T113000Z-JOB001-3f9a1c2e である
    When `$GREEN_RUNNER --run-id 20260830T124500Z-JOB001-7b2d9e01 --job-id JOB001 --role green --mode background --execution-spec {そのパス}` を実行する
    Then 終了コード 2 で facade/20260830T124500Z-JOB001-7b2d9e01/green/stderr.log の末尾に `error: execution-spec run_id mismatch arg=20260830T124500Z-JOB001-7b2d9e01 spec=20260830T113000Z-JOB001-3f9a1c2e` が残る
    And facade/20260830T124500Z-JOB001-7b2d9e01/green/exitcode.txt の中身が 2 である

  Scenario: --execution-spec と PARAM の併用は拒否する
    When `$GREEN_RUNNER --run-id 20260830T124500Z-JOB001-7b2d9e01 --job-id JOB001 --role green --mode background --execution-spec {パス} -- 20260830` を実行する
    Then 終了コード 2 で facade/20260830T124500Z-JOB001-7b2d9e01/green/stderr.log の末尾に `error: params are not accepted with --execution-spec` が残り、exitcode.txt の中身が 2 である
```
