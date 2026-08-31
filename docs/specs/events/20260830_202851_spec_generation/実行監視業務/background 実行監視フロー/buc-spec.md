# background 実行監視フロー

## 概要

ジョブスケジューラのジョブステータスに現れない background slot 実行と速報比較依頼の異常(ハング疑い / background 実行エラー / 速報クロスチェック異常)を、定期起動のハング検知スクリプトが判定・通知・記録し、運用者がメールで受け取って対処を判断する BUC。監視は通知のみで、状態変更・プロセス停止・再実行は行わない(対処は実行中止フロー / background 側リランフローに委ねる)。監視記録に残る警告時経過時間を根拠に、運用者がジョブごとの `hang_detect_limit_minutes` を調整する運用改善のループまでを含む。

## 所属 UC 一覧

| UC名 | アクター | 主な操作 | 関連情報 |
|------|---------|---------|---------|
| [background 実行の経過時間と終了状態を判定する](background%20実行の経過時間と終了状態を判定する/spec.md) | ジョブスケジューラ(定期ジョブ)/ 運用者(受益者) | 成果物ディレクトリと未終端の速報比較依頼を走査し、exitcode.txt の有無・値と経過時間から判定する | slot 実行、Runner Result、実行設定(execution-spec)、ハング検知上限設定、速報比較依頼、監視記録 |
| [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) | 運用者(受益者) | 判定結果を warning / error のメールとして 1 回だけ送信する | 監視記録、通知メール、slot 実行、速報比較依頼 |
| [監視記録を保存する](監視記録を保存する/spec.md) | 運用者(受益者) | 判定と送信結果を monitor_records へ UPSERT し、警告時経過時間を保持する | 監視記録、実行ログ |
| [background 異常の通知メールを受け取る](background%20異常の通知メールを受け取る/spec.md) | 運用者 | メールの件名・本文から重要度と種別を読み、静観 / 中止 / リランを判断する | 通知メール、監視記録 |
| [hang_detect_limit_minutes をジョブごとに調整する](hang_detect_limit_minutes%20をジョブごとに調整する/spec.md) | 運用者 | 警告傾向を参照し、slot ジョブマップの hang_detect_limit_minutes をジョブごとに調整する | 監視記録、ハング検知上限設定、ジョブマップ、実行設定(execution-spec) |

判定 / 通知 / 記録の 3 UC は、ハング検知スクリプトの 1 回の実行(5 分ごと)を構成する。受信と調整の 2 UC は運用者が行う。

## UC 横断データフロー

BUC 内の UC 間で情報がどう流れるかを示す。情報がどの UC で作成(C)・参照(R)・更新(U)されるかを明記する。

### データフロー図

```mermaid
graph LR
  subgraph EXT["BUC 外(入力)"]
    RUN["slot 実行 / Runner Result\n(started-at.txt / exitcode.txt)"]
    SPEC["実行設定(execution-spec)\nrole ごとの hang_detect_limit_minutes"]
    REQ["速報比較依頼\n(status / 比較結果)"]
  end
  JUDGE["background 実行の経過時間と\n終了状態を判定する"]
  NOTIFY["ハング疑い・実行エラー・\n比較異常を通知する"]
  RECORD["監視記録を保存する"]
  RECEIVE["background 異常の\n通知メールを受け取る"]
  TUNE["hang_detect_limit_minutes を\nジョブごとに調整する"]
  MAP["ジョブマップ\n(hang_detect_limit_minutes 列)"]
  RUN --> JUDGE
  SPEC --> JUDGE
  REQ --> JUDGE
  RECORD -->|"監視記録(現在の monitor_status)"| JUDGE
  JUDGE -->|"判定結果(run_id, role, judgement)"| NOTIFY
  JUDGE -->|"判定結果(全件)"| RECORD
  NOTIFY -->|"送信結果(next_status, alerted_at, 警告時経過時間)"| RECORD
  NOTIFY -->|"通知メール(warning / error)"| RECEIVE
  RECORD -->|"監視記録(警告傾向)"| TUNE
  TUNE -->|"ハング検知上限設定"| MAP
  MAP -->|"次回以降の run の実行設定"| SPEC
  RECEIVE -.->|"対処判断(中止 / リラン)"| OUT["実行中止フロー /\nbackground 側リランフロー"]
```

### 情報 CRUD マトリクス

分母は BUC.tsv でこの BUC に紐づく 9 情報。列見出しは以下の略記表に従う。

| 略記 | UC名 |
|------|------|
| 判定 | background 実行の経過時間と終了状態を判定する |
| 通知 | ハング疑い・実行エラー・比較異常を通知する |
| 記録 | 監視記録を保存する |
| 受信 | background 異常の通知メールを受け取る |
| 調整 | hang_detect_limit_minutes をジョブごとに調整する |

