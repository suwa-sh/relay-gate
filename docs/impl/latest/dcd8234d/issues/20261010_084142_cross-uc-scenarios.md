# UC 横断 Scenario 一覧(S2 test-scaffold 起票)

- uc_id: dcd8234d(クロスチェックのジョブマップと比較定義を定義する / define-crosscheck-job-map-and-comparison-definitions)
- 起票 stage: S2 test-scaffold
- 目的: E2E Scenario(`features/uc/define-crosscheck-job-map-and-comparison-definitions.feature`)と対象 ATDD Scenario(@atdd_SPEC-004-04-5)の Given / When / Then ごとに担当 UC を判定し、他 UC の責務を含む Scenario を着手前に一覧化する。S6(UC BDD)/ S7(ATDD)でのハーネス注入の要否を確定する
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 判定結果の要約

| # | 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|---|
| 1 | UC BDD | 比較定義と対象カタログを検証する(SPEC-004-01) | Given 2 行目(/opt/compare/compare.sh と compare-v2.sh が実行可能)。比較ツールは外部システムであり、どの UC の成果物でもない | 不要(sandbox に実行可能なスタブを置く fixture で足りる) |
| 2 | UC BDD | クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04) | Then 2 行目の前半「slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ」。CSV クォート解析関数は UC「slot ごとのジョブマップを定義する」(eff24f55、完了済み)が tier-facade に実装した | 不要(実体で判定できる後半「タブ区切りのファイルは `error: header mismatch` で拒否される」を判定する。前半は別 issue `20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md` の tier 間依存の扱いに従う) |
| 3 | ATDD | SPEC-004-04-5 | なし(責務は本 UC) | 不要 |

上記以外の UC BDD Scenario(正常系 1 件・異常系 4 件)は、Then がすべて `validate-config.sh --crosscheck-job-map` / `--target-catalog` の終了コード・stdout・stderr だけを判定しており、本 UC の責務に閉じる。

## 仕様の記載と担当 UC の判定

### 1. 比較定義と対象カタログを検証する(SPEC-004-01)

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given 1 / 3 行目 | crosscheck-job-map.csv / target-catalog.csv の内容(DocString) | 本 UC(設定ファイルの定義) |
| Given 2 行目 | /opt/compare/compare.sh と /opt/compare/compare-v2.sh が実行可能である | 比較ツールは外部システム(spec.md「関連 RDRA モデル」外部システム: 比較ツール)。relay-gate のどの UC も生成しない。検証ルール 6(compare_command が実行可能)の前提として実行可能ファイルを置くだけでよい |
| When / Then 1〜2 行目 | 2 つの validate-config.sh の起動と stdout の順序 | 本 UC |
| Then 3 行目 | 管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない | 本 UC の検証コマンドが RDB に触れず読み取り専用であること(spec.md「概要」「速報と確報のモデル分離」)。本 UC の責務として判定できる |

### 2. クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04)

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given / When / Then 1 行目 | カンマを含む引用セルの解析と `status=valid` | 本 UC |
| Then 2 行目 前半 | slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ | CSV クォート解析関数の実体は tier-facade(`facade/src/repository/job_map_repo.sh` 系)にあり、UC eff24f55 の成果物。本 UC の tier(rapid / final)からの参照は impl-config の contracts[] に無い tier 間依存になる。「同じ関数が使われる」こと自体は実行結果からは判定できない(同じ解析結果になることまでしか判定できない) |
| Then 2 行目 後半 | タブ区切りのファイルは `error: header mismatch` で拒否される | 本 UC(ヘッダー検証ルール 2) |

### 3. ATDD SPEC-004-04-5

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given | クロスチェックジョブマップと対象カタログ | 本 UC(2 ファイルの fixture) |
| When | ファイル形式を確認する | 本 UC(`validate-config.sh --crosscheck-job-map` / `--target-catalog` を起動する) |
| Then | slot ジョブマップと同じ CSV 形式である | 本 UC(カンマ区切り・1 行目ヘッダー・引用セルの解析結果が受理されること) |

uc-map の atdd_scenarios はユーザー確認済み(atdd_confirmed: true)で本 UC に割り当てられている。3 step とも既存の ATDD step ファイルに同一文言は無く、ambiguous にならない(先行 UC の「設定を検証する」のような step 共有は不要)。

## 実装で判明した事実

- S2 時点では全 step が not implemented の skeleton であり、上記の横断部分も skeleton として転写した(転写ルールにより意訳・削除しない)
- 1 の Given 2 行目は、sandbox 配下に `/opt/compare/compare.sh` と同じ相対位置で `exit 0` の実行可能スタブを置けば成立する。他 UC のプロセス起動や状態遷移の注入は要らない
- 2 の Then 2 行目前半は「実装の構造(関数の共有)」を要求しており、CLI の実行結果だけでは真偽を判定できない

## 提案

- S6(UC BDD): 1 は World の sandbox に比較ツールのスタブを配置する(先行 UC の runner スタブと同じ方式)。2 の Then 2 行目は後半(タブ区切りの拒否)を実体で判定し、前半は「本 UC の tier が slot ジョブマップと同じ解析結果を返す(カンマを含む引用セル・二重化した引用符)」ことの判定で代替し、代替した旨と本 issue のパスを step のコメントに残す
- S8(feedback): 2 の Then 2 行目は「利用者が観測できる振る舞い(タブ区切りの拒否・引用セルの解析)」と「実装の構造(同じ関数を使う)」が 1 文に混ざっている。受け入れ基準を振る舞いだけに分離するか、関数共有を契約(impl-config の contracts[] または shared_spec_refs)として宣言するかを仕様側へ要求する(別 issue `20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md` と合わせて扱う)
