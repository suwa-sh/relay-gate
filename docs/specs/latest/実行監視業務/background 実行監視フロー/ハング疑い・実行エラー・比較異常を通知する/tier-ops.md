# ハング疑い・実行エラー・比較異常を通知する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detector.sh` の通知部分を追加する。
usecase は、対象の並べ替え → 再通知の要否の判定 → alert 行の出力 → 記録 UC の呼び出しまたは通知済みの印の保存 → 終了コードの決定を行う。
domain は、通知レベル対応表・再通知しない規則・終了コードの決定を持つ。
repository は、現在の通知済み状態(monitor_records または通知済みの印)を読み、off では印を書く。
コマンド契約(引数・設定・終了コード表)は UC「background 実行の経過時間と終了状態を判定する」の tier 仕様を正とし、このファイルは alert 行・再通知しない規則・通知済みの印の UC 側の処理を定義する。行形式・再通知の規則・印の置き場と書き方の共通の正本は CLI 契約 `shared_rules.hang_alert` である。

## コマンド契約

### hang-detector.sh(通知部分)

- **書式**: `hang-detector.sh [--verbose] [--help]`(UC「background 実行の経過時間と終了状態を判定する」を参照)
- **アクセス権**: ジョブスケジューラのハング検知定期ジョブ。off では成果物ルート直下の `hang-detector-notified/` への書き込み権限
- **トリガー**: 同 UC の判定結果(全件。新たに知らせるのは EXEC_ERROR / HANG_SUSPECTED / COMPARE_ERROR のうち未通知のもの)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 通知の有無はオプションで制御しない(dry-run は提供しない) |

- **stdin**: なし
- **設定**: 通知のための設定キーは無い。hang-detector.env のキーは判定 UC の設定契約のとおり(HANG_DB_CONN_REF / RAPID_HANG_DETECT_LIMIT_MINUTES / HANG_SCAN_WINDOW_HOURS)

## 出力契約

- **stdout**: 出力しない
- **stderr**:
  | 行 | 出す条件 | 例 |
  |---|---|---|
  | `alert: level=<warning\|error> kind=<kind> run_id=<run_id> role=<role> job_id=<job_id> elapsed_minutes=<n>` | その回に新たに知らせる異常 1 件につき 1 行 | `alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=blue job_id=JOB001 elapsed_minutes=75` |
  | `error: notified mark invalid run_id=<run_id> role=<role> path: <印の確定名の絶対パス>` | off で、窓内の対象の印の内容が規定の値(英字コード 1 つ + LF)でない、または読めない(その対象の alert 行より前に出す) | `error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=green path: /var/relay-gate/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green` |
  | `error: monitor record save failed run_id=<run_id> role=<role>` | off 以外で、alert 行を出した対象の監視記録の UPSERT に失敗した(記録 UC。alert 行の直後に出す) | `error: monitor record save failed run_id=20260830T113000-JOB001-3f9a1c2e role=green` |
  | `error: notified mark save failed run_id=<run_id> role=<role> path: <印の確定名の絶対パス>` | off で、通知済みの印の保存に失敗した(alert 行の直後に出す) | `error: notified mark save failed run_id=20260830T113000-JOB001-3f9a1c2e role=green path: /var/relay-gate/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green` |
  | `info: alert skipped already notified run_id=<run_id> role=<role> status=<現在の通知済み状態>` | `--verbose` 時だけ。判定は異常だが通知済みのため知らせなかった | — |
- **alert 行の項目**:
  | 項目 | 値 |
  |---|---|
  | level | hang-suspected は `warning`。background-exec-error / rapid-crosscheck-error は `error` |
  | kind | `hang-suspected` / `background-exec-error` / `rapid-crosscheck-error`(判定結果 HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR に対応) |
  | run_id / role | 対象。background slot は role=blue / green、速報比較依頼は role=rapid-crosscheck |
  | job_id | background slot は execution-spec.json の job_id、速報比較依頼は依頼の job_id |
  | elapsed_minutes | 判定時点の started_at からの経過分(判定 UC の計算ルール。CLI 契約 `shared_rules.time_precision`) |
