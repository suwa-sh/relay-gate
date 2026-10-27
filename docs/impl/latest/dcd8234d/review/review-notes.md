# review notes (dcd8234d)

## 2026-10-10 S2 後のオーケストレータ判断(S9 でユーザーに提示する)

- 事実: validate-config.sh のエントリポイントは tier-facade 所有で、--crosscheck-job-map / --target-catalog の検証ロジックは本 UC の tier(rapid / final)が `validate_config_<kind>` 関数として提供する(契約 tier_note / owner_tier、tier md「変更概要」= bash の source で直接依存、CLP-003)。ただし facade 側に他 tier の関数を source する行が無く、本 UC の write-set(rapid-crosscheck/ final-crosscheck/)だけでは動かない(issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)
- 判断: dist-impl-run の既定 ③(cross-UC/tier 依存は issues 起票つきの意図的逸脱で統合を通し、S8 で変更要求化)を採用。単一 writer(オーケストレータ)が S4 dispatch 前に facade/src/presentation/validate-config.sh へ handler 登録(固定パス 2 件を存在時のみ source)を 1 commit で追加した。uc-map の tiers は変えない(tier-facade を追加して S1 からやり直す案は不採用)
- CSV クォート解析関数(facade job_map_repo.sh の csv_parse 系)の再利用は仕様(spec.md Then「同じ CSV クォート解析関数が使われる」)に明示されているが、tier 間依存として契約宣言が無い。S4 では暫定依存(issue 参照コメント + AssumptionRecord)として許可し、S8 で契約宣言の変更要求を出す
- 未決(S9 で確認): (a) facade 側の登録方式(固定パス source)を契約として宣言するか、(b) CSV 解析関数の共有を contracts[] / shared_spec_refs のどちらで宣言するか

## 2026-10-10 attempt 上限到達の判断

- 独立検証 3 回目(attempt 3)で rapid 側に blocker 1 件(1 列カタログの空白だけの行を受理)が残存。final 側は合格
- レビュー HTML: tmp/reviews/crosscheck-config-attempt-limit-review.html
- ユーザー回答: 「A: 4 回目の実装と独立検証を許可します。残った 1 件を直してください」→ attempt 4 を continue_once で開く

## 2026-10-10 レビュー対話での仕様選択(承認前。S8 refresh の入力)

- ユーザー質問: 「target-catalog.csv は何の対象か。クロスチェック自体は別ツールが行うので対象一覧は不要。速報は blue/green のジョブ情報を渡し、確報は何も渡さずキックするだけ」
- 調査結果: 方針資料にあるのは確報依頼の「business_date」「対象カタログの版」と所有者(クロスチェックの job map)だけ。5 列 CSV・検証・比較ツールへの {catalog_path} 受け渡しは仕様策定フェーズの推論(仮採用)
- ユーザー決定(案 A): 確報クロスチェックは比較ツールを起動するだけ。対象カタログ(target-catalog.csv / validate-config.sh --target-catalog / 確報依頼の catalog_version)と business_date を relay-gate から外す(「relay-gate はアプリ独自 DB の業務日付を参照できない」)。速報の {blue} / {green} はそのまま
- 影響: 本 UC の確報側(tier-final-crosscheck の対象カタログ検証)は仕様反映後に削除。比較定義(速報側)の予約行 final-crosscheck のカタログ参照(ヘッダーコメント target_catalog_path / catalog_version、検証ルール 9、{catalog_path} {catalog_version} {business_date} プレースホルダ)も不要になる。確報 runner / worker の UC、CLI 契約、RDB スキーマ(final_crosscheck_requests.business_date / catalog_version)、USDM(SPEC-004-01 / 004-04 / 006-01)、方針資料(tmp/ の確報依頼データ項目)を揃える
- 手順: review_approved は記録せず、S8 を mode=refresh で再実行して変更要求 CR-006 を追加(CR-005 のカタログ関連部分を整理)→ S9 再生成 → 再レビュー → 公開許可 → blocked_on_spec

## 2026-10-10 レビュー対話での仕様選択(第 2 回。簡素化案で確定。S8 refresh の入力)

