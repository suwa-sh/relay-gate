# UC 横断 Scenario 一覧(S2 test-scaffold 起票)

- uc_id: 65b09d93(slot runner の実体スクリプトを割り当てる / assign-slot-runner-scripts)
- 起票 stage: S2 test-scaffold
- 目的: UC BDD(`features/uc/assign-slot-runner-scripts.feature`)・tier BDD(`facade/features/assign-slot-runner-scripts.feature`)・対象 ATDD(@atdd_SPEC-001-04-3 / @atdd_SPEC-001-04-8)の Given / When / Then ごとに担当 UC を判定し、他 UC の責務を含む Scenario を着手前に一覧化する。S4 / S6 / S7 でのハーネス注入の要否を決める
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)
- 扱いの前例: `docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md`(この UC だけで判定できる部分を step で判定し、できない部分の責務分担をここに記録する)

## 判定結果の要約

| # | 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|---|
| 1 | UC BDD | runner 実体を差し替えても facade は変更不要である(SPEC-001-04) | When の後半(facade.sh JOB001 の実行)/ Then 2 行目(green/ に Runner Result の 3 ファイルが揃う) | 要(facade.sh が無い間は判定できない。下記) |
| 2 | UC BDD | facade は設定された runner を runner IF で起動するだけである(SPEC-002-03) | When(facade.sh JOB001 x y)/ Then 全体(facade が渡す引数と環境変数) | 要(同上) |
| 3 | tier BDD | 差し替えた runner 実体は runner IF だけで facade から起動できる | When(facade.sh JOB001 x)/ Then 全体 | 要(同上) |
| 4 | ATDD | SPEC-001-04-8 | Given(relay-gate の提供物の一覧) | 不要(照合先を下記に固定する) |

上記以外の Scenario(UC BDD 7 件・tier BDD 10 件・ATDD SPEC-001-04-3)は、Then がすべて `validate-config.sh --feature-flag` の終了コード・stdout・stderr、または配置ディレクトリのファイル(`runners/standard-runner.sh` と `lib/runner-*.sh`)だけを判定しており、本 UC の責務に閉じる。

## 仕様の記載と担当 UC の判定

### 1. runner 実体を差し替えても facade は変更不要である(SPEC-001-04)

| 行 | 文言(要約) | 担当 UC の判定 |
|---|---|---|
| Given | 並行稼働モード / 次世代実装用の自作の runner を作成 | 本 UC(runner の割当の前提)。自作の runner は step が置くスタブ |
| When 前半 | GREEN_RUNNER を差し替え、validate-config.sh が終了コード 0 | 本 UC |
| When 後半 | ジョブスケジューラが facade.sh JOB001 を実行する | facade.sh は UC「slot 実行モードを選択して runner を起動する」(09730858)の担当。本 UC の時点で facade.sh は無い |
| Then 1 行目 | facade.sh・速報クロスチェック runner / worker・hang-detector.sh・background-rerun.sh・abort-green.sh・標準の slot runner・共通ライブラリのファイルは変更されていない | 「差し替えの前後でファイルの内容が同じ」ことは本 UC で判定できる。ただし列挙されたファイルの大半は後続 UC が作るため、本 UC の時点で実在するのは標準の slot runner と共通ライブラリだけ |
| Then 2 行目 | green/ に Runner Result の 3 ファイルが揃う | facade.sh の起動(09730858)と、3 ファイルの公開(UC「実装スクリプトを実行して Runner Result を出力する」)の担当 |

### 2. facade は設定された runner を runner IF で起動するだけである(SPEC-002-03)

| 行 | 文言(要約) | 担当 UC の判定 |
|---|---|---|
| Given | 記録するスタブ runner を割り当てる / 両 slot のジョブマップに JOB001 の行 | 本 UC(割当)。スタブは step が置く |
| When | ジョブスケジューラが facade.sh JOB001 x y を実行する | 09730858 |
| Then | facade が渡す引数(--run-id … -- x y)と環境変数(GREEN_IMPL、RAPID_CROSSCHECK_RUNNER を渡さない) | facade.sh の振る舞いで、09730858 の担当 |

### 3. tier BDD「差し替えた runner 実体は runner IF だけで facade から起動できる」