| 情報名 | 判定 | 通知 | 記録 | 受信 | 調整 |
|--------|:----:|:----:|:----:|:----:|:----:|
| slot 実行 | R(on: slot_executions.status の ABORTED 判定) | - | - | - | - |
| Runner Result | R | - | - | - | - |
| 実行設定(execution-spec) | R | - | - | - | R |
| ハング検知上限設定 | R | - | - | - | U |
| 速報比較依頼(rapid_crosscheck_request) | R | - | - | - | - |
| 監視記録 | R | R | C / U | R | R |
| 通知メール | - | C | - | R | - |
| 実行ログ | C | C | C | - | - |
| ジョブマップ | - | - | - | - | U |

補足:

- 監視記録の作成・更新は「記録」UC に集約する。「判定」「通知」は現在の monitor_status を読むだけで書かない(冪等判定と遷移先の決定に使う)。
- 「通知」UC は slot 実行・速報比較依頼を直接読まない(判定 UC から受け取った判定結果と monitor_records だけを入力にする。BUC.tsv 上の紐づけは「判定 UC 経由」と読み替える)。
- 「判定」UC の slot 実行 R は RAPID_CROSSCHECK_MODE=on のときだけ(off では slot_executions が無く、成果物ファイルのみで判定する)。
- 「調整」UC の U は運用者による slot ジョブマップの編集を指す。管理 DB・execution-spec.json は直接編集しない(設定所有区分)。
- 実行ログは BUC.tsv 上「記録」のみに紐づくが、「判定」「通知」の spec も `judged` / `alert sent` 行を追記する。

## 状態遷移全体図

BUC 内で関連する状態モデルは「監視状態」(実行監視管理)の 1 つ。状態.tsv の 8 遷移すべてをこの BUC の UC が担当する。加えて、ハング疑い通知済み → 比較異常通知済み(速報比較依頼が warning 通知後に FAILED / 比較 NG で終端したとき)と、運用者が中止した対象(on で slot_executions / 依頼が ABORTED)を正常終了(COMPLETED)で終端する遷移は状態.tsv に無い遷移として本 spec で仮採用する(rdra-feedback 対象)。判定結果(hang_judgement)は NOT_TARGET / COMPLETED / EXEC_ERROR / MONITORING / HANG_SUSPECTED / COMPARE_ERROR の 6 値で、監視状態と 1:1 に写像する。ハング疑い通知済みは終端ではなく、次回以降の定期ジョブでも走査・再判定する。slot 実行 / クロスチェック依頼 / 並行稼働実行の状態は、この BUC ではいっさい変更しない(監視は通知のみ)。

```mermaid
stateDiagram-v2
  state "監視対象外(NOT_MONITORED)" as NOT_MONITORED
  state "監視中(MONITORING)" as MONITORING
  state "ハング疑い通知済み(HANG_SUSPECTED_NOTIFIED)" as HANG
  state "実行エラー通知済み(EXEC_ERROR_NOTIFIED)" as EXEC
  state "比較異常通知済み(COMPARE_ERROR_NOTIFIED)" as COMPARE
  state "正常終了(COMPLETED)" as COMPLETED
  [*] --> NOT_MONITORED: background 実行の経過時間と終了状態を判定する(foreground または limit=0)
  [*] --> MONITORING: background 実行の経過時間と終了状態を判定する(limit>0・exitcode 未出力・上限以内)
  MONITORING --> HANG: ハング疑い・実行エラー・比較異常を通知する(上限超過・warning 送信)
  MONITORING --> EXEC: ハング疑い・実行エラー・比較異常を通知する(exitcode 非 0・error 送信)
  MONITORING --> COMPARE: ハング疑い・実行エラー・比較異常を通知する(依頼 FAILED / 比較 NG・error 送信)
  MONITORING --> COMPLETED: background 実行の経過時間と終了状態を判定する(exitcode 0、または on で中止済み ABORTED)
  HANG --> COMPLETED: background 実行の経過時間と終了状態を判定する(通知後に exitcode 0、または通知後に中止済み ABORTED)
  HANG --> EXEC: ハング疑い・実行エラー・比較異常を通知する(通知後に exitcode 非 0・追加 error 送信)
  HANG --> COMPARE: ハング疑い・実行エラー・比較異常を通知する(通知後に依頼 FAILED / 比較 NG・追加 error 送信。状態.tsv に無い仮採用)
  NOT_MONITORED --> [*]
  COMPLETED --> [*]
  EXEC --> [*]
  COMPARE --> [*]
```

### 状態遷移 UC マッピング

