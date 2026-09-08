# 速報クロスチェックフロー

## 概要

blue / green の slot runner が完了時に系統ごとの公開 function で速報クロスチェック runner(dispatcher)へ完了通知を送り(自 slot の中止状態は判断しない)、runner は rapid_run で両系成功を判定したときに限り速報比較依頼を run_id 主キーで 1 件だけ REQUESTED で作成する(run が中止済み(parallel_runs ABORTED または slot_executions に ABORTED あり。後者は仮採用: rdra-feedback #13)では両系成功でも作成せず、完了事実だけを記録して実行ログに警告を残す)。管理 DB 接続参照名・lease 期間・poll 間隔は基盤適用設計者が所有する速報クロスチェック設定(rapid-crosscheck.env)から読む。速報クロスチェック worker が管理 DB をジョブキューとして claim / lease し、job_id ごとの比較定義に従って比較ツールでジョブ単位比較を非同期に実行して comparison_result を登録する。運用者は結果を run_id で参照して差分の原因を調査する。速報の結果は業務ジョブのジョブスケジューラ応答に影響させず、リリース判断の正本には用いない。

## 所属 UC 一覧

| UC名 | アクター | 主な操作 | 関連情報 |
|------|---------|---------|---------|
| [速報クロスチェック runner へ完了通知を送信する](速報クロスチェック%20runner%20へ完了通知を送信する/spec.md) | 運用者(受益者・操作なし) | slot runner が exitcode.txt 公開直後に feature flag の RAPID_CROSSCHECK_RUNNER が指す速報クロスチェック runner を blue-completed / green-completed で起動し、run_id・job_id・exit_code・artifact_uri を一方向に通知する。受信側が rapid_runs の自系統の列を更新する。RAPID_CROSSCHECK_MODE が off 以外(foreground / background)のときだけ送信し、off では送信しない。自 slot の中止状態(aborted.txt の有無)は判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり送る。送信失敗は自動検知せず実行ログに警告を残す(完了通知失敗の扱い) | 完了通知、Runner Result、slot 実行、feature flag 設定、実行ログ、速報実行(rapid_run)、速報クロスチェック設定 |
| [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) | 運用者(受益者・自動) | 完了状況を 両系未完了 → 片系完了 → 両系成功 / いずれか失敗 → 比較依頼作成済み へ進め、両系成功のときだけ条件付き INSERT で rapid_crosscheck_request を 1 件作成する。中止済みの run(並行稼働実行が ABORTED、または slot 実行に ABORTED あり。後者は仮採用: rdra-feedback #13)では両系成功でも作成せず、完了事実だけを記録して実行ログに警告を残す(中止済み run の比較依頼作成除外。判断主体は dispatcher) | 完了通知、速報実行(rapid_run)、速報比較依頼(rapid_crosscheck_request)、並行稼働実行(parallel_run)、slot 実行(spec 追加採用)、速報クロスチェック設定、実行ログ |
| [速報比較依頼を claim する](速報比較依頼を%20claim%20する/spec.md) | 運用者(受益者・自動) | worker(feature flag の RAPID_CROSSCHECK_WORKER が指す実体)が速報クロスチェック設定の poll 間隔で poll し、REQUESTED の依頼を worker_id / lease_until(設定の lease 期間)付きで CLAIMED にし、lease 失効かつ未開始の依頼を REQUESTED へ戻す | 速報比較依頼(rapid_crosscheck_request)、速報クロスチェック設定 |
| [比較ツールでジョブ単位比較を実行して結果を登録する](比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) | 運用者(受益者・自動)/ 比較ツール(外部) | 依頼を RUNNING にし、job_id の比較定義(crosscheck-job-map.csv)で比較ツールを起動する。stdout / stderr / exit_code を依頼に保存し、0 で SUCCEEDED、非 0 で FAILED とし、比較ツールの終了コードを得たときだけ comparison_result を登録する(比較結果の登録条件)。速報比較依頼だけのリラン由来 run は依頼終端時に parallel_run を COMPLETED にする | 速報比較依頼(rapid_crosscheck_request)、クロスチェックジョブマップ、比較定義、比較ツール実行結果、比較結果(comparison_result)、実行ログ、並行稼働実行(parallel_run) |
| [速報比較結果を参照する](速報比較結果を参照する/spec.md) | 運用者(参照者) | run_id で comparison_result と依頼の stdout / stderr / exit_code を参照し、blue / green の差分の原因を調査する。状態は変更しない | 比較結果(comparison_result)、速報比較依頼(rapid_crosscheck_request)、比較ツール実行結果、並行稼働実行(parallel_run)、Runner Result |

完了通知の送信側は tier-facade(slot runner)、受信側と以降の UC は tier-rapid-crosscheck で実現する。管理 DB(ジョブキュー兼管理 DB。RDB)は relay-gate 内部のデータストアであり、外部システムではない。

## UC 横断データフロー

BUC 内の UC 間で情報がどう流れるかを示す。情報がどの UC で作成(C)・参照(R)・更新(U)されるかを明記する。

### データフロー図

```mermaid
graph LR
  EXEC["実装切替ジョブ実行フロー(別 BUC)\nRunner Result / slot 実行 / parallel_run / rapid_run 作成"]
  CFG["適用構成定義フロー(別 BUC)\nクロスチェックジョブマップ / 比較定義"]
  UC1["速報クロスチェック runner へ完了通知を送信する"]
  UC2["両系成功時に速報比較依頼を作成する"]
  UC3["速報比較依頼を claim する"]
  UC4["比較ツールでジョブ単位比較を実行して結果を登録する"]
  UC5["速報比較結果を参照する"]
  TOOL["比較ツール"]
  MON["background 実行監視フロー(別 BUC)"]
  OPS["運用者"]

  RCFG["速報クロスチェック設定(rapid-crosscheck.env)\nRAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC"]
  EXEC -->|"Runner Result(exit_code, artifact_uri)/ feature flag(RAPID_CROSSCHECK_MODE, RAPID_CROSSCHECK_RUNNER)"| UC1
  RCFG -->|"管理 DB 接続参照名"| UC1
  RCFG -->|"lease 期間 / poll 間隔 / 接続参照名"| UC3
  UC1 -->|"完了通知(blue-completed / green-completed)→ rapid_run 更新"| UC2
  EXEC -->|"parallel_run.status / slot 実行の status(run が中止済み = parallel_run ABORTED または slot 実行に ABORTED ありなら依頼を作らない)"| UC2
  UC2 -->|"速報比較依頼(REQUESTED)"| UC3
  UC3 -->|"速報比較依頼(CLAIMED, worker_id, lease_until)"| UC4
  CFG -->|"job_id ごとの比較定義"| UC4
  UC4 -->|"比較起動"| TOOL
  TOOL -->|"比較ツール実行結果(stdout / stderr / exitcode)"| UC4
  UC4 -->|"速報比較依頼(SUCCEEDED / FAILED)+ 比較結果(comparison_result)"| UC5
  UC4 -->|"依頼状態 / started-at.txt / exitcode.txt"| MON
  UC5 -->|"差分の原因調査"| OPS
```

### 情報 CRUD マトリクス

列の UC は完了通知 → 依頼作成 → claim → 比較実行 → 参照の順。`R(間接)` は run_id 相関で別テーブル経由に参照し、その情報自体は読まないことを示す。

| 情報名 | 速報クロスチェック runner へ完了通知を送信する | 両系成功時に速報比較依頼を作成する | 速報比較依頼を claim する | 比較ツールでジョブ単位比較を実行して結果を登録する | 速報比較結果を参照する |
|--------|:---:|:---:|:---:|:---:|:---:|
| 完了通知 | C | R | - | - | - |
| Runner Result | R | - | - | R(blue / green の成果物) | R(間接) |
| slot 実行 | R | R(status。ABORTED の slot があれば依頼を作らない。仮採用: rdra-feedback #13) | - | - | - |
| feature flag 設定 | R | - | R | - | R |
| 速報クロスチェック設定 | R(受信側の接続参照名) | R(接続参照名) | R(接続参照名・lease 期間・poll 間隔) | - | R(接続参照名。spec 追加採用) |
| 速報実行(rapid_run) | U | R / U | - | R | R |
| 速報比較依頼(rapid_crosscheck_request) | - | C | U | U | R |
| 並行稼働実行(parallel_run) | - | R(job_id と status。FOR UPDATE。ABORTED なら依頼を作らない) | - | U(リラン由来 run の COMPLETED) | R(間接) |
| クロスチェックジョブマップ | - | - | - | R | - |
| 比較定義 | - | - | - | R | - |
| 比較ツール実行結果 | - | - | - | C | R |
| 比較結果(comparison_result) | - | - | - | C | R |
| 実行ログ | C | C(依頼を作らなかった WARN を含む) | C | C | - |

## 状態遷移全体図

BUC 内の UC が遷移 UC になっている状態モデルは、速報実行の完了状況、クロスチェック依頼(速報比較依頼)、並行稼働実行(リラン由来 run の RUNNING → COMPLETED のみ)の 3 つ。`[*]` → 両系未完了 は実装切替ジョブ実行フロー、依頼の RUNNING → ABORTED(abort-rapid-crosscheck)と background-rerun による依頼の再作成(並行稼働実行の `[*]` → STARTED → RUNNING)は実行復旧業務が担うため図に含めない。ただし本 BUC が作成した未着手(REQUESTED)の速報比較依頼が abort-blue / abort-green で ABORTED になる遷移(UC「実行を ABORTED へ遷移させる」。実行中止フロー)は、本 BUC の依頼ライフサイクルの終端として図に示す。run が中止済み(parallel_runs ABORTED または slot_executions に ABORTED あり。後者は仮採用: rdra-feedback #13)では「両系成功 → 比較依頼作成済み」の遷移は起きず、両系成功に留まる(条件「中止済み run の比較依頼作成除外」)。

```mermaid
stateDiagram-v2
  state "速報実行の完了状況" as RR {
    [*] --> 両系未完了: 実装切替ジョブ実行フロー(別 BUC)
    両系未完了 --> 片系完了: 両系成功時に速報比較依頼を作成する
    両系未完了 --> いずれか失敗: 両系成功時に速報比較依頼を作成する
    片系完了 --> 両系成功: 両系成功時に速報比較依頼を作成する
    片系完了 --> いずれか失敗: 両系成功時に速報比較依頼を作成する
    両系成功 --> 比較依頼作成済み: 両系成功時に速報比較依頼を作成する(中止済み run = parallel_run ABORTED または slot 実行に ABORTED あり。遷移せず両系成功に留まる)
    比較依頼作成済み --> [*]
    いずれか失敗 --> [*]
  }
  state "クロスチェック依頼(速報比較依頼)" as REQ {
    [*] --> REQUESTED: 両系成功時に速報比較依頼を作成する
    REQUESTED --> CLAIMED: 速報比較依頼を claim する
    CLAIMED --> REQUESTED: 速報比較依頼を claim する(lease 失効・未開始)
    REQUESTED --> ABORTED: 実行を ABORTED へ遷移させる(別 BUC 実行中止フロー。abort-blue / abort-green。未着手依頼のみ)
    CLAIMED --> RUNNING: 比較ツールでジョブ単位比較を実行して結果を登録する
    RUNNING --> SUCCEEDED: 比較ツールでジョブ単位比較を実行して結果を登録する
    RUNNING --> FAILED: 比較ツールでジョブ単位比較を実行して結果を登録する
    SUCCEEDED --> [*]
    FAILED --> [*]
    ABORTED --> [*]
  }
  state "並行稼働実行(速報比較依頼だけのリラン由来 run)" as PR {
    [*] --> RUNNING: background 側リランフロー(別 BUC。--role rapid-crosscheck)
    RUNNING --> COMPLETED: 比較ツールでジョブ単位比較を実行して結果を登録する(依頼の終端時)
    COMPLETED --> [*]
  }
  RR --> REQ: 比較依頼作成済みで依頼の追跡を引き継ぐ
  REQ --> PR: 依頼の終端(SUCCEEDED / FAILED)でリラン由来 run を終端させる
```

### 状態遷移 UC マッピング

| 状態モデル | 遷移元 | 遷移先 | 担当 UC |
|-----------|--------|--------|--------|
| 速報実行の完了状況 | 両系未完了 | 片系完了 | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) |
| 速報実行の完了状況 | 両系未完了 | いずれか失敗 | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) |
| 速報実行の完了状況 | 片系完了 | 両系成功 | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) |
| 速報実行の完了状況 | 片系完了 | いずれか失敗 | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) |
| 速報実行の完了状況 | 両系成功 | 比較依頼作成済み | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md)(run が中止済み(parallel_runs ABORTED または slot_executions に ABORTED あり。後者は仮採用: rdra-feedback #13)では遷移せず両系成功に留まる) |
| クロスチェック依頼 | `[*]` | REQUESTED | [両系成功時に速報比較依頼を作成する](両系成功時に速報比較依頼を作成する/spec.md) |
| クロスチェック依頼 | REQUESTED | CLAIMED | [速報比較依頼を claim する](速報比較依頼を%20claim%20する/spec.md) |
| クロスチェック依頼 | CLAIMED | REQUESTED | [速報比較依頼を claim する](速報比較依頼を%20claim%20する/spec.md) |
| クロスチェック依頼 | REQUESTED | ABORTED(abort-blue / abort-green による未着手の速報比較依頼の中止。速報比較依頼のみ。条件付き UPDATE status='REQUESTED'。0 件は正常) | [実行を ABORTED へ遷移させる](../../実行復旧業務/実行中止フロー/実行を%20ABORTED%20へ遷移させる/spec.md)(別 BUC 実行中止フロー) |
| クロスチェック依頼 | CLAIMED | RUNNING | [比較ツールでジョブ単位比較を実行して結果を登録する](比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) |
| クロスチェック依頼 | RUNNING | SUCCEEDED | [比較ツールでジョブ単位比較を実行して結果を登録する](比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) |
| クロスチェック依頼 | RUNNING | FAILED | [比較ツールでジョブ単位比較を実行して結果を登録する](比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) |
| 並行稼働実行 | RUNNING | COMPLETED(速報比較依頼だけを新規作成したリラン由来 run。`parent_run_id IS NOT NULL` かつ slot_executions 0 件) | [比較ツールでジョブ単位比較を実行して結果を登録する](比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) |

## BUC 内共有条件一覧

BUC 内の複数 UC で共有される条件の一覧。分母は BUC.tsv でこの BUC に紐づく条件。UC spec の分岐条件一覧で追加採用されている UC は「(spec)」で示す。

| 条件名 | 条件の説明 | 適用 UC |
|--------|----------|--------|
| 依頼状態遷移規則 | 依頼は REQUESTED で作成され、claim で CLAIMED、比較開始で RUNNING、exitcode 0 で SUCCEEDED、非 0 または実行エラーで FAILED、停止確認後の中止で ABORTED に遷移する(未着手 REQUESTED の速報比較依頼は abort-blue / abort-green でも ABORTED になる。競合窓の保険。CLAIMED のまま中止した依頼は lease 失効で REQUESTED に戻り再 claim されうる: rdra-feedback #15)。速報と確報で同一 | 両系成功時に速報比較依頼を作成する, 速報比較依頼を claim する, 比較ツールでジョブ単位比較を実行して結果を登録する |
| 中止済み run の比較依頼作成除外 | run が中止済み(並行稼働実行(parallel_run)が ABORTED、**または**同 run の slot 実行(slot_executions)に ABORTED の行がある = いずれかの slot に aborted.txt が公開済み)の場合、速報クロスチェック runner(dispatcher)は完了通知を受けても速報比較依頼を作成しない(判定キーの拡張は仮採用: rdra-feedback #13。RDRA 条件は parallel_run の ABORTED のみを判定キーとしている。foreground slot の中継完了で parallel_run が COMPLETED になった後に background slot を中止する典型経路では parallel_run だけでは除外が効かないため)。parallel_runs は FOR UPDATE で読み、abort-blue / abort-green の parallel_runs 無条件行ロック(`SELECT 1 ... FOR UPDATE`。parallel_runs が COMPLETED でも取る)と直列化する。完了事実(blue_status / green_status と成果物 URI)は rapid_run に記録し、実行ログに警告を残す。判断主体は速報クロスチェック runner であり、slot runner は自 slot の中止状態を判断せず通常どおり完了通知を送る。RAPID_CROSSCHECK_MODE=off では完了通知も比較依頼も存在しないため速報有効時だけに適用する。両 slot 完了直後の依頼を止める本来の経路は本条件であり、abort-blue / abort-green の REQUESTED → ABORTED は競合窓の保険(rdra-feedback #14) | 両系成功時に速報比較依頼を作成する |
| 完了通知の系統独立 | blue / green runner は完了時に自系統の公開 function で通知するだけで、相手側の状態や比較依頼の要否を判断しない。自 slot の中止状態(aborted.txt の有無)も判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり通知する | 速報クロスチェック runner へ完了通知を送信する |
| 設定所有区分 | 速報クロスチェックの管理 DB 接続参照名・lease 期間・worker の poll 間隔は速報クロスチェック設定(rapid-crosscheck.env。所有者: 基盤適用設計者)が所有する | 速報比較依頼を claim する(spec) |
| 速報結果の位置付け | 速報の exitcode や失敗は業務ジョブの結果としてジョブスケジューラへ返さない。速報は原因調査用で、リリース判断の正本は確報 | 速報比較結果を参照する, 比較ツールでジョブ単位比較を実行して結果を登録する, 速報クロスチェック runner へ完了通知を送信する(spec), 両系成功時に速報比較依頼を作成する(spec), 速報比較依頼を claim する(spec) |
| 比較ツール終了コードの対応 | 比較 OK=0 は SUCCEEDED、比較 NG=3 は FAILED(警告終了)、実行エラー=6 は FAILED(エラー終了) | 比較ツールでジョブ単位比較を実行して結果を登録する, 速報比較結果を参照する |
| 速報と確報のモデル分離 | 速報は rapid_run / rapid_crosscheck_request を用い、確報の final_crosscheck_request と対象カタログを作成・変更しない | 両系成功時に速報比較依頼を作成する, 速報クロスチェック runner へ完了通知を送信する(spec), 速報比較依頼を claim する(spec), 比較ツールでジョブ単位比較を実行して結果を登録する(spec), 速報比較結果を参照する(spec) |
| 速報クロスチェック有効判定 | RAPID_CROSSCHECK_MODE が foreground または background のとき runner は完了通知を送信し、速報管理 DB に完了結果と比較依頼を書き込む(両値の挙動は同じ。判定は off か off 以外か)。off では完了通知を送信せず、速報管理 DB へ接続・書き込みせず、parallel_run も作成しない(worker / 結果参照も off では DB に接続せず終了コード 3) | 速報クロスチェック runner へ完了通知を送信する, 両系成功時に速報比較依頼を作成する(spec), 速報比較依頼を claim する(spec), 速報比較結果を参照する(spec) |
| 完了通知失敗の扱い | slot runner から速報クロスチェック runner への完了通知の送信失敗は自動検知しない。slot runner は実行ログに警告を残し、Runner Result と終了コードは実装スクリプトの exitcode のまま変更しない。復旧は運用者が速報クロスチェック runner を同一引数で再実行する(冪等・先勝ちで完了結果は一度だけ登録される) | 速報クロスチェック runner へ完了通知を送信する |
| 比較結果の登録条件 | comparison_result は比較ツールを起動して終了コードを得たときだけ登録する。比較定義なし・起動失敗では登録せず、依頼だけを FAILED(exit_code=6 相当、error_summary に理由)で終端する | 比較ツールでジョブ単位比較を実行して結果を登録する |

## BUC 内共有バリエーション一覧

BUC 内の複数 UC で共有されるバリエーションの一覧(UC spec のバリエーション一覧を集約)。

| バリエーション名 | 値 | 適用 UC |
|----------------|---|--------|
| 実装スロット | blue、green | 速報クロスチェック runner へ完了通知を送信する, 両系成功時に速報比較依頼を作成する |
| 速報クロスチェックのプロセス役割 | runner(dispatcher)、worker | 速報クロスチェック runner へ完了通知を送信する, 両系成功時に速報比較依頼を作成する, 速報比較依頼を claim する, 比較ツールでジョブ単位比較を実行して結果を登録する |
| クロスチェック依頼状態 | REQUESTED、CLAIMED、RUNNING、SUCCEEDED、FAILED、ABORTED | 両系成功時に速報比較依頼を作成する, 速報比較依頼を claim する, 比較ツールでジョブ単位比較を実行して結果を登録する, 速報比較結果を参照する |
| クロスチェック種別 | 速報クロスチェック | 両系成功時に速報比較依頼を作成する, 速報比較依頼を claim する, 速報比較結果を参照する |
| 比較ツール終了コード | 0(比較 OK)、3(比較 NG・警告終了)、6(実行エラー・エラー終了) | 比較ツールでジョブ単位比較を実行して結果を登録する, 速報比較結果を参照する |
| 比較結果ステータス | 比較 OK、比較 NG、FAILED | 比較ツールでジョブ単位比較を実行して結果を登録する, 速報比較結果を参照する |
| 速報クロスチェックモード | foreground、background、off(foreground / background は同じ挙動) | 速報クロスチェック runner へ完了通知を送信する, 速報比較依頼を claim する, 速報比較結果を参照する |
| 設定所有区分 | 速報クロスチェック設定(所有者: 基盤適用設計者) | 速報比較依頼を claim する |
