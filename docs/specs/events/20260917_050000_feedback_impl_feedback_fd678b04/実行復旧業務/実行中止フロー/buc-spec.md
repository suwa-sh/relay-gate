# 実行中止フロー

## 概要

運用者が、通知メールやジョブスケジューラの実行結果から中止対象の run_id を特定し、対象のプロセス・Pod・SSH 接続先の処理を自身で強制終了したうえで、中止スクリプト(abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck)で RUNNING の slot 実行、REQUESTED / CLAIMED / RUNNING の速報比較依頼、または RUNNING の確報比較依頼を ABORTED へ明示的に遷移させる BUC。スクリプトは現在状態を表示して停止確認に yes と応答されたときだけ状態を更新し、自身ではプロセスを停止しない。slot 実行の中止は成果物ディレクトリへの `aborted.txt`(中止日時 1 行)の書き込みを正本とし、RAPID_CROSSCHECK_MODE が off 以外なら管理 DB の状態も ABORTED に更新し、対象 run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(競合窓の保険。dispatcher 側の中止済み run 判定と併用。CLAIMED / RUNNING の依頼は変更せず、明示中止は abort-rapid-crosscheck の status IN 条件付き UPDATE で行う)。off でも成果物ファイルだけで中止が成立し、ABORTED にした background slot 実行と速報比較依頼は background 側リランフローの対象になれる。

## 所属 UC 一覧

| UC名 | アクター | 主な操作 | 関連情報 |
|------|---------|---------|---------|
| [現在状態を確認して停止確認に応答する](現在状態を確認して停止確認に応答する/spec.md) | 運用者 | 中止スクリプトを `--run-id` 付きで起動し、表示された現在状態(slot 系は成果物ファイルから導出)を見てプロセス停止済みかを yes / yes 以外で応答する | 中止指示、slot 実行、速報比較依頼、確報比較依頼、通知メール |
| [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md) | 運用者(受益者) | yes 応答時に限り、background かつ RUNNING の slot 実行は `aborted.txt` を書き(off 以外は加えて管理 DB を条件付き UPDATE)、速報比較依頼は REQUESTED / CLAIMED / RUNNING のとき(abort-rapid-crosscheck。`status IN` 条件付き UPDATE)、確報比較依頼は RUNNING のとき(abort-final-crosscheck)条件付き UPDATE で ABORTED にし、並行稼働実行が STARTED / RUNNING なら併せて ABORTED にする(COMPLETED は変更しない)。abort-blue / abort-green は対象 run の REQUESTED(未着手)の速報比較依頼も ABORTED にする(off 以外。0 件で可。競合窓の保険)。CLAIMED を中止すると claim 済み worker は比較を開始しない | 中止指示、slot 実行、速報比較依頼、確報比較依頼、並行稼働実行、実行ログ、Runner Result |

2 UC は 4 つの中止スクリプトの前半(状態表示と対話確認)と後半(状態更新)を構成する。

## UC 横断データフロー

BUC 内の UC 間で情報がどう流れるかを示す。情報がどの UC で作成(C)・参照(R)・更新(U)されるかを明記する。

### データフロー図