2 と同じ。When と Then は facade.sh(09730858)の振る舞いで、本 UC の tier 実装(標準の slot runner の入口と共通ライブラリの配置)では green にできない。

### 4. ATDD SPEC-001-04-8(提供物の一覧)

| 行 | 文言 | 判定のしかた |
|---|---|---|
| Given | relay-gate の提供物の一覧 | spec.md「関連 USDM」の REQ-001 行の注記どおり、CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner` を一覧の正本とする。配置ディレクトリの中身は tier BDD「配置ディレクトリの runners には標準の slot runner があり ssh-runner_sh は無い」で判定する |
| When / Then | 標準の slot runner は正式な提供物として載っており、参考実装(仮採用)という扱いの runner は無い | (a) 契約の `standard_runner.file` が `runners/standard-runner.sh` で、`summary` が正式な提供物と述べている、(b) 配置ディレクトリ(facade/)の `runners/standard-runner.sh` が実行可能な通常ファイルで、`runners/ssh-runner.sh`(旧仕様の参考実装)が無い、の 2 点を実体で判定する |

## 実装で判明した事実

- S2 時点では全 step が not implemented の skeleton である。上記の横断部分も skeleton として転写した(転写ルールにより意訳・削除しない)
- 1〜3 は facade.sh が無いと When が実行できない。本 UC の実装範囲(オーケストレータの決定)は標準の slot runner の入口と共通ライブラリ 4 本の配置までで、facade.sh は含まない

## 決めてほしいこと(1〜3 の扱い)

S4 のゲート 4 は tier BDD の全 Scenario の pass、S6 は UC BDD の全 Scenario の pass を求める。1〜3 は facade.sh が無いと pass できないため、この UC で扱いを決める必要がある。

| 案 | 内容 | 長所 | 短所 |
|---|---|---|---|
| A(推奨) | S8 で仕様の変更要求を出し、facade.sh を起動する部分(2 と 3 の全体、1 の When 後半と Then 2 行目)を UC「slot 実行モードを選択して runner を起動する」(09730858)の Scenario へ移す。1 は本 UC に残る部分(差し替えて validate-config.sh が通り、標準の slot runner と共通ライブラリが変わらない)だけの形にする。変更要求が反映されるまで、1〜3 は本 UC のゲートで保留として記録する | 先行の前例(fd678b04 の `20260917_074633_cross-uc-scenarios-resolution.md`。facade.sh を起動する When / Then を仕様から外し、本 UC の出力だけで判定する形に改めた)と同じ解き方。各 UC のゲートが自分の責務だけで閉じる | 仕様の変更要求の往復が要る |
| B | 仕様は変えず、1〜3 を本 UC のゲートで保留にし、09730858 の S6 で本 UC の feature も合わせて流して green にする | 仕様の往復が要らない | 本 UC の feature の合否が別 UC の実装で決まり、どの UC のゲートで判定したかが追いにくい |
| C | facade.sh の代わりのスタブを注入して本 UC で green にする | 本 UC のゲートが閉じる | facade.sh の振る舞いそのものが判定対象のため、スタブでは何も確かめないことになる(採らない) |

## 提案

- S4(tier BDD の 3): 上の案 A または B のどちらでも、本 UC の S4 では green にできない。保留にする場合は step に本 issue のパスを書く
- S6(UC BDD の 1 と 2): 1 は When 前半と Then 1 行目のうち本 UC の時点で実在するファイル(標準の slot runner と共通ライブラリ)の内容が差し替えの前後で同じことを実体で判定し、facade.sh の起動と Then 2 行目は 09730858 の S6 で判定する。2 は 09730858 の S6 で判定する。どちらも facade.sh の代わりのスタブを注入しない(facade.sh の振る舞いそのものが判定対象のため、スタブで置き換えると何も確かめないことになる)
- S7(ATDD の 4): 上表の (a)(b) で判定する。(a) は契約 YAML を読む step、(b) はファイルの実体を見る step とする
- S8(feedback): 1 の Then は「本 UC の判定(差し替えで relay-gate のファイルが変わらない)」と「後続 UC の判定(3 ファイルが揃う)」が 1 Scenario に混ざっている。Then の責務分離を仕様側へ要求するかを検討する
