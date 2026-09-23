# UC 横断 Scenario 一覧(S2 test-scaffold 起票)

- uc_id: eff24f55(slot ごとのジョブマップを定義する / define-slot-job-maps)
- 起票 stage: S2 test-scaffold
- 目的: E2E Scenario(`features/uc/define-slot-job-maps.feature`)と対象 ATDD Scenario の Given / When / Then ごとに担当 UC を判定し、他 UC の責務を含む Scenario を着手前に一覧化する。S6(UC BDD)/ S7(ATDD)でのハーネス注入の要否を確定する
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 判定結果の要約

| # | 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|---|
| 1 | UC BDD | hang_detect_limit_minutes の変更は次回以降の run に反映される(SPEC-008-05) | Given(実行中 run の execution-spec.json)/ Then の 2 行目(execution-spec.json が 60 のまま) | 不要(fixture 配置で足りる) |
| 2 | UC BDD | 導入時は全ジョブ 60 分・foreground slot の行は 0 で定義する | Given(並行稼働モードで導入する) | 不要(前提の記録のみ) |
| 3 | ATDD | SPEC-008-05-2 | Then の前半(調整日時と調整根拠は適用構成文書に残る) | 不要(本 UC は後半だけを実体で判定) |
| 4 | ATDD | SPEC-004-04-4 | なし(責務は本 UC)。ただし When の step 文言が先行 UC と重複 | 不要(step 共有の拡張が必要。下記) |

上記以外の UC BDD Scenario(正常系 5 件・異常系 9 件)は、Then がすべて `validate-config.sh --job-map` の終了コード・stdout・stderr だけを判定しており、本 UC の責務に閉じる。

## 仕様の記載と担当 UC の判定

### 1. hang_detect_limit_minutes の変更は次回以降の run に反映される(SPEC-008-05)

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given | run_id=20260830T113000-JOB001-3f9a1c2e が execution-spec.json の slots.green.hang_detect_limit_minutes=60 で実行中である | execution-spec.json の生成は UC「execution-spec.json を確定保存する」、run の実行は UC「slot 実行モードを選択して runner を起動する」の責務 |
| When / Then 1 行目 | validate-config.sh --job-map ... --verbose → `info: resolved job_id=JOB001` と `hang_detect_limit_minutes=90` | 本 UC |
| Then 2 行目 | execution-spec.json の slots.green.hang_detect_limit_minutes は 60 のままである | 判定内容は「本 UC の検証コマンドが読み取り専用で既存 run の成果物を書き換えない」こと。本 UC の責務として判定できる |

spec.md「関連 USDM」の SPEC-008-05 行が、本 Scenario を「検証側」と明記し、実行側(次回以降の run に新しい上限が反映される)を UC「hang_detect_limit_minutes をジョブごとに調整する」へ分離済みである。Then に他 UC が遷移させる状態は含まれない。

### 2. 導入時は全ジョブ 60 分・foreground slot の行は 0 で定義する

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given | 並行稼働モード(blue foreground / green background)で導入する | feature flag の組合せは UC「feature flag を設定する」(fd678b04、完了済み)の責務。本 Scenario では前提の説明であり、When / Then は feature flag を読まない |
| When / Then | 両ジョブマップを validate-config.sh で検証し、両方とも終了コード 0 | 本 UC |

### 3. ATDD SPEC-008-05-2

| 行 | 文言 | 担当 UC の判定 |
|---|---|---|
| Given / When | hang_detect_limit_minutes を調整した / 調整の記録を確認する | 調整の運用は UC「hang_detect_limit_minutes をジョブごとに調整する」。本 UC はジョブマップの列定義側 |
| Then 前半 | 調整日時と調整根拠(警告時経過時間)は適用構成文書に残り | 適用構成文書は relay-gate が読まない文書(spec.md バリエーション一覧「設定所有区分 = 適用文書」)。実体で自動判定できる対象が無い |
| Then 後半 | ジョブマップの列には持たない | 本 UC(契約の 9 列に調整記録の列が無い。未知列は `warn: unknown column`) |

uc-map の atdd_scenarios はユーザー確認済み(atdd_confirmed: true)で本 UC に割り当てられている。

### 4. ATDD SPEC-004-04-4(step 文言の重複)

- When「設定を検証する」は @atdd_SPEC-001-01-4(fd678b04、完了済み)と同一文言である
- 既存定義は `features/atdd/steps/configure-feature-flags.steps.js` にあり、`validate-config.sh --feature-flag` を起動する
- 同じ文言を本 UC の step ファイルで再定義すると cucumber が ambiguous step として扱うため、S2 では定義していない

## 実装で判明した事実

- S2 時点では全 step が not implemented の skeleton であり、上記の横断部分も skeleton として転写した(転写ルールにより意訳・削除しない)
- 1 の Given は、担当 UC が未実装でも execution-spec.json の fixture(`slots.green.hang_detect_limit_minutes=60` を含む JSON)を一時ディレクトリに置けば成立する。他 UC のプロセス起動や状態遷移の注入は要らない
- 4 は仕様の矛盾ではない。USDM の acceptance_criteria が SPEC をまたいで同じ When 文言を使うために起きる、ハーネス側の制約である

## 提案

- S6(UC BDD): 1 は execution-spec.json の fixture を sandbox に配置し、検証コマンド実行の前後でファイル内容が一致することを判定する。fixture の最小形は `{"slots":{"green":{"hang_detect_limit_minutes":60}}}` とし、注入箇所のコメントに本 issue のパスを書く(execution-spec.json の全体形式は担当 UC の契約が正本)。2 の Given は前提の記録だけにする
- S7(ATDD): 3 の Then 前半は「ジョブマップ側に調整記録の置き場が無いこと」の確認(契約 9 列に該当列が無い + 調整記録らしい列を足すと `warn: unknown column` になる)で代替し、適用構成文書そのものは判定対象外とする旨を step のコメントに残す。4 は既存 step「設定を検証する」を、Given が World に置いた検証種別(`--feature-flag` / `--job-map`)で起動を切り替える形へ拡張する。@atdd_SPEC-001-01-4 の結果を変えないことを、拡張後にタグ指定で再実行して確認する
- S8(feedback): SPEC-008-05-2 の Then は「relay-gate が判定できる事実(ジョブマップの列に持たない)」と「運用文書の記載(適用構成文書に残る)」が 1 文に混ざっている。受け入れ基準の分離を仕様側へ要求するかを検討する
