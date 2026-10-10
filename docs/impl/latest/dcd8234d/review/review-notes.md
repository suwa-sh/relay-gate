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
