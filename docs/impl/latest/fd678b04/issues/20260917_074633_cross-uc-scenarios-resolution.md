# UC 横断 Scenario の解消 / 残存記録(S2 test-scaffold 再実行)

- uc_id: fd678b04(feature flag を設定する / configure-feature-flags)
- 起票 stage: S2 test-scaffold(spec event 20260917_050000_feedback_impl_feedback_fd678b04 追従の再実行)
- 対象の既存 issue: `docs/impl/latest/fd678b04/issues/20260917_004843_cross-uc-scenarios.md`(編集せず、本ファイルで解消 / 残存を記録する)
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 仕様の記載(spec event 適用後)

spec.md「E2E 完了条件(BDD)」の Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」が、
`validate-config.sh --feature-flag` の終了コード・stdout・stderr だけで判定する形に差し替わった。
spec.md の注記は「切り替え後の実行(green の結果が返り、blue は起動されず、管理 DB へ接続しない)は
UC『slot 実行モードを選択して runner を起動する』の Scenario で検証する。『ジョブ定義は変更していない』は
テストが facade.sh の起動やジョブ定義に触れないことを表す前提条件である」と定める。

tier-facade.md の「ティア完了条件(BDD)」は変更なし(既存 feature と完全一致)。

## 解消 / 残存

| 既存 issue の項目 | 判定 | 根拠 |
|---|---|---|
| 1. 運用モード切替 Scenario の When「ジョブスケジューラが facade.sh JOB001 を実行する」/ Then「green の結果が返り、blue は起動されず、管理 DB へ接続しない」 | 解消 | 当該 When / Then は spec から削除され、本 UC の責務(validate-config.sh の出力)だけで判定する形になった。S6 のハーネス注入(facade.sh スタブ・psql sentinel)は不要になり、`features/uc/steps/configure-feature-flags.steps.js` から撤去した |
| 1. Given「ジョブスケジューラのジョブ定義は facade.sh JOB001 のままである」 | 解消(前提条件化) | spec.md 注記により「テストが facade.sh の起動やジョブ定義に触れない」ことを表す前提条件。step は記録のみ(facade.sh を配置・起動しない) |
| 2. 正常系 3 Scenario の Given(runner が `--help` に "runner-if-version=1" を返す / `<slot>-job-map.csv` が存在する) | 残存 | 定義元は引き続き UC「slot runner の実体スクリプトを割り当てる」/ UC「slot ごとのジョブマップを定義する」。Then(終了コード 0・operation_mode)は本 UC の責務であり、前提の準備は既存の S6 step(一時ディレクトリの runner スタブ・ジョブマップ CSV)で満たしている。仕様変更は不要(責務分担の記録のみ) |

## 実装で判明した事実

- 変更 Scenario の新 step 4 件(Given 並行稼働の組合せで終了コード 0 / When 単独本番へ変更して実行 / Then "error:" 行なし / Then ジョブ定義は変更していない)は S2 skeleton(未実装 fail)として置いた。S6 uc-bdd で実装する
- 共有仕様 `cli-command-contract.yaml` の `runner_help_probe`(待機上限 4 秒 / 版の値が 1 でない場合は未応答 / 版行の前後空白除去 / 準備失敗は終了コード 6)に対し、既存実装 `facade/src/` には未追従の項目がある。④ TDD として red のテストを `facade/test/` に追加した(S4 再実行で追従予定。実装コードは S2 では変更しない):
  - `test/gateway/runner_probe.bats`: 既定待機上限 4 秒(pass。実装済み)/ 版の値の前後空白除去(red)/ 複数行は最初の 1 行(pass。実装済み)
  - `test/usecase/validate_feature_flag.bats`: 版が 1 でない場合は未応答扱い(red)
  - `test/presentation/validate_config.bats`: 一時ファイル作成失敗で `error: runner probe failed slot=<s> reason=<r>`・終了コード 6・stdout 空(red)

## 提案

- S6(UC BDD): 変更 Scenario の新 step を実装する。ハーネス注入は不要
- S4(tier-impl 再実行): 上記 red テストを green にする(gateway の版の値の trim / usecase の版 ≠ 1 判定 / presentation または gateway の準備失敗 → 6)
