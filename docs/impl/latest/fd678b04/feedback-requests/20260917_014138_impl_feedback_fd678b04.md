---
schema_version: distillery.feedback-request/v1
feedback_id: 20260917_014138_impl_feedback_fd678b04
created_at: 2026-09-17T01:41:38+09:00
source: distillery-impl
uc_id: fd678b04
---

# 実装からの変更要求

## CR-fd678b04-001: 運用モード切替 Scenario の Then を検証側と実行側の責務に分離する

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-03]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md, docs/usdm/latest/requirements.yaml]

### 観測した事実

UC「feature flag を設定する」の E2E 完了条件(BDD)にある Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」は、次の When / Then を持つ。

```gherkin
Given ジョブスケジューラのジョブ定義は facade.sh JOB001 のままである
And feature-flag.env を並行稼働から単独本番の組合せへ変更し validate-config.sh が終了コード 0 を返した
When ジョブスケジューラが facade.sh JOB001 を実行する
Then green の結果が返り、blue は起動されず、管理 DB へ接続しない
```

この UC の実装範囲は `validate-config.sh --feature-flag`(tier-facade)だけである。facade.sh の起動制御と管理 DB 非接続は UC「slot 実行モードを選択して runner を起動する」の完了条件であり、同 UC には既に Scenario「新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03)」がある。

この UC の統合テストでは、facade.sh が未実装のため、上記の When / Then を「検証済み feature-flag.env を読んで off でない slot の runner だけを起動する暫定スタブ」で代替して pass させた。この pass はスタブに対するものであり、facade.sh の実装を検証した証跡ではない。暫定スタブは担当 UC の実装完了後に削除する前提で、削除条件を統合テストの記録に残している。

### 現在の仕様と問題

spec.md の E2E 完了条件は「この UC の実装で green にできる Scenario」の集合として扱われる。しかし上記 Scenario は Given だけがこの UC の責務で、When / Then は別 UC の責務である。結果として次の問題が起きる。

- この UC の統合テストが、別 UC の成果物(facade.sh)の有無に依存する。実装順序が UC 単位で進む間は、暫定スタブでしか通せない
- 暫定スタブで通した pass が、要件 SPEC-001-03 の受け入れ条件「Given ジョブスケジューラのジョブ定義を変更しない When feature flag だけを変更する Then 並行稼働と単独本番を切り替えられる」の証跡として誤読されうる
- USDM トレーサビリティ表(spec.md「関連 USDM」)で SPEC-001-03 の対応 Scenario にこの Scenario が並び、検証側と実行側の責務境界が表からは読めない

方針資料(RelayGate のしくみ)の受入条件「ジョブスケジューラの同じジョブ定義で、並行稼働と単独本番を設定だけで切り替えられます」は維持する。要求は Scenario の意図を弱めることではなく、検証できる UC に Then を置き直すことである。

### 変更してほしいこと

- UC「feature flag を設定する」の Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」を、この UC の CLI で観測できる Then に書き換える。例: 「Given ジョブスケジューラのジョブ定義は facade.sh JOB001 のままである And feature-flag.env を並行稼働の組合せで validate-config.sh が operation_mode=parallel を返した When feature-flag.env を単独本番の組合せへ変更して validate-config.sh --feature-flag を実行する Then 終了コード 0 で stdout に operation_mode=green_only が出る And ジョブ定義は変更していない」
- 実行側の Then(「green の結果が返り、blue は起動されず、管理 DB へ接続しない」)は UC「slot 実行モードを選択して runner を起動する」の既存 Scenario「新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03)」で覆う。不足があれば同 Scenario へ「ジョブ定義を変更していない」前提を追記する
- spec.md「関連 USDM」の SPEC-001-03 行に、実行側の受け入れ条件は UC「slot 実行モードを選択して runner を起動する」で覆う旨の「※」補足を置く(同表の SPEC-001-01 行の書き方に揃える)
- 同様の形(Given だけが自 UC、When / Then が他 UC)の Scenario が他 UC の spec.md にもあれば、同じ方針で分離する

### 完了条件

- UC「feature flag を設定する」の E2E 完了条件の全 Scenario が、`validate-config.sh --feature-flag` の実行結果(終了コード・stdout・stderr)だけで Then を判定できる
- 「ジョブ定義を変えずに設定だけで切り替える」意図が、検証側 UC と実行側 UC の Scenario の組で SPEC-001-03 に紐づいている
- spec.md「関連 USDM」の SPEC-001-03 行から、検証側と実行側の責務境界が読める

## CR-fd678b04-002: runner --help 問い合わせの待機上限と未応答判定を validate-config.sh の契約に一元化し NFR と整合させる

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-04, B.2.1.1]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md, docs/nfr/latest/nfr-grade.yaml]

