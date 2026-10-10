# CLAUDE.md / dev-rules への提案(relay-gate)

既存の CLAUDE.md と `docs/dev-rules/` は変更していない。取り込むかどうかは保守者が判断する。

## 提案 1: `docs/dev-rules/tier-rules.md`「全種別共通」に、同じプロセスに source される tier の名前空間の規則を追加する

- 現状: 「全種別共通」は契約に無い tier 間依存の禁止だけを書く。bash の source で直接依存する tier の関数名・グローバル変数名の規則は無い。
- 問題: 速報クロスチェック tier の関数が確報 tier の同名関数に上書きされ、実プロセス経由のテストでだけ終了コード 6 になった(`issues/20261010_092630_tier-handler-function-namespace-collision.md`)。
- 提案(4 行):
  1. 同じプロセスに source される tier は、トップレベルの関数名・グローバル変数名に tier 固有の接頭辞を付ける(tier-rapid-crosscheck: `crosscheck_` / `CROSSCHECK_`、tier-final-crosscheck: `final_` / `FINAL_`、tier-ops: `ops_` / `OPS_`)。
  2. tier-facade の共有関数は、契約の共有面に列挙した名前(`job_map_*` / `csv_*` / `cli_field_*`)だけを他 tier から呼ぶ。それ以外の facade の名前は他 tier から参照しない。
  3. 他 tier が定義した名前を再定義しない。source されるファイルは関数の定義だけを行い、シェルオプションの変更・グローバル変数の上書き・コマンドの実行をしない。
  4. 統合前に同じ UC の全 tier の `declare -F` の集合を比較し、重複が無いことを確認する。
- 仕様側の規則は CR-dcd8234d-003 で求めた。仕様が確定したら、dev-rules はその規則を参照する形にする。

## 提案 2: `docs/dev-rules/tier-rules.md`「全種別共通」に、参照先ファイルへの入力規則の適用を明記する

- 現状: CLI 契約 `config_input_rules` の `scope` は「設定ファイルを読むすべての読み手」に共通規則を課すが、dev-rules には「検証対象から参照する別のファイル」も対象であることが書かれていない。
- 問題: 参照先カタログへの共通規則の抜けが 3 attempt 続けて blocker になり、attempt 上限に到達した(`learnings/20261010_104636_referenced-csv-shares-config-input-rules.md`)。
- 提案(2 行):
  1. 設定ファイルの検証で別のファイルを読む(参照解決・存在確認を含む)ときは、そのファイルにも `config_input_rules` を同じ関数で適用する。参照解決だけが目的でも省略しない。
  2. 参照先に対する入力規則の各項目(NUL / UTF-8 / BOM / CR / 重複列名 / クォート / 空白だけの行 / 列数)を、主ファイルと同じ粒度で bats に置く。

## 提案 3: CLAUDE.md「実装規約」に、tier 間の関数共有の方向を 1 行追加する(CR-dcd8234d-001 が確定した場合)

- 現状: CLAUDE.md の実装規約は言語・コメント・エアーギャップ・Runner Result Contract を書くが、`validate-config.sh` の委譲構造(facade の本体が他 tier の検証関数を source する)は書かれていない。
- 提案: CR-dcd8234d-001 で共有面と登録方法が確定したら、「`validate-config.sh` の本体は tier-facade が所有し、検証種別ごとの関数 `validate_config_<kind>` を所有 tier が `<tier>/src/presentation/validate_config_<kind>.sh` で提供する。CSV の解析・表記は tier-facade の共有関数を使い、他 tier は CSV パーサを持たない」を 1 行追加する。
- 確定前は追加しない(仕様の正本は distillery 側)。
