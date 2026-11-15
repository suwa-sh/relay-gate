---
schema_version: distillery.feedback-request/v1
feedback_id: 20261116_standard_runner_job_map_location
created_at: 2026-11-16T00:50:00+09:00
source: distillery-impl
uc_id: 65b09d93
---

# 利用者からの変更要求(標準の runner の提供、ジョブマップの場所、起動時の検査の未決 2 件)

## CR-65b09d93-001: relay-gate が標準の slot runner を正式に提供し、利用者はジョブマップを置くだけで動かせるようにする

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-04]
- related_files: [docs/usdm/latest/requirements.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- 利用者の想定(2026-11-15 の発言): 「runner は relay-gate で用意し、引数と起動するコマンドをマップした設定ファイルを利用者が配置するもの」。
- 現在の仕様は、relay-gate が同梱するものを「共通ライブラリ `lib/runner-*.sh`(ジョブマップ解決・execution-spec 保存・3 ファイル公開・完了通知)」と「参考実装 `runners/ssh-runner.sh`(仮採用: 汎用の SSH runner)」とし、適用側が参考実装をコピーまたは `source` して runner 実体(`runners/blue-runner.sh` など)を書く、としている。そのまま使える正式な runner は無い。
- 要求(USDM)は「blue / green の runner は設定で実体スクリプトを割り当て、実装固有の起動方式・ホスト・OS・プロトコルを slot の runner に閉じ込める。runner を差し替えることで異なる世代の実装を並行稼働できる」と定める。relay-gate が runner を提供するかどうかは書いていない。
- 元の方針資料のしくみの資料は「`$BLUE_RUNNER` と `$GREEN_RUNNER` は適用ごとに実体を割り当てます」と書く。利用イメージの資料は、案件固有の接続(Windows サーバへの実行、DB セグメント経由の実行、Kubernetes Job の起動)のために `legacy-runner.sh` / `beam-runner.sh` などを適用側が用意する例を示す。
- slot ジョブマップは、host と user が両方空の行をローカル実行、それ以外を SSH 実行として解決する(現在の仕様と要求)。
- 利用者は 2026-11-16 に、選択肢を比べたうえで次のとおり決定した: 「relay-gate が標準の runner(ローカル実行と SSH 実行)を正式に配り、特殊な接続だけ利用者が自作する形にする」。
- runner・共通ライブラリ・ジョブを起動するコマンドは、まだ実装していない(実装済みは設定の検証コマンドだけ)。

### 現在の仕様と問題

- ローカル実行と SSH 実行だけで足りる適用でも、利用者は参考実装をコピーして runner を書かなければ動かせない。「ジョブマップを置けば動く」という利用者の想定と違う。
- 参考実装は仮採用のままで、正式に提供する範囲(何を保証し、何を利用者が書くか)が決まっていない。

### 変更してほしいこと

1. relay-gate は、そのまま feature flag の `BLUE_RUNNER` / `GREEN_RUNNER` に割り当てられる標準の slot runner を正式に提供する。標準の runner は、slot ジョブマップの行に従ってローカル実行(host と user が両方空)と SSH 実行の両方を扱う。標準の runner を使う適用では、利用者が用意するものは feature flag と slot ジョブマップ(と実行先の実装)だけにする。
2. 標準の runner は、runner の外部 IF(引数、`--help` の応答、Runner Result Contract の 3 ファイルと execution-spec.json、完了通知)を満たす正式な提供物として、要求・アーキテクチャ・インフラ(配置物)・仕様に位置づける。「参考実装(仮採用)」の扱いをやめる。
3. 標準の runner のファイル構成(blue 用と green 用を 1 つの実体で兼ねるか、ファイル名、置き場所、feature flag への書き方の例)を仕様で 1 つに決める。推奨は、1 つの実体を blue と green の両方に割り当てられる形(slot は起動時の引数で受け取る)。
4. 特殊な接続(標準の runner が扱わない起動方式・プロトコル)は、これまでどおり利用者が runner を自作して割り当てられる。自作する runner のための共通ライブラリの提供と、runner の外部 IF は残す。runner を差し替えて異なる世代の実装を並行稼働できる、という要求は変えない。
5. 元の方針資料の「適用ごとに実体を割り当てる」は、割り当てる実体として標準の runner を選べる、という形で両立させる。方針資料の記述と違う点が残る場合は、利用者決定(2026-11-16)として判断記録に残す。
6. 標準の runner を割り当てた設定が検証を通り、ローカル実行の行と SSH 実行の行をそれぞれ解決できることを判定できる BDD シナリオを、該当する機能に置く。

### 完了条件

- 標準の runner が正式な提供物であることと、その範囲(ローカル実行と SSH 実行)が、要求と仕様から読み取れる。
- 標準の runner を使う適用で利用者が用意するものが、feature flag と slot ジョブマップだけであることが、仕様から読み取れる。
- 標準の runner のファイル名・置き場所・feature flag への書き方が 1 つに決まっている。
- 利用者が runner を自作して割り当てる道(共通ライブラリと runner の外部 IF)が残っている。
- 「参考実装(仮採用)」という扱いが仕様に残っていない。

## CR-65b09d93-002: slot ジョブマップの場所を feature flag に書けるようにし、書かなければいまの固定の名前を使う

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-01, SPEC-004-04, REQ-001, SPEC-001-01]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/tier-facade.md, docs/rdra/latest/情報.tsv, docs/arch/latest/arch-design.yaml]