```mermaid
graph LR
  subgraph IN["BUC 外(入力)"]
    MAIL["通知メール\n(background 実行監視フロー)"]
    SCHED["ジョブスケジューラの実行結果"]
    HOST["リモート実行ホスト\n(運用者が自身でプロセス停止)"]
  end
  CONFIRM["現在状態を確認して\n停止確認に応答する"]
  ABORT["実行を ABORTED へ\n遷移させる"]
  subgraph FS["成果物ディレクトリ(slot の正本)"]
    RR_ART["Runner Result\nexecution-spec.json / started-at.txt / exitcode.txt / aborted.txt"]
  end
  subgraph DB["内部データストア: ジョブキュー兼管理 DB"]
    SE["slot 実行"]
    RR["速報比較依頼"]
    FR["確報比較依頼"]
    PR["並行稼働実行"]
  end
  LOG["実行ログ"]
  MAIL -->|"run_id / role"| CONFIRM
  SCHED -->|"run_id"| CONFIRM
  HOST -.->|"停止済みの確認"| CONFIRM
  RR_ART -->|"現在状態(mode / status を導出)"| CONFIRM
  SE -->|"pid(off 以外)"| CONFIRM
  RR -->|"現在状態(status / worker_id / lease_until)"| CONFIRM
  FR -->|"現在状態(status / worker_id / lease_until)"| CONFIRM
  CONFIRM -->|"中止指示(run_id, 中止対象種別, 停止確認応答=yes)"| ABORT
  CONFIRM -->|"answer=no(状態不変)"| LOG
  ABORT -->|"aborted.txt(.tmp -> mv)"| RR_ART
  ABORT -->|"RUNNING → ABORTED(off 以外)"| SE
  ABORT -->|"REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck)/ REQUESTED → ABORTED(abort-blue / abort-green の未着手依頼。競合窓の保険。off 以外)"| RR
  ABORT -->|"RUNNING → ABORTED"| FR
  ABORT -->|"STARTED / RUNNING → ABORTED(COMPLETED は不変。off 以外)"| PR
  ABORT -->|"operator / answer / from / to"| LOG
  ABORT -.->|"ABORTED は中止確認済みとしてリラン可(off でも aborted.txt で成立)"| RERUN["background 側リランフロー"]
```

### 情報 CRUD マトリクス

分母は BUC.tsv でこの BUC に紐づく 8 情報。

| 情報名 | 現在状態を確認して停止確認に応答する | 実行を ABORTED へ遷移させる |
|--------|:---:|:---:|
| 中止指示 | C | U |
| slot 実行 | R | U |
| Runner Result | R(spec のみ) | U |
| 速報比較依頼(rapid_crosscheck_request) | R | U |
| 確報比較依頼(final_crosscheck_request) | R | U |
| 通知メール | R | - |
| 並行稼働実行(parallel_run) | - | U |
| 実行ログ | C | C |

補足:

- 中止指示は永続化する情報ではなく、前半 UC が run_id・中止対象種別・表示した現在状態・停止確認応答を確定し(C)、後半 UC が更新後状態(ABORTED)と指示者・指示日時を実行ログに残す(U)。
- slot 実行の現在状態は成果物ファイル(execution-spec.json の mode、started-at.txt / exitcode.txt / aborted.txt の有無と値)から導出する(条件「slot 実行の状態導出規則」)。前半 UC は管理 DB を参照するだけで更新しない(slot 系は off 以外のとき pid を補うためだけに読む)。更新は後半 UC に限る。
- Runner Result の U は後半 UC が `aborted.txt`(中止日時 1 行)を成果物ディレクトリに追加すること。他の成果物ファイルは書き換えない。BUC.tsv 上の紐づけは後半 UC で、前半 UC は spec 上の参照のみ。
- 並行稼働実行の併更新は RAPID_CROSSCHECK_MODE が off 以外のときだけ行う(off では parallel_run が存在しない)。

## 状態遷移全体図

BUC 内で関連する状態モデルは 3 つ(slot 実行 / クロスチェック依頼 / 並行稼働実行)。slot 実行は RUNNING → ABORTED、クロスチェック依頼は REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck。速報比較依頼のみ。`status IN ('REQUESTED','CLAIMED','RUNNING')` の条件付き UPDATE)、RUNNING → ABORTED(abort-final-crosscheck。確報比較依頼のみ)と REQUESTED → ABORTED(abort-blue / abort-green による未着手の速報比較依頼の中止。競合窓の保険。速報比較依頼のみ)、並行稼働実行は STARTED → ABORTED と RUNNING → ABORTED をこの BUC が担当する。前半 UC は状態を変更しない。中止できる状態でない対象(速報比較依頼の終端状態、確報比較依頼の RUNNING 以外、slot の RUNNING 以外 / foreground / off)は状態を変更せずエラー終了する。

