# NEXT: ジョブマップで JOB_ID から実行先を解決する(7c41c7cd)

- state: **completed**(仕様への要求 0 件。還流は不要。PR 作成へ進む)
- 承認: `review_approved` event `20261126_090000_review_approved_7c41c7cd_final`(S9 evidence `20261124_050000_s9_review_generated_7c41c7cd`)。前提 23 件すべて confirmed
- 取り込み準備: `delivery_prepared` event `20261126_090001_delivery_prepared_7c41c7cd_resolve_execution_target_from_job_map`
- 生成日時: 2026-11-26T09:00:01+09:00

## この周回でしたこと

- 2026-11-23 に公開した要望 3 件(入力の複製の作業名 / 自作 runner 向け共通ライブラリ / 読めないジョブマップの報告)が仕様へ反映された後の再実行
- 実装の欠陥 2 件を直した(仕様は変えない)
  - 入力の複製の最終名に先にディレクトリやリンクがあると、中身をすり替えられる(`facade/src/repository/job_map_repo.sh`)
  - runner の結果ファイルの確定名に先にディレクトリなどがあると、終了コード 6 にならず `exitcode.txt` を公開する(`facade/src/gateway/filesystem_adapter.sh`)
- 実装のやり直しは利用者の承認で上限 5 回まで延ばした

## 取り込み

- base: `main`(`aa69938`)/ feature branch: `feature/resolve-execution-target-from-job-map`
- squash commit message: `feat: ジョブマップで JOB_ID から実行先を解決する`
- **注意**: feature branch には `impl(bootstrap): rerun P2 ...` の commit が混在する(仕様の反映がこの branch にしか無いため、ここで bootstrap を再実行した)。squash に含まれる
- PR の存在は GitHub が正(`gh pr list --state all --head feature/resolve-execution-target-from-job-map`)

## 次の機能へ引き継ぐこと

- ATDD「組み立てた引数で実装を起動する」の 1 件は、実装が受け取った引数の確認だけが後続の機能(実装スクリプトの実行)待ちで保留
- UC BDD 全体の保留 1 件(`select-slot-mode-and-launch-runners.feature:94`)は execution-spec.json の保存を担う機能待ち
- 一時ファイルの名前に他の利用者のファイルがある場合はテストしていない(コードの確認のみ)。Linux では未実行