| 状態モデル | 遷移元 | 遷移先 | 担当 UC |
|-----------|--------|--------|--------|
| 監視状態 | `[*]` | 監視対象外 | [background 実行の経過時間と終了状態を判定する](background%20実行の経過時間と終了状態を判定する/spec.md) |
| 監視状態 | `[*]` | 監視中 | [background 実行の経過時間と終了状態を判定する](background%20実行の経過時間と終了状態を判定する/spec.md) |
| 監視状態 | 監視中 | ハング疑い通知済み | [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) |
| 監視状態 | 監視中 | 実行エラー通知済み | [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) |
| 監視状態 | 監視中 | 比較異常通知済み | [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) |
| 監視状態 | 監視中 | 正常終了 | [background 実行の経過時間と終了状態を判定する](background%20実行の経過時間と終了状態を判定する/spec.md) |
| 監視状態 | ハング疑い通知済み | 正常終了 | [background 実行の経過時間と終了状態を判定する](background%20実行の経過時間と終了状態を判定する/spec.md) |
| 監視状態 | ハング疑い通知済み | 実行エラー通知済み | [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) |
| 監視状態 | ハング疑い通知済み | 比較異常通知済み(状態.tsv に無い仮採用) | [ハング疑い・実行エラー・比較異常を通知する](ハング疑い・実行エラー・比較異常を通知する/spec.md) |

すべての遷移結果は [監視記録を保存する](監視記録を保存する/spec.md) が monitor_records へ永続化する(遷移の判定はしない)。[background 異常の通知メールを受け取る](background%20異常の通知メールを受け取る/spec.md) と [hang_detect_limit_minutes をジョブごとに調整する](hang_detect_limit_minutes%20をジョブごとに調整する/spec.md) は状態を変更しない。

## BUC 内共有条件一覧

BUC 内の複数 UC で共有される条件の一覧。適用 UC は BUC.tsv の紐づけを正とし、spec 側でのみ参照する UC は括弧で補足する。

| 条件名 | 条件の説明 | 適用 UC |
|--------|----------|--------|
| 監視は通知のみ | ハング検知は RUNNING を ABORTED へ変更せず、実行プロセスを停止せず、新しい実行依頼を作成しない。自動中止・自動再実行は行わない | 通知メールを受け取る, 異常を通知する, 監視記録を保存する |
| 通知レベルの判定 | ハング疑いは warning、background 実行エラーと速報クロスチェック異常は error のメールとする。件名 `[relay-gate][{level}] {kind} run_id= job_id= role=` で運用者が重要度と種別を判別する | 通知メールを受け取る, 異常を通知する |
| 速報比較依頼の異常判定 | 速報比較依頼が FAILED または比較 NG なら速報クロスチェック異常として通知する。RUNNING で上限超過は状態を変更せずハング疑いとして通知する | 経過時間と終了状態を判定する, 異常を通知する |
| ハング検知対象の除外 | hang_detect_limit_minutes が 0 の role と foreground role は検知対象外(NOT_MONITORED)。傾向集計の run_count からも除外する | 経過時間と終了状態を判定する, hang_detect_limit_minutes を調整する |
| 速報クロスチェック有効判定 | RAPID_CROSSCHECK_MODE=off では管理 DB に接続しない。判定は成果物走査のみ、記録は実行ログのみ、傾向参照は終了コード 3 で終了する | 経過時間と終了状態を判定する(spec では 異常を通知する, 監視記録を保存する, hang_detect_limit_minutes を調整する も参照) |

## BUC 内共有バリエーション一覧

BUC 内の複数 UC で共有されるバリエーションの一覧(各 UC spec のバリエーション一覧を集約)。

| バリエーション名 | 値 | 適用 UC |
|----------------|---|--------|
| ハング検知判定結果 | 対象外(正常終了)、background 実行エラー、継続監視、ハング疑い(spec の hang_judgement は NOT_TARGET / COMPLETED / EXEC_ERROR / MONITORING / HANG_SUSPECTED / COMPARE_ERROR の 6 値。監視対象外 NOT_TARGET と正常終了 COMPLETED を分ける。rdra-feedback 対象) | 経過時間と終了状態を判定する, 異常を通知する, 監視記録を保存する, 通知メールを受け取る |
| 速報クロスチェック監視判定 | 速報クロスチェック異常(FAILED / 比較 NG)、ハング疑い(RUNNING 継続)、正常 | 経過時間と終了状態を判定する, 異常を通知する, 監視記録を保存する, 通知メールを受け取る |
| 通知レベル | warning、error | 異常を通知する, 通知メールを受け取る |
| run role(成果物ディレクトリ区分) | blue、green、rapid-crosscheck、final-crosscheck(final-crosscheck は走査対象外) | 経過時間と終了状態を判定する, 異常を通知する, 監視記録を保存する, 通知メールを受け取る, hang_detect_limit_minutes を調整する |
| ハング検知上限設定 | 60 分(導入時既定)、ジョブごとの調整値、0(検知対象外) | 経過時間と終了状態を判定する, 監視記録を保存する, hang_detect_limit_minutes を調整する |
| 速報クロスチェックモード | on、off | 経過時間と終了状態を判定する, 異常を通知する, 監視記録を保存する |
| 監視状態 | 未検知、ハング疑い、通知済み、通知後正常終了(monitor_status への対応は「監視記録を保存する」を参照) | 異常を通知する, 監視記録を保存する, hang_detect_limit_minutes を調整する |