### 観測した事実

`validate-config.sh --feature-flag` は blue / green の runner 実体に `--help` を問い合わせ、`runner-if-version=1` の応答を確認する。この問い合わせに関する規則は次のように分散している。

- CLI 契約(cli-command-contract.yaml の validate-config.sh)と UC「feature flag を設定する」の tier-facade.md は、未応答時に `warn: runner does not respond to --help ...` を出し `<slot>_runner_if_version=-` にするとだけ定める。待機上限は書かれていない
- UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md「UC ロジック」に「`--help` の呼び出しは 5 秒でタイムアウト(応答なしは warn。仮採用)」とある。同ファイルは「UC『feature flag を設定する』の契約に以下を追加する」と述べて検証項目を追加している

実装では、この UC の spec と CLI 契約だけを照合して「待機上限は仕様に無い」と判断し、NFR B.2.1.1(CLI 応答 10 秒以内)から逆算して 1 slot あたり 4 秒の待機上限を置いた。独立した検証でも同じ箇所を「仕様に照合先が無い」と判定し、別 UC の tier-facade.md にある 5 秒の記述は実装・検証の双方が参照しなかった。

実測では、両 runner が応答しない場合に 2 回の問い合わせを逐次実行して約 9.1 秒で復帰した(待機上限 4 秒 × 2 slot + 停止処理)。

加えて、未応答の判定基準について次の点が仕様に無く、実装で判断した。

- runner が `runner-if-version=` 行を出力しつつ非 0 で終了した場合の扱い
- `runner-if-version=` 行が複数ある場合の採用規則
- 問い合わせ用の一時ファイル作成に失敗した場合(runner ではなく検証側の障害)を runner 未応答と区別するか

### 現在の仕様と問題

- 待機上限の正本が、コマンドを定義する UC の契約ではなく、検証項目を「追加する」別 UC の tier md にある。コマンド単位で仕様を読む実装者・検証者が見落とす構造になっており、実際に見落とした
- 仮採用の 5 秒を 2 slot 逐次に適用すると、待機だけで 10 秒となり NFR B.2.1.1 の「10 秒以内」を停止処理と出力の分だけ超える。5 秒と NFR の両方を満たすには、問い合わせを並列にするか、上限を短くする必要があるが、どちらにするかが仕様に無い
- 未応答判定の細則(非 0 終了・版行の重複・検証側の一時ファイル障害)が無いため、実装ごとに挙動が変わりうる。特に検証側の障害を runner 未応答として warn で継続すると、利用者は設定の問題と検証器の障害を区別できない

### 変更してほしいこと

- runner `--help` 問い合わせの規則を、CLI 契約(cli-command-contract.yaml)の validate-config.sh の項に一元化する。UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md はその契約を参照する形にし、値を二重に持たない
- 一元化する規則に次を含める
  - 1 slot あたりの待機上限(秒)と、blue / green への問い合わせを逐次にするか並列にするか。NFR B.2.1.1(10 秒以内)を、両 slot が未応答でも満たす値にする
  - 待機上限に達した runner プロセスの扱い(停止するか、放置するか)
  - 「応答しない」の判定基準: 非 0 終了・`runner-if-version=` 行なし・行が複数ある場合の採用規則
  - 問い合わせの準備(一時ファイル作成など)に失敗した場合は runner 未応答と区別し、CLI 共通の実行エラー(終了コード 6)として報告すること
- 上記の値と方式は、現行実装をレビューした結果として次の希望値を採用してほしい
  - 1 slot あたりの待機上限は 4 秒とする
  - blue / green への問い合わせは逐次に行う(並列にしない)
  - 待機上限に達した runner は、runner のプロセスグループへ TERM を送り、0.2 秒後に KILL を送って停止し、その slot を「応答しない」(warn + `<slot>_runner_if_version=-`)として扱う
  - この組合せは現行実装の値であり、両 slot が未応答でも約 9.1 秒で復帰し NFR B.2.1.1 の 10 秒以内に収まる
  - UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md にある 5 秒(仮採用)は、この 4 秒に置き換える
- 5 秒が仮採用として todo に記録されているなら、確定値(4 秒)に更新する

### 完了条件

- validate-config.sh の CLI 契約だけを読めば、`--help` 問い合わせの待機上限・実行方式・未応答判定・検証側障害の扱いを推測なしに実装できる
- 両 slot の runner が応答しない場合の CLI 応答時間が、契約の値から NFR B.2.1.1 以内と計算できる
- UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md に、CLI 契約と異なる待機上限の値が残っていない
