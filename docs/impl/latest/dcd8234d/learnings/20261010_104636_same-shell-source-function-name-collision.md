# 同じシェルに source される tier どうしで関数名が衝突し、黙って上書きされた

## 何が起きたか

- `validate-config.sh` の本体(tier-facade)は、速報クロスチェックと確報クロスチェックの検証関数ファイルを同じシェルに順に source する。
- 速報側の実装(attempt 2)が repository 層に `target_catalog_repo_load` を定義した。確報側にも同名の関数があり、後から source された確報側の定義で上書きされた。
- 両者は戻り値の意味が違うため、`--crosscheck-job-map` の対象カタログ参照の解決が内部障害(終了コード 6)になった。
- shellcheck でも、tier 単独で source する bats でも検出されなかった。facade の本体を実プロセスとして起動する presentation 層のテストでだけ現れた。

## 原因

- bash は関数の再定義をエラーにしない。source の順序で最後の定義が勝つ。
- dev-rules・契約・tier 仕様のどこにも、同じプロセスに読み込まれる tier 間の名前空間の規則が無かった。
- 各 tier は並走で実装され、相手 tier の関数名を見る機会が無い。衝突は統合時にだけ起こる。

## 回避方法

- tier が定義するトップレベルの関数名・グローバル変数名に tier 固有の接頭辞を付ける(速報: `crosscheck_` / `CROSSCHECK_`。確報は既存名のまま)。
- 他 tier の名前を再定義しない。共有してよい名前は facade の共有関数(`job_map_*` / `csv_*` / `cli_field_*`)だけに限る。
- 統合前に両 tier の `declare -F` の集合を `comm` で比較し、重複が無いことを確認する(今回は実装者と独立検証の双方が行った)。
- 実プロセス経由のテスト(facade の本体を起動する bats)を各 tier の presentation 層に置く。単体 source のテストだけでは衝突を見つけられない。

## 次回の対応

- 名前空間の規則は仕様側に求めた(CR-dcd8234d-003)。dev-rules への追記は `proposal-context.md` に書いた。
- 同じプロセスに source される tier を追加する UC(ops など)では、着手前に既存 tier のトップレベル名の一覧を取り、接頭辞を決めてから実装する。
- 関数名の重複検出をスクリプト化して統合テストのゲートに加える(`proposal-skill.md` の提案)。
