# UC 横断 Scenario 一覧(S2 test-scaffold 起票)

- uc_id: fd678b04(feature flag を設定する / configure-feature-flags)
- 起票 stage: S2 test-scaffold
- 目的: E2E Scenario(`features/uc/configure-feature-flags.feature`)の Then ごとに担当 UC を判定し、他 UC の責務を含む Scenario を着手前に一覧化する。S6(UC BDD)でのハーネス注入の要否を確定し、S8 で仕様側へ「Then の責務分離」を要求できるようにする
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 仕様の記載

spec.md「E2E 完了条件(BDD)」の次の Scenario が、本 UC(validate-config.sh --feature-flag の検証)の責務を超える Then / Given を含む。

### 1. ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| When | ジョブスケジューラが facade.sh JOB001 を実行する | UC「slot 実行モードを選択して runner を起動する」(実装切替業務)/ UC「切り替えた運用モードで業務ジョブを実行する」 |
| Then | green の結果が返り、blue は起動されず、管理 DB へ接続しない | 同上(facade.sh の起動制御と管理 DB 非接続は本 UC の実装範囲外) |

本 UC が担う部分は Given「feature-flag.env を並行稼働から単独本番の組合せへ変更し validate-config.sh が終了コード 0 を返した」のみ。

### 2. 並行稼働モードの feature flag を検証する(SPEC-001-01)/ 単独本番モード / 次世代並行稼働モード(SPEC-001-03)

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given | 両 runner は --help に "runner-if-version=1" を返す / `<slot>-job-map.csv` が存在する | UC「slot runner の実体スクリプトを割り当てる」(runner IF 応答と stdout 末尾 4 行 blue_job_map / green_job_map / blue_runner_if_version / green_runner_if_version の定義元)/ UC「slot ごとのジョブマップを定義する」(ジョブマップの存在) |

Then 自体(終了コード 0、operation_mode=...)は本 UC の責務。ただし tier-facade.md の「終了コード 2」条件に「対応ジョブマップなし」が含まれるため、前提の準備(runner スタブ・ジョブマップ)は S6 で本 UC の step 側に用意する必要がある。

## 実装で判明した事実

- S2 時点では全 step が not implemented の skeleton であり、上記の横断部分も skeleton として転写した(転写ルールにより意訳・削除しない)
- 1 の Scenario は facade.sh の実装(別 UC。fd678b04 の tiers は tier-facade のみだが、facade.sh 起動制御は別 UC の tier-facade 完了条件)が無いと green にできない

## 提案

- S6(UC BDD): 1 の Scenario は担当 UC 未実装の間、当該 When / Then の step をハーネス注入(暫定注入。本 issue のパスをコメントに書き、契約確定後に削除)するか、担当 UC の S6 完了後に再実行する。2 の Given は本 UC の step 側で一時ディレクトリに runner スタブ(`--help` で `runner-if-version=1` を返す)とジョブマップ CSV を作る(実体テストの規約どおり)
- S8(feedback): spec.md の Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」の Then を、本 UC の責務(検証が終了コード 0)と実行側 UC の責務(facade.sh の起動結果)に分離する変更要求を検討する