```mermaid
stateDiagram-v2
  state "slot 実行(並行稼働実行管理)" as SLOT {
    state "RUNNING" as S_RUNNING
    state "ABORTED" as S_ABORTED
    S_RUNNING --> S_ABORTED: 実行を ABORTED へ遷移させる(abort-blue / abort-green、background のみ。aborted.txt を書き、off 以外は管理 DB も更新)
    S_ABORTED --> [*]
  }
  state "クロスチェック依頼(速報 / 確報)" as REQ {
    state "REQUESTED" as R_REQUESTED
    state "CLAIMED" as R_CLAIMED
    state "RUNNING" as R_RUNNING
    state "ABORTED" as R_ABORTED
    R_RUNNING --> R_ABORTED: 実行を ABORTED へ遷移させる(abort-rapid-crosscheck(速報)/ abort-final-crosscheck(確報。RUNNING のみ))
    R_CLAIMED --> R_ABORTED: 実行を ABORTED へ遷移させる(abort-rapid-crosscheck。claim 済み速報比較依頼の中止。claim 済み worker は RUNNING への条件付き UPDATE が 0 件になり比較を開始しない。速報比較依頼のみ)
    R_REQUESTED --> R_ABORTED: 実行を ABORTED へ遷移させる(abort-rapid-crosscheck(速報。未着手依頼の明示中止)/ abort-blue / abort-green(対象 run の未着手の速報比較依頼のみ。競合窓の保険。off 以外。条件付き UPDATE status='REQUESTED'。0 件は正常))
    R_ABORTED --> [*]
  }
  state "並行稼働実行" as PR {
    state "STARTED" as P_STARTED
    state "RUNNING" as P_RUNNING
    state "ABORTED" as P_ABORTED
    P_RUNNING --> P_ABORTED: 実行を ABORTED へ遷移させる(slot 実行 / 速報比較依頼の中止に伴う)
    P_STARTED --> P_ABORTED: 実行を ABORTED へ遷移させる(STARTED で作成した直後の中止。RUNNING 更新前を取りこぼさない)
    P_ABORTED --> [*]
  }
```

### 状態遷移 UC マッピング

| 状態モデル | 遷移元 | 遷移先 | 担当 UC |
|-----------|--------|--------|--------|
| slot 実行 | RUNNING | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md) |
| クロスチェック依頼(速報比較依頼) | RUNNING | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md)(abort-rapid-crosscheck) |
| クロスチェック依頼(速報比較依頼) | CLAIMED | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md)(abort-rapid-crosscheck。claim 済み依頼の中止。worker は RUNNING への条件付き UPDATE 0 件で比較を開始しない。確報比較依頼には適用しない) |
| クロスチェック依頼(速報比較依頼) | REQUESTED | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md)(abort-rapid-crosscheck による未着手依頼の明示中止 / abort-blue / abort-green による slot 中止時の競合窓の保険(対象 run の未着手依頼のみ)。確報比較依頼には適用しない) |
| クロスチェック依頼(確報比較依頼) | RUNNING | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md)(abort-final-crosscheck) |
| 並行稼働実行 | RUNNING | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md) |
| 並行稼働実行 | STARTED | ABORTED | [実行を ABORTED へ遷移させる](実行を%20ABORTED%20へ遷移させる/spec.md) |

[現在状態を確認して停止確認に応答する](現在状態を確認して停止確認に応答する/spec.md) は yes 応答を後半 UC に引き渡すだけで、遷移は行わない(yes 以外は状態不変で終了コード 3)。

## BUC 内共有条件一覧

BUC 内の複数 UC で共有される条件の一覧。適用 UC は BUC.tsv の紐づけを正とし、spec 側でのみ参照する UC は括弧で補足する。