### 観測した事実

- 現在の仕様は、slot ジョブマップの場所を設定ファイル置き場の固定の名前(`$RELAY_GATE_CONFIG_DIR/blue-job-map.csv` と `$RELAY_GATE_CONFIG_DIR/green-job-map.csv`)に決めている。場所を設定で変える手段は無い。固定の名前にした理由は、要求・方針資料・判断記録のどこにも無い。
- 元の方針資料の利用イメージの資料は、feature flag の設定例の中に、ジョブマップの場所を書く行を置いている: `LEGACY_JOB_MAP_CSV=./legacy-job-map.csv` / `BEAM_JOB_MAP_CSV=./beam-job-map.csv`(キー名は適用側が決めた名前で、相対パス)。しくみの資料の設定例(9 キー)には、ジョブマップの場所の行は無い。
- 要求(RDRA の情報「feature flag」)とアーキテクチャは、feature flag を「元の方針資料の設定契約どおり 9 キー」と定めている。現在の仕様は、9 キー以外のキーを未知のキーとして warn を出す。
- feature flag の runner / worker の 4 キーは、2026-11-15 の利用者決定で相対パスを受け付け、基準を設定ファイルのあるディレクトリにした。
- 利用者は 2026-11-16 に、選択肢を比べたうえで次のとおり決定した: 「設定ファイルに場所を書く項目を足し、書かなければいまの固定の名前を使う形にする。相対パスの基準は設定ファイルのあるディレクトリ」。

### 現在の仕様と問題

- 方針資料の利用イメージの設定例(設定ファイルにジョブマップの場所を書く)が、現在の仕様では表せない。
- ジョブマップを設定ファイル置き場以外に置きたい適用(例: runner と同じディレクトリに置く、サンプルを置いたまま試す)に手段が無い。

### 変更してほしいこと

1. feature-flag.env に、slot ジョブマップの場所を書く任意のキーを blue 用と green 用に 1 つずつ足す。キー名は仕様で確定する。推奨は `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV`(方針資料の利用イメージの `LEGACY_JOB_MAP_CSV` / `BEAM_JOB_MAP_CSV` と同じ語尾。slot の名前は他のキーに合わせて BLUE / GREEN)。
2. キーが無い、または値が空のときは、いまの固定の名前(`$RELAY_GATE_CONFIG_DIR/blue-job-map.csv` / `$RELAY_GATE_CONFIG_DIR/green-job-map.csv`)を使う。既存の設定はそのまま動く。
3. 値は絶対パスと相対パスのどちらも受け付ける。相対パスの基準は、その feature-flag.env があるディレクトリとする。解決の規則(`~` や環境変数を展開しない、`./` や `../` を畳まない、設定ファイルのパスが相対パスのときの扱い、シンボリックリンクをたどらない、解決後のパスの使い方と表示)は、runner / worker の 4 キーの規則と同じにする。
4. 解決後のパスを、ジョブマップを読むすべての処理で同じに使う: feature flag の検証コマンドのジョブマップの所在の検査と表示(`blue_job_map:` などの行、`error: job map not found` の行)、slot runner のジョブマップ解決、ジョブマップを読む運用系のコマンド。slot runner は feature-flag.env を読まない契約のままにし、ジョブを起動するコマンド(とリランのコマンド)が解決した後の場所を runner へ渡す方法を仕様で決める。
5. feature flag のキーの数(9 キー)と、9 キー以外を未知のキーとして扱う規則を、足したキーに合わせて直す。要求(RDRA の情報)・アーキテクチャの「9 キー」の記述も揃える。足す 2 キーは任意であること、方針資料のしくみの資料の 9 キーの設定例がそのまま通ることを明記する。
6. ジョブマップ単体の検証コマンド(`validate-config.sh --job-map <パス>`)は、渡されたパスを検証する動きのまま変えない。
7. キーを書いた場合・書かない場合・相対パスの場合に、どのジョブマップが使われるかを判定できる BDD シナリオを、該当する機能に置く。
8. 実装済みの機能(feature flag の検証)が新しい契約と違うことを、実装との差分として仕様の判断記録に残す。

### 完了条件