- ユーザーの元の構想: 「blue/green-runner → DB ← worker → 比較ツール」「確報 runner → DB ← worker → 比較ツール」。速報はジョブ ID を渡す、確報はパラメータなし。worker は任意の比較コマンドを 1 つ定義でき、速報はそのパラメータを動的に渡せる。現在の仕様(ジョブ ID ごとの比較定義 CSV・比較対象/定義版の列・成果物パスの受け渡し・対象カタログ・検証ルール群)は複雑にし過ぎ
- 想定環境の制約: runner と worker は別ネットワークセグメントで動く。worker はファイルパスを渡されても読めない。必要な情報は DB の依頼レコードに含める
- 確定した内容:
  1. 速報の起動コマンド: 設定に 1 行。プレースホルダは依頼レコードの値だけ: {job_id}(必須)、{run_id} {params} {blue_exit_code} {green_exit_code}(任意)
  2. 確報の起動コマンド: 設定に 1 行。プレースホルダなし。runner は引数なしで起動するだけ(business_date / catalog_version なし)
  3. 完了通知で DB に入れる値: run_id、job_id、exit_code(成果物パス artifact_uri は外す)。速報の依頼レコードは run_id / job_id / parameters / blue・green の exit_code を持つ
  4. worker の結果保存: 依頼レコードの stdout / stderr / exitcode 列だけ(runner 側成果物ディレクトリへのファイル保存は外す)。状態は exitcode 0 → SUCCEEDED、非 0 または起動失敗 → FAILED
  5. 速報の比較結果レコード(difference_count / report_uri の抽出)は廃止し、標準出力をそのまま保存するだけにする
  6. 確報の依頼レコードは識別子・状態・時刻・結果(stdout / stderr / exitcode)だけ。確報 runner は保存された値をそのままスケジューラへ返す。速報はスケジューラへ返さない
  7. 廃止: ジョブ ID ごとの比較定義 CSV(crosscheck-job-map.csv の行構造)、比較対象・定義版の列、対象カタログ、{blue} {green} のパス受け渡し、worker のファイル保存、検証ルール群。検証は「コマンドが絶対パスで実行可能」「速報に {job_id} がある」の 2 点
- 手順: 第 1 回(案 A)の CR-006 を含む 6 件を、この簡素化に統合した要求に書き直す(S8 refresh 第 2 回)→ S9 再生成 → 再レビュー → 公開 → blocked_on_spec。第 1 回向けの S9 再生成は方針変更のため中断(done 未作成)

## 2026-10-10 承認(要求公開許可)

- レビュー HTML(簡素化版)へのユーザー回答: 機能=A / 要求=公開 / 登録=A / 前提=一括承認
- 意味: 現在の到達点の記録承認 + 変更要求 4 件の公開許可。delivery approval ではない(仕様反映後に再レビュー)

## 2026-10-27 仕様還流後の再レビュー(S9 evidence 20261027_092806_s9_review_generated_dcd8234d)

- ユーザー回答(原文): 機能=A(この実装を承認する) / 要求=公開(要求と受け入れ基準を、仕様の 3 点の検証に揃える変更要求を出す) / 前提=A-009:却下(仕様変更: 引用符の外し方を、契約の 2 か所とも今の実装の規則=先頭と末尾を別々に 1 文字ずつ外す、に揃えて書く) / 前提=A-012:承認 / 前提=残り10件:一括承認
- 却下した前提: tier-facade A-009(spec_change)。期待: CLI 契約の引用符除去の 2 か所の記述を、現行実装の規則(先頭と末尾の引用符を別々に 1 文字ずつ外す。対の一致は要求しない)に揃える。実装コードは変更しない
- 承認した前提: A-012(--final-crosscheck は受理して未実装の終了コード 6)、残り 10 件
- 手順: review_approved は記録せず、S8 を mode=refresh で再実行して A-009 の仕様変更要求を追加 → S9 再生成 → 回答と exact に一致すれば公開許可として記録 → S8 publish → blocked_on_spec