| 条件名 | 条件の説明 | 適用 UC |
|--------|----------|--------|
| 停止確認応答 | 現在状態を表示後に「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と対話確認し、yes(完全一致)のときだけ状態を ABORTED に更新する。yes 以外は状態を変更せず終了する。スクリプト自身はプロセスを停止しない | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| slot 実行の状態導出規則 | slot 実行の状態は成果物ディレクトリのファイル正本から導出する: exitcode.txt があれば 0 で SUCCEEDED / 非 0 で FAILED、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING。前半 UC は表示、後半 UC は可否判定と yes 応答直後の再確認に使う | 実行を ABORTED へ遷移させる(spec のみ: 現在状態を確認して停止確認に応答する) |
| 速報クロスチェック有効判定 | abort-blue / abort-green は RAPID_CROSSCHECK_MODE によらず成果物ファイルで現在状態を表示し aborted.txt で中止を記録する。off 以外なら加えて管理 DB(slot_executions / parallel_runs / REQUESTED の rapid_crosscheck_requests)を ABORTED に更新し、off では管理 DB に触れず aborted.txt だけで終了コード 0。abort-rapid-crosscheck は依頼レコードが管理 DB にしか無いため off では終了コード 3。abort-final-crosscheck は RAPID_CROSSCHECK_MODE を参照せず、final-crosscheck.env の FINAL_DB_CONN_REF の有無だけで管理 DB 有無を判定する | (spec のみ: 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる) |

BUC.tsv 上で 1 UC のみに紐づく条件(CLI とメールによる提示 / slot 中止可否判定 / 依頼中止可否判定 / 依頼状態遷移規則)は各 UC spec に記載する。slot 中止可否判定は、yes で slot を ABORTED にするとき対象 run の REQUESTED で未着手の速報比較依頼も ABORTED にする(CLAIMED / RUNNING は変更しない)ことを含む(UC「実行を ABORTED へ遷移させる」)。この REQUESTED → ABORTED は競合窓の保険である: 両系の完了通知で速報比較依頼が REQUESTED で作成された直後に運用者が slot を中止した場合の競合窓を塞ぐ。dispatcher 側の中止済み run 判定(速報クロスチェックフローの条件「中止済み run の比較依頼作成除外」。並行稼働実行 ABORTED または完了通知の対象 slot の slot 実行 ABORTED)と併用する。依頼中止可否判定は、速報比較依頼は REQUESTED / CLAIMED / RUNNING のいずれでも abort-rapid-crosscheck(停止確認 yes 後の `status IN` 条件付き UPDATE)で中止でき、確報比較依頼は RUNNING のときだけ abort-final-crosscheck で中止できる判定表(クロスチェック種別 × 依頼状態)。CLAIMED のまま残すと lease 失効で REQUESTED に戻り再 claim されるため、中止済み run の依頼は abort-rapid-crosscheck で止める。CLAIMED を中止すると claim 済み worker は RUNNING への条件付き UPDATE が 0 件になり比較を開始しない(速報クロスチェックフローの UC「比較ツールでジョブ単位比較を実行して結果を登録する」)。

## BUC 内共有バリエーション一覧

BUC 内の複数 UC で共有されるバリエーションの一覧(各 UC spec のバリエーション一覧を集約)。

| バリエーション名 | 値 | 適用 UC |
|----------------|---|--------|
| 中止対象種別 | background slot 実行、速報比較依頼(REQUESTED / CLAIMED / RUNNING を中止できる)、確報比較依頼(RUNNING のみ) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| 停止確認応答 | yes、no(yes 以外はすべて no 扱い) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| slot 実行モード | foreground、background、off(中止可は background のみ。execution-spec.json の slots.<role>.mode で判定) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| 速報クロスチェックモード | foreground、background、off(off 以外は管理 DB も更新。off は aborted.txt のみ) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| Runner Result 成果物種別 | started-at.txt、exitcode.txt、aborted.txt(状態導出に使う 3 種。aborted.txt は後半 UC が中止時のみ生成) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
| クロスチェック依頼状態 | REQUESTED、CLAIMED、RUNNING、SUCCEEDED、FAILED、ABORTED(abort-rapid-crosscheck の中止可は REQUESTED / CLAIMED / RUNNING、abort-final-crosscheck の中止可は RUNNING のみ。終端状態は状態を変更せずエラー終了。REQUESTED の速報比較依頼は abort-blue / abort-green の slot 中止に伴っても ABORTED になる(競合窓の保険)) | 現在状態を確認して停止確認に応答する, 実行を ABORTED へ遷移させる |