- feature-flag.env にジョブマップの場所を書く任意のキーが blue 用と green 用にあり、キー名が 1 つに決まっている。
- キーを書かない設定で、いまと同じ固定の名前のジョブマップが使われることが、仕様から読み取れる。
- 相対パスの基準(設定ファイルのあるディレクトリ)と解決の規則が、runner / worker の 4 キーと同じであることが、CLI 契約から読み取れる。
- 検証コマンドと実行時の読み手で、同じ設定から同じジョブマップが選ばれる。
- 要求・アーキテクチャ・仕様で、feature flag のキーの数の記述が揃っている。

## CR-65b09d93-003: ジョブを起動するコマンドは、設定の違反が 2 つ以上あるとき、検証コマンドと同じ順で最初の違反を 1 行出す

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-01]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md, docs/todo.md]

### 観測した事実

- feature flag の検証コマンド(`validate-config.sh --feature-flag`)の error 行どうしの順は、2026-11-15 に CLI 契約に定めた(対象は検証コマンドだけ)。
- ジョブを起動するコマンド(`facade.sh`)は、設定の検証エラーを error 1 行で出す契約である。違反が 2 つ以上ある設定で、どの違反の 1 行を出すかが 1 つに決まっていない。機能「slot 実行モードを選択して runner を起動する」の仕様は、検査を「列挙 → foreground → 必須キーの存在 → 実体パス」の順で書く一方、検証コマンドと同じ検証関数を使うとも書いており、設定によって出る 1 行が食い違う。
- この未決は課題一覧に記録済み(2026-11-15)。元の方針資料に記載は無い。
- 利用者は 2026-11-15 に次のとおり決定した: 「検証コマンドと同じ順で、最初の違反を 1 行出す」。

### 現在の仕様と問題

- 違反が 2 つ以上ある設定で、ジョブを起動するコマンドの stderr が実装によって変わりうる。

### 変更してほしいこと

1. ジョブを起動するコマンドは、feature flag の設定に違反が 2 つ以上あるとき、検証コマンドの error 行の順で最初に出る違反の error 行(その行に hint があれば hint も)だけを出して、設定エラーの終了コードで終わる、と CLI 契約に定める。
2. 機能「slot 実行モードを選択して runner を起動する」の仕様の検査の順の記述を、この規則に合わせて直す。
3. 違反が 2 つ以上ある設定で出る 1 行を判定できる BDD シナリオを、該当する機能に置く。
4. 課題一覧の該当の記録を、決定済みとして閉じる。リランのコマンドの扱いは次の要求で定める。

### 完了条件

- 違反が 2 つ以上ある設定で、ジョブを起動するコマンドが出す error 行が、CLI 契約から 1 つに決まる。
- 検査の順の記述が、機能の仕様と CLI 契約で食い違っていない。

## CR-65b09d93-004: リランのコマンドは、起動の前に runner / worker の実体を検査せず、起動に失敗したら終了コード 6 にする

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-01]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/実行復旧業務/background 側リランフロー/元の execution-spec.json から復元して新しい run_id で起動する/tier-ops.md, docs/todo.md]

### 観測した事実

- リランのコマンド(`background-rerun.sh`)は、feature-flag.env の `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` を使う。
- リランのコマンドが feature-flag.env の違反を見つけたときの扱い(検査するキーの範囲・終了コード・事前検証との前後)は、CLI 契約に無い。課題一覧に記録済み(2026-11-15)。元の方針資料に記載は無い。
- 利用者は 2026-11-15 に次のとおり決定した: 「起動の前に 4 項目(runner / worker の 4 キー)の実体を検査せず、起動に失敗したら終了コード 6 にする」。

### 現在の仕様と問題

- リランのコマンドが、起動の前に runner の実体の存在・実行権限を検査するのか、起動してみて失敗を扱うのかが決まっていない。

### 変更してほしいこと

1. リランのコマンドは、起動の前に runner / worker の 4 キーの実体(存在・実行権限・`--help` の応答)を検査しない、と CLI 契約に定める。相対パスの解決は、runner / worker の 4 キーの規則どおり行う。
2. runner の起動に失敗したとき(実体が無い、実行できない)は、終了コード 6 で終わる、と定める。そのときの stderr の error 行の文言と、成果物・管理 DB に残すものを、既存の起動失敗の規則と揃えて 1 つに決める。
3. リランのコマンドが feature-flag.env から読むキーの範囲と、読めない・形式が不正なときの扱い(入力の守備範囲の検査と終了コード)を、他の実行時の読み手の規則と揃えて明記する。
4. 起動の前に検査しないことと、起動に失敗したときの終了コードを判定できる BDD シナリオを、該当する機能に置く。

### 完了条件

- リランのコマンドが起動の前に runner / worker の実体を検査しないことが、CLI 契約から読み取れる。
- runner の起動に失敗したときの終了コード(6)と error 行が 1 つに決まっている。
- 課題一覧の該当の記録が、決定済みとして閉じられている。