- **並び順**: 対象ごとの行は run_id 昇順(バイト順)→ role(blue, green, rapid-crosscheck)。1 つの対象の中は「`error: notified mark invalid` → `alert:`(または `info: alert skipped`)→ `error: monitor record save failed` / `error: notified mark save failed`」の順(契約 `shared_rules.hang_alert.order`)。判定 UC の走査の warn 行と `info: judged` 行は対象ごとの行より前。hang-detector.env の未知キーの warn 行は判定 UC が走査を始めるときに出し、どの alert 行・対象ごとの行よりも前(判定 UC の「未知キーの warn を出す時点」。契約 `shared_rules.hang_alert.unknown_key_warn`)
- alert 行は CLI 契約 `conventions.output_format.stderr` の例外として契約に明記された行形式であり、`error:` / `warn:` の行と同じ標準エラーに出す。対象ごとの error 行(印の不正・保存失敗)も同じ例外として 1 対象 1 行で複数出してよい
- **終了コード**: 判定 UC の終了コード表に従う。この UC が決めるのは、新たに知らせた異常の段階(error が 1 行以上 → 6、warning だけ → 3、無し → 0)と、印の不正・保存失敗による 6
- **実行ログ**(`RELAY_GATE_LOG_DIR/hang-detector.sh.log`): `INFO alert level=... kind=... run_id=... role=... job_id=... elapsed_minutes=...`(stderr の alert 行と同じ項目)/ `INFO alert skipped already notified run_id=... role=... status=...` / `ERROR notified mark invalid run_id=... role=... path: ...` / `ERROR monitor record save failed run_id=... role=...` / `ERROR notified mark save failed run_id=... role=... path: ...`
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル出力日時} {LEVEL} {message}`)に従う

## UC ロジック

- **設定ファイルの読み込み**: 判定 UC と同じ(CLI 契約 `config_input_rules` に従う)。stdout / stderr / 実行ログに出す任意入力の制御文字は `ui-design.md`「制御文字の表記」の可視表記にする
- **バリデーション**: なし(入力は同一プロセス内の判定結果)
- **確認プロンプト**: なし
- **処理手順**:
  1. 判定 UC から全判定結果を受け取り、run_id 昇順 → role(blue, green, rapid-crosscheck)に並べる
  2. 対象ごとに、判定結果を CLI 契約 `shared_rules.state_codes.hang_judgement_to_monitor_status` で写した値 S と、現在の通知済み状態 C を求める(off で印が不正・読めなければ、ここで `error: notified mark invalid ...` を出し、C=MONITORING とする)
  3. 下の「再通知しない規則」で知らせると決まった対象だけ、alert 行を 1 行出す
  4. alert 行を出した直後に、その対象の通知済み状態を保存する(off 以外は記録 UC の UPSERT、off は通知済みの印)。保存に失敗したら error 行を出し、終了コード 6 を予約して次の対象へ進む
  5. 知らせない対象も記録 UC へ渡す(off 以外は判定値の UPSERT、off は実行ログ)。off で印が HANG_SUSPECTED_NOTIFIED、または不正・読めない対象の判定が COMPLETED(正常終了・中止済み)なら、alert 行を出さずに印を COMPLETED へ書き換える(保存失敗の扱いは手順 4 と同じ)
  6. 全対象を終えてから終了コードを決める
- **再通知しない規則**:
  | 項目 | 内容 |
  |---|---|
  | 知らせる条件 | S が HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED のいずれかで、S ≠ C、かつ C が終端(EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED / NOT_MONITORED)でない |
  | C の出所(off 以外) | `monitor_records.monitor_status`(判定 UC が走査の前に SELECT した行)。行が無ければ MONITORING 扱い。管理 DB に接続・SELECT できない回は C を読めないため、判定 UC が走査せずに error 1 行と終了コード 6 で終え、この UC は動かない(alert 行を出さない。`error: monitor record save failed` も出さない)。異常は通知済みにならないので、接続できた最初の回にこの規則で一度だけ知らせる(契約 `shared_rules.hang_alert.db_unavailable`) |
  | C の出所(off) | 通知済みの印の中身。印が無ければ MONITORING 扱い。印の内容が規定の値でない・読めなければ `error: notified mark invalid ...` を出して MONITORING 扱い(下の「通知済みの印」の「不正・読めない」) |
  | 結果の例 | C=MONITORING・S=HANG_SUSPECTED_NOTIFIED → 知らせる / C=HANG_SUSPECTED_NOTIFIED・S=HANG_SUSPECTED_NOTIFIED → 知らせない / C=HANG_SUSPECTED_NOTIFIED・S=EXEC_ERROR_NOTIFIED → 知らせる / C=EXEC_ERROR_NOTIFIED・S=EXEC_ERROR_NOTIFIED → 知らせない |
  - 監視記録の alerted_at は記録用であり、再通知の判定には使わない
- **通知済みの印**(off のときだけ hang-detector が書く。管理 DB の監視記録の代わり):
  | 項目 | 内容 |
  |---|---|
  | 置き場 | `$RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/`(`facade/` と並ぶ成果物ルート直下のディレクトリ)。無ければ作る |
  | ファイル名 | `<run_id>.<role>`(role は blue / green。off では速報比較依頼が無い) |
  | 内容 | 通知済み状態の英字コード 1 行 + LF(HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED。COMPLETED はハング疑いを知らせたあとで対象が正常終了・中止した終端)。規定の値 = この 3 つのどれか + LF 1 つと完全に一致するバイト列 |
  | 不正・読めない | 確定名の印があるのに、内容が規定の値でない(空、末尾の LF が無い、CR・空白を含む、2 行以上、3 つ以外の英字コード)、または読めない(権限が無い、通常のファイルでない、読み取りの失敗)。窓内の対象なら `error: notified mark invalid run_id=... role=... path: ...` を 1 行出し(文言は内容の不正と読めないで同じ。内容は出さない)、C を MONITORING として判定を続け、終了コード 6。alert 行を出した対象は S へ、判定が COMPLETED の対象は COMPLETED へ、下の「書き方」で書き直す。判定が MONITORING / NOT_TARGET の対象は書き換えず、次の回も同じ error 行を出す。窓外の run の印の不正は判定 UC が印の無いものとして扱い、走査しないため error 行も出ない(契約 `shared_rules.hang_alert.notified_mark.invalid` / `scan_window`) |
  | 書き方 | 同じ置き場の `<run_id>.<role>.tmp` へ書いてから mv で確定名へ置き換える。読み手は `.tmp` で終わる名前を無視する |
  | 書く契機 | (1) alert 行を出した直後(MONITORING → *_NOTIFIED、HANG_SUSPECTED_NOTIFIED → EXEC_ERROR_NOTIFIED の書き換え、不正・読めない印の書き直しを含む)。(2) 印が HANG_SUSPECTED_NOTIFIED、または不正・読めない対象の判定が COMPLETED(正常終了・中止済み)になったとき。alert 行を出さずに同じ手順で COMPLETED へ書き換えて終端する。(1)(2) 以外では印を書き換えない。印が無い対象が正常終了・中止した場合は印を作らない |
  | 置き換え先が通常のファイルでない | 確定名がディレクトリなど通常のファイルでないときは、その中へ移さず(mv -T 相当。確定名のエントリを消さない)、`error: notified mark save failed ...` を出して終了コード 6。`.tmp` は残さない。印は変わらないので次の回も印の不正として扱う(契約 `notified_mark.write_rule`) |
  | 判定しない対象 | execution-spec.json が無い run、started-at.txt が不正な role、execution-spec.json にキーが無い role の印は読まない(error 行を出さず、書き直さない。契約 `notified_mark.unjudged_targets`) |
  | 置き場を読めない | 判定 UC が `error: notified mark dir is not readable path: ...` の 1 行だけで終了コード 6 で終え、この UC は動かない(契約 `notified_mark.directory_unreadable`) |
  | 触れないもの | Runner Result の契約ファイル(stdout.log / stderr.log / exitcode.txt / execution-spec.json / started-at.txt / aborted.txt)と `facade/` 配下 |
  | 保存失敗 | 置き場の作成・一時ファイルの書き込み・mv のいずれかの失敗。`error: notified mark save failed run_id=... role=... path: ...` を出して終了コード 6。印が変わらないので次回同じ異常を再び知らせる(知らせ漏れより重複)。COMPLETED への書き換えの失敗も同じ行と終了コード 6 で、印が HANG_SUSPECTED_NOTIFIED のまま残るため次回も走査して書き換えをやり直す |
  | 窓外の走査 | 中身が HANG_SUSPECTED_NOTIFIED の印がある run は `HANG_SCAN_WINDOW_HOURS` の窓外でも走査する。中身が EXEC_ERROR_NOTIFIED / COMPLETED の印は終端として扱い、その run を窓外では走査しない(判定 UC の走査手順 2) |
  | 削除 | ハウスキープが保持日数を過ぎた実行の単位とともに削除する(UC「保持日数を過ぎた終了済みの実行と確報比較依頼を判定する」) |
- **管理 DB を使う設定での保存**: alert 行を出したあと、記録 UC が monitor_records を UPSERT する(monitor_status=S、alerted_at=判定時刻)。UPSERT に失敗したら `error: monitor record save failed run_id=... role=...` を出して終了コード 6。monitor_status が変わらないので次回同じ異常を再び知らせる
- **エラーハンドリング**: 印の不正と保存失敗は、それぞれ 1 対象につき error 1 行 + 実行ログ ERROR(1 対象 1 行で複数出してよい。契約 `conventions.output_format.stderr` の例外)。他の対象の判定・alert 行・保存は続け、最後に終了コード 6
- **クラッシュ耐性**: alert 行を出したあと保存前にプロセスが終了した場合、次回同じ異常を再び知らせる(保存されていないため)。重複は「知らせ漏れより重複」として許容し、alert 行の直後に保存することで窓を最小にする
- **監視は通知のみ**: alert 行・印・監視記録以外の副作用を持たない。`abort-*` / `background-rerun` / 依頼 INSERT を呼ばない(LP-017)

## データモデル変更

### monitor_records(参照。更新は UC「監視記録を保存する」)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / role | string | 主キー | 追加(参照) |
| monitor_status | string | 現在の通知済み状態 C | 追加(参照) |

### 成果物ルート(off のみ)

| ファイル | 型 | 説明 | 変更種別 |
|---------|---|------|---------|
| `hang-detector-notified/<run_id>.<role>` | text | 通知済みの印。英字コード 1 行 + LF | 追加 |
| `hang-detector-notified/<run_id>.<role>.tmp` | text | 印の書き込み途中の一時ファイル。mv で確定名へ置き換える | 追加 |

## ビジネスルール

- 通知レベルの判定: ハング疑い = warning、background 実行エラー / 速報クロスチェック異常 = error。新たに知らせる異常が warning だけなら 3、error があれば 6、無ければ 0
- CLI による提示: 知らせ方は終了コードと標準エラーの alert 行だけ。CLI の出力以外の通知手段は持たない
- 再通知しない: 同じ監視対象の同じ通知済み状態は 1 回だけ知らせる。ハング疑い通知後の実行エラー / 速報クロスチェック異常は別の異常として 1 回知らせる
- 保存失敗: alert 行を出したあとで監視記録または印の保存に失敗したら終了コード 6 にし、次回も知らせる
- 速報比較依頼の異常判定: FAILED / 比較 NG → error、RUNNING 上限超過 → warning(状態は変更しない)
- 監視は通知のみ: 状態変更・プロセス停止・依頼作成をしない

## ティア完了条件(BDD)

```gherkin
Feature: ハング疑い・実行エラー・比較異常を通知する - 実行監視・復旧ティア

  Scenario: alert 行を出した直後に監視記録を保存する
    Given RAPID_CROSSCHECK_MODE=background で monitor_records に run_id=20260830T113000-JOB001-3f9a1c2e role=green の行が無く、判定が HANG_SUSPECTED(elapsed_minutes=74)、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh` を実行する
    Then stderr の 1 行目は "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green job_id=JOB001 elapsed_minutes=74" である
    And monitor_records の該当行は monitor_status=HANG_SUSPECTED_NOTIFIED alerted_at=2026-08-30T12:45:00 で、終了コード 3 で終了する

  Scenario: --verbose では通知済みで知らせなかった対象を info 行で示す
    Given 前のシナリオの後、判定が引き続き HANG_SUSPECTED である
    When `hang-detector.sh --verbose` を再実行する
    Then stderr に "info: alert skipped already notified run_id=20260830T113000-JOB001-3f9a1c2e role=green status=HANG_SUSPECTED_NOTIFIED" が出て、"alert:" で始まる行は出ず、終了コード 0 で終了する

  Scenario: off で印を一時ファイルから確定名へ置き換える
    Given RAPID_CROSSCHECK_MODE=off で $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ が無く、20260830T113000-JOB001-3f9a1c2e の green の判定が HANG_SUSPECTED である
    When `hang-detector.sh` を実行する
    Then $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/ が作られ、20260830T113000-JOB001-3f9a1c2e.green の中身は "HANG_SUSPECTED_NOTIFIED" + LF で、20260830T113000-JOB001-3f9a1c2e.green.tmp は残っていない
    And 終了コード 3 で終了する

  Scenario: off でハング疑い通知後の実行エラーは印を書き換える
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green の中身が "HANG_SUSPECTED_NOTIFIED" + LF で、green/exitcode.txt の中身が 1 になった
    When `hang-detector.sh` を実行する
    Then stderr に "alert: level=error kind=background-exec-error run_id=20260830T113000-JOB001-3f9a1c2e role=green" で始まる行が 1 行出て、終了コード 6 で終了する
    And 印の中身は "EXEC_ERROR_NOTIFIED" + LF になる

  Scenario: 印の置き場の .tmp ファイルは通知済み状態として読まない
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/ に 20260830T113000-JOB001-3f9a1c2e.green.tmp(中身 "HANG_SUSPECTED_NOTIFIED")だけがあり、green の判定が HANG_SUSPECTED である
    When `hang-detector.sh` を実行する
    Then 印が無いものとして扱い、stderr に "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green" で始まる行が出て、終了コード 3 で終了する

  Scenario Outline: 規定の値でない印は不正として扱う
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green の内容が <content> で、green の判定が MONITORING(上限以内)である
    When `hang-detector.sh` を実行する
    Then stderr は "error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=green path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green" の 1 行だけで、終了コード 6 で終了する
    And 印の内容は変わらない(判定が MONITORING のため書き直さない)

    Examples:
      | content                                        |
      | 0 バイト(空のファイル)                        |
      | "HANG_SUSPECTED_NOTIFIED"(末尾の LF なし)     |
      | "HANG_SUSPECTED_NOTIFIED" + CR + LF            |
      | " COMPLETED" + LF(先頭に空白)                 |
      | "COMPLETED" + LF + "COMPLETED" + LF(2 行)     |
      | "COMPARE_ERROR_NOTIFIED" + LF                  |

  Scenario: 印の場所がディレクトリなら読めない印として扱う
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green がディレクトリで、green の判定が MONITORING である
    When `hang-detector.sh` を実行する
    Then stderr は "error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=green path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green" の 1 行だけで、終了コード 6 で終了する

  Scenario: 印の場所がディレクトリで知らせる異常があれば、中へ移さずに保存失敗として扱う
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green がディレクトリで、green の判定が HANG_SUSPECTED(elapsed_minutes=74)である
    When `hang-detector.sh` を実行する
    Then stderr は "error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=green path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green" / "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green job_id=JOB001 elapsed_minutes=74" / "error: notified mark save failed run_id=20260830T113000-JOB001-3f9a1c2e role=green path: $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green" の 3 行がこの順に出て、終了コード 6 で終了する
    And 20260830T113000-JOB001-3f9a1c2e.green はディレクトリのままで中に新しいファイルは作られず、hang-detector-notified/ に ".tmp" で終わるファイルは残っていない

  Scenario: 規定の値の印は不正として扱わない
    Given RAPID_CROSSCHECK_MODE=off で hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green の内容が "EXEC_ERROR_NOTIFIED" + LF で、green/exitcode.txt の中身が 1 である
    When `hang-detector.sh` を実行する
    Then stderr に "error:" / "alert:" で始まる行は出ず、終了コード 0 で終了する

  Scenario: 印の不正は対象ごとに 1 行ずつ対象の順に出す
    Given RAPID_CROSSCHECK_MODE=off で、20260830T113000-JOB001-3f9a1c2e の blue と green(どちらも background、上限 60 分、started-at.txt が 2026-08-30T11:30:05Z)がともに exitcode.txt も aborted.txt も無く、RELAY_GATE_NOW=2026-08-30T12:00:00Z(上限以内)である
    And hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.blue と hang-detector-notified/20260830T113000-JOB001-3f9a1c2e.green の内容がどちらも空である
    When `hang-detector.sh` を実行する
    Then stderr は "error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=blue path: ..." と "error: notified mark invalid run_id=20260830T113000-JOB001-3f9a1c2e role=green path: ..." の 2 行がこの順に出て、終了コード 6 で終了する
```
