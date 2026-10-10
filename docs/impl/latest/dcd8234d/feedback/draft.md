---
schema_version: distillery.feedback-request/v1
feedback_id: 20261010_104636_impl_feedback_dcd8234d
created_at: 2026-10-10T10:46:36+09:00
source: distillery-impl
uc_id: dcd8234d
---

# 実装からの変更要求

## CR-dcd8234d-001: validate-config.sh の検証ロジックの委譲と CSV 解析関数の共有が、ティア間の契約として宣言されていない

- severity: spec-gap
- related_ids: [SPEC-004-04, REQ-004, CLP-003]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md]

### 観測した事実

- `validate-config.sh` の本体(エントリポイント)は速報・確報クロスチェックのティアではなく、既存の facade ティアが所有する。CLI 契約の `tier_note` と `options[].owner_tier` は、`--crosscheck-job-map` の検証ロジックを速報クロスチェックティアに、`--target-catalog` を確報クロスチェックティアに割り当てる。
- 両ティアの仕様「変更概要」は、各ティアが検証関数を提供し、本体が「bash の source で直接依存(CLP-003)」すると書く。
- UC 仕様の E2E 完了条件(SPEC-004-04)の Then は「slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ」と書く。その関数(CSV の複製・バイト点検・クォート解析、出力フィールドの表記)の実体は facade ティアにある。
- 一方、実装リポジトリのティア間依存の宣言(契約一覧)には管理 DB のスキーマ 1 件しか無い。facade ティアと両クロスチェックティアのあいだの関数共有は、どちらの方向も宣言されていない。
- 開発規約「全種別共通」は、契約に無いティア間依存を実装で直接結ばず、変更要求で契約宣言の追加を求めると定める。
- 本 UC の実装は、次の 2 つの暫定依存で統合テストを通した。
  - facade ティアの本体が、両クロスチェックティアの固定パス(`<tier>/src/presentation/validate_config_<kind>.sh`)を存在時のみ source して `validate_config_<kind>` 関数を登録する(本 UC の書き込み範囲外の facade に 1 commit で追加)。
  - 両クロスチェックティアが、facade ティアの CSV 読み込み関数と出力フィールド表記関数を、本体が先に source している前提でそのまま呼ぶ(両ティアとも CSV パーサを持たない)。
- 独立検証は 4 回とも、この依存を「利用者が確定した意図的な逸脱」として blocker にせず minor で残した。実装者の前提記録にも両ティアで記録されている(確報ティア A-018 / A-019、速報ティア冒頭の除外事項)。
- レビュー対話(2026-10-10)で、利用者は確報クロスチェックの対象カタログと `--target-catalog` を relay-gate から外す決定をした(CR-dcd8234d-006)。この決定後、本要求の対象は facade ティアと速報クロスチェックティアの 2 ティア間の共有だけになる。

### 現在の仕様と問題

- UC 仕様とティア仕様は「直接依存で共有する」と書き、開発規約は「契約に無い直接依存は禁止」と書く。両方を同時に満たす実装は無い。
- 共有面(どの関数を、どのティアが提供し、どのティアが使うか)が仕様に無いため、実装者が共有する関数の集合を自分で決めた。facade ティアが共有関数の名前や引数を変えると、利用側のティアが黙って壊れる。
- 検証関数の登録方法(固定パスを source する)も仕様に無い。facade ティアの本体に他ティアのパスを直書きしており、ティアを追加するたびに facade 側を書き換える。
- 元の方針資料との照合結果: 方針資料は「設定ファイルは同じ CSV 形式」「`validate-config.sh` で検証する」ことを定めるが、スクリプトの内部構成(ティア間の関数共有)の記載は無い。どちらの方向に決めても方針資料と矛盾しない。

### 変更してほしいこと

1. facade ティアと速報クロスチェックティアのあいだの依存を、ティア間の依存ルール(CLP-003 と同じ階層)と契約として明記する。次の 2 方向を区別する。
   - facade ティアが提供する共有関数(CSV の単一スナップショット・バイト点検・クォート解析、出力フィールドの可視表記)を、速報クロスチェックティアが使う。
   - 速報クロスチェックティアが提供する検証関数(`validate_config_<kind>`)を、facade ティアの本体が使う。
   - 確報クロスチェックティアは CR-dcd8234d-006 の反映で `validate-config.sh` の検証関数を持たなくなる。確報側の共有は宣言しない(将来ティアを追加する場合は同じ契約の形で追加する)。
2. 検証関数の登録方法を 1 つに決める。
   - 案 A(現在の実装): facade ティアの本体が、所有ティアの固定パス `<tier>/src/presentation/validate_config_<kind>.sh` を存在時のみ source する。関数名は `validate_config_<kind> <path> <verbose>`。
   - 案 B: facade ティアの本体が、設定したディレクトリ配下の検証関数ファイルを探索して source する(ティア追加時に facade 側を変えない)。
   - 推奨は案 A である。本 UC で動作確認済みで、探索の順序と衝突の規則を新たに決めなくてよい。
3. 共有関数の集合(関数名・引数・戻り値・出力)を契約の共有仕様として 1 か所に書き、速報クロスチェックティアの仕様からはその場所を参照する形にする。

### 完了条件

- facade ティアと速報クロスチェックティアの依存が、提供側・利用側・共有する関数の集合を含めて契約として読める。
- 検証関数の登録方法(パスと関数名)が仕様から一意に決まる。
- 開発規約「契約に無いティア間依存の禁止」と、ティア仕様「直接依存で共有する」が矛盾しない。

## CR-dcd8234d-002: 受け入れ基準の Then に「同じ関数を使う」という実装構造の要求が混ざり、テストで判定できない

- severity: spec-gap
- related_ids: [SPEC-004-04, REQ-004]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md, docs/usdm/latest/requirements.yaml]

### 観測した事実

- UC 仕様の E2E 完了条件の Scenario「クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04)」の最後の Then は次の 1 文である。

```gherkin
And slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される
```

- 前半「同じ CSV クォート解析関数が使われ」は、コマンドの実行結果(終了コード・stdout・stderr)からは真偽を判定できない。同じ解析結果になることまでしか判定できない。
- 後半「タブ区切りのファイルは `error: header mismatch` で拒否される」は、実行結果で判定できる。
- UC BDD の step 実装は、前半を「二重化した引用符を含む引用セルを 1 セルとして受理する(`rows=2` / `status=valid`)」で代替し、代替した旨をコメントに残した。feature 本文は仕様からの転写規約により変更していない。
- 同じ Scenario の 1 つ前の Then「囲んだセルはカンマを含む 1 セルとして解析される」と、受け入れ基準 SPEC-004-04-5「slot ジョブマップと同じ CSV 形式である」は、実行結果で判定できている。
- Scenario 名と受け入れ基準の「対象カタログ」の語は、CR-dcd8234d-006 で対象カタログが廃止されると残らない。

### 現在の仕様と問題

- 受け入れ基準に「利用者が観測できる振る舞い」と「実装の構造(関数の共有)」が 1 文に混ざっている。
- 実装の構造は、テストでは判定できず、代替した判定が仕様の意図と一致しているかを step 実装者が毎回判断する。
- 関数の共有そのものは CR-dcd8234d-001 で契約として扱う。受け入れ基準には振る舞いだけを残すのが筋である。
- 元の方針資料との照合結果: 方針資料は「クロスチェックのジョブマップも slot ジョブマップと同じ CSV 形式」とだけ定める。関数の共有は方針資料の要求ではない。

### 変更してほしいこと

1. 当該 Then を、観測できる振る舞いだけに書き直す。例:

```gherkin
And 二重化した引用符を含む引用セルは 1 セルとして解析され、タブ区切りのファイルは `error: header mismatch` で拒否される
```

2. 「同じ CSV クォート解析関数を使う」という構造の要求は、受け入れ基準から外し、CR-dcd8234d-001 の契約(共有関数の集合)へ移す。
3. USDM の受け入れ基準(SPEC-004-04)に同じ文言があれば、同じ方針でそろえる。
4. Scenario 名・受け入れ基準・Given から「対象カタログ」の語を外す作業は CR-dcd8234d-006 で行う。本要求は Then の文言だけを対象にする。

### 完了条件

- 当該 Scenario のすべての Then が、`validate-config.sh` の終了コード・stdout・stderr だけで判定できる。
- UC BDD の step 実装から「代替した」コメントを消せる。

## CR-dcd8234d-003: 同じシェルに source されるティアの関数名・グローバル変数名の名前空間の規則が無い

- severity: spec-gap
- related_ids: [CLP-003, SPEC-004-04, REQ-004]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md]

### 観測した事実

- `validate-config.sh` の本体は、速報クロスチェックティアと確報クロスチェックティアの検証関数ファイルを、同じシェルに順に source する。
- 速報クロスチェックティアの実装(2 回目)が repository 層に `target_catalog_repo_load` を定義したところ、確報クロスチェックティアにも同名の関数があり、後から source された確報側の定義で上書きされた。両者は戻り値の意味が異なるため、`--crosscheck-job-map` の対象カタログ参照の解決が内部障害(終了コード 6)になった。
- bash は関数の再定義を黙って受け入れる。lint(shellcheck)でも、ティア単独で source する単体テストでも検出されない。本体を実プロセスとして起動するテストでだけ現れた。
- 速報クロスチェックティアは、自ティアの関数名・定数名にティア固有の接頭辞(`crosscheck_` / `CROSSCHECK_`)を付けて回避した。両ティアのトップレベル名に他の衝突が無いことは実装者と独立検証の双方が確認した。
- アーキテクチャ設計のティア間依存ルール(CLP-003「IF なし(直接依存)」)、CLI 契約、両ティアの仕様のいずれにも、同じプロセスに読み込まれるティア間の名前空間の規則は無い。
- CR-dcd8234d-006 の反映後は、確報クロスチェックティアの検証関数は無くなり、同じシェルに source されるのは facade ティアと速報クロスチェックティアの 2 つになる。衝突の実例は確報側の関数で起きたが、規則の不在は残る。

### 現在の仕様と問題

- 「bash の source で直接依存」する設計を採る以上、名前の衝突は設計上の制約として仕様に書く必要がある。実装規約だけで扱うと、ティアごとの実装者が独立に名前を決め、統合時にだけ壊れる。
- 今回の回避は速報側だけが接頭辞を付けた片務的なもので、facade ティアの共有関数(`job_map_*` / `csv_*` / `cli_field_*`)には規則が無い。次にティアを追加すると同じ衝突が起こり得る。
- 元の方針資料との照合結果: 方針資料はシェルスクリプトの内部構成を定めていない。規則の追加は方針資料と矛盾しない。

### 変更してほしいこと

1. ティア間依存ルール(CLP-003)に、同じプロセスに source されるティア間の名前空間の規則を追加する。
   - 各ティアが定義するトップレベルの関数名・グローバル変数名には、ティア固有の接頭辞を付ける(例: 速報クロスチェックは `crosscheck_` / `CROSSCHECK_`)。
   - facade ティアが提供する共有関数は、共有面として契約に列挙した名前(`job_map_*` / `csv_*` / `cli_field_*`)だけを他ティアから呼べる名前とし、それ以外は facade 固有の接頭辞で閉じる。
   - 他ティアが定義した名前を再定義してはならない。
2. `validate-config.sh` のエントリポイントの契約(`tier_note`)に、検証関数ファイルは関数の定義だけを行い、source 時に副作用(シェルオプションの変更・グローバル変数の上書き・コマンドの実行)を起こさないことを明記する。
3. 可能なら、統合テストの観点として「所有ティアごとの関数名の集合に重複が無いこと」を仕様に書く(実装側はそれをゲートにできる)。

### 完了条件

- 同じプロセスに読み込まれるティアの名前空間の規則が、ティア間依存ルールまたは契約から読める。
- 同じプロセスに読み込まれるティア(facade / 速報クロスチェック)の関数名が、その規則に照らして衝突しないことを人が確認できる。

## CR-dcd8234d-004: ティア仕様の BDD「compare_options にプレースホルダが無い」の Given と Then の値が一致しない

- severity: spec-gap
- related_ids: [SPEC-004-01, REQ-004]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md]

### 観測した事実

- 速報クロスチェックティアの仕様「ティア完了条件(BDD)」に次の Scenario がある。

```gherkin
Scenario: compare_options にプレースホルダが無い
  Given JOB001 行の compare_options が `--fast` である
  When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
  Then 終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る
```

- 検証ルール 7 の違反文言は `error: compare_options is missing {blue} or {green} line=N job_id=... value=...` で、`value=` には行の compare_options の値をそのまま出す(CLI 契約「行の値不正」の共通形式)。
- Given のとおり compare_options を `--fast` にすると、実装の出力は `value=--fast` になり、Then と一致しない。Then のとおり `value=--blue {blue}` を出すには、Given の値が `--blue {blue}`(`{green}` だけが欠けた値)でなければならない。
- ティアの feature ファイルは仕様からの転写で同文のため、実装を仕様に合わせても Given と Then を両立できない。
- 実装は検証ルール 7 どおり(`value=` に元の値)とし、step 定義の Given が Then と整合する `--blue {blue}` を書き込む代替をした。TDD では `--fast` の入力で `value=--fast` が出ることを別に確認している。

### 現在の仕様と問題

- 同じ Scenario の中で入力と期待出力が食い違い、どちらが意図かを仕様から決められない。
- 転写規約で feature を直せないため、step 定義が Given の文言と違う値を書き込んでいる。Scenario を読む人は、Given の値でテストしていると誤解する。
- 元の方針資料との照合結果: 方針資料にプレースホルダの違反例の記載は無い。どちらに直しても矛盾しない。

### 変更してほしいこと

1. Given か Then のどちらかに統一する。推奨は Given を `--blue {blue}`(`{green}` が無い)に直す案である。Then の `value=--blue {blue}` は「片方だけ欠けても違反になる」ことを示せて、検証ルール 7 の例として情報量が多い。
2. Then を残す場合は `value=--fast` に直す。

### 完了条件

- 当該 Scenario の Given の値から Then の期待出力が一意に導ける。
- ティアの step 定義で、Given の文言と違う値を書き込む代替が不要になる。

## CR-dcd8234d-005: 実装が補った速報側の違反文言 2 件が CLI 契約に無い

- severity: spec-gap
- related_ids: [SPEC-004-01, REQ-004]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md]

### 観測した事実

- CLI 契約は、行の値不正を `error: <column> is <reason> line=N ...` の共通形式で定め、`<reason>` の具体例を列挙する。ティア仕様の検証ルール一覧も、違反ごとの文言を列挙する。
- 次の 2 件は、列の定義(型・固定値)としては仕様にあるが、違反したときの文言がどちらにも無い。実装者が共通形式に合わせて文言を決めた。

| 列 | 列定義の記載 | 文言の有無 | 実装が決めた文言 |
|---|---|---|---|
| compare_command(速報) | 絶対パス | 実行不可(`is not executable`)だけがある。相対パスの文言は無い | `error: compare_command is not absolute line=N job_id=... value=...` |
| compare_targets(速報、comparison_type=full の行) | `catalog` 固定 | 非空(`is empty`)だけがある。固定値違反の文言は無い | `error: compare_targets is not catalog line=N job_id=... value=...` |

- 独立検証は 2 件とも仕様に無い判断(minor)として確認を残した。
- 初版の本要求にあった次の 2 項目は、レビュー対話(2026-10-10)の決定で対象そのものが無くなるため、CR-dcd8234d-006 に吸収した。
  - 確報側の `catalog_version` の許可文字違反の文言(`error: catalog_version is invalid line=N value=...`)。対象カタログの検証自体を廃止する。
  - 参照先カタログの列数不一致(`error: column count mismatch line=N expected=<n> actual=<n>`)の `expected` の基準。対象カタログ参照の解決(検証ルール 9)自体を廃止する。

### 現在の仕様と問題

- 列定義にある制約を違反したときの文言が契約に無いため、実装者が決めた文言が事実上の契約になっている。文言は利用者の修正作業に直結する外部 IF であり、契約に書かれていないと別の実装(再実装・他ティアの同種の列)で変わり得る。
- `compare_targets` が `catalog` 固定である定めは、CR-dcd8234d-006 で予約行 `final-crosscheck` の列定義を見直すときに変わり得る。固定値が変わる場合は、その値に合わせた文言を契約に書く必要がある。
- 元の方針資料との照合結果: 方針資料は違反文言を定めていない。文言の追加は方針資料と矛盾しない。

### 変更してほしいこと

1. CLI 契約の「行の値不正」の例と、ティア仕様の検証ルール一覧に、上表 2 件の文言を追加する。推奨は実装が決めた文言をそのまま採用する案である(共通形式に沿っており、実装とテストの変更が要らない)。別の文言にする場合は、その文言を契約に書く。
2. CR-dcd8234d-006 で予約行 `final-crosscheck` の `compare_targets` の固定値を変える場合は、`is not catalog` の文言をその値に合わせて書き直す。

### 完了条件

- 上表 2 件の違反が起きたときの文言が、CLI 契約またはティア仕様から一意に読める。

## CR-dcd8234d-006: 確報クロスチェックの対象カタログと業務日付を relay-gate が検証・配布する仕様が、方針資料「比較対象の定義は適用側で定義する」と乖離している

- severity: spec-gap
- related_ids: [SPEC-004-01, SPEC-004-04, SPEC-006-01, SPEC-006-02, SPEC-011-03, SPEC-013-01, REQ-004, REQ-006]
- related_files: [docs/specs/latest/_inference.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/usdm/latest/requirements.yaml, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を登録して終端状態まで待機する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を claim する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/保存済みの確報結果をジョブスケジューラへ返す/spec.md]

### 観測した事実

- 元の方針資料(`tmp/RelayGateのしくみ.md` 42 行目)は「比較対象の定義は、適用側で定義します」と定める。方針資料の確報依頼のデータ項目には「business_date」「対象カタログの版」があり、所有者の表には「比較対象と対象カタログ: クロスチェックの job map」がある。それ以上の記載(対象カタログの列、検証、比較ツールへの受け渡し)は方針資料に無い。
- 対象カタログ CSV の列(catalog_version / target_type / target_identifier / compare_condition / business_date_handling)、`validate-config.sh --target-catalog` の検証、比較定義のヘッダーコメント `# target_catalog_path=` / `# catalog_version=`、確報 worker が該当版の行を抜き出して `{catalog_path}` で渡す仕組みは、仕様策定フェーズの推論である。推論記録(`docs/specs/latest/_inference.md` #5)は設定ファイルの形式を「仮採用」とし、本 UC の確報ティア仕様(tier-final-crosscheck.md)の設定契約も「所在は `_inference.md` #5 仮採用」と注記している。速報ティア仕様の予約行 `final-crosscheck` の compare_options も、プレースホルダを「仮採用: 確報比較ツールへの引数の渡し方は方針資料に定めが無いため」と注記している。
- 本 UC の実装は、この推論どおりに対象カタログの検証(確報ティア、bats 57 件)と対象カタログ参照の解決(速報ティアの検証ルール 9)を実装し、独立検証を通した。
- レビュー対話(2026-10-10、`docs/impl/latest/dcd8234d/review/review-notes.md`)で、利用者は次を決定した(案 A)。
  - 確報クロスチェックは比較ツールを起動するだけにする。比較対象の一覧は比較ツール側(適用側)が持つ。
  - relay-gate はアプリ独自 DB の業務日付を参照できないため、business_date も relay-gate から外す。
  - 速報クロスチェックの `{blue}` / `{green}`(成果物の場所)の受け渡しは変えない。
  - 方針資料側の確報依頼のデータ項目(business_date / 対象カタログの版)は、利用者が方針資料を更新してそろえる。

### 現在の仕様と問題

- 方針資料は比較対象の定義を適用側に置くのに対し、仕様は relay-gate が対象カタログの列を定め、検証し、該当版の行を抜き出して比較ツールへ配る。relay-gate が持つ必要のない対象一覧と業務日付を、検証・配布まで含めて実装している。
- 仕様上、対象カタログと business_date は次の場所に分散している。
  - 本 UC: 確報ティア仕様(tier-final-crosscheck.md)全体。速報ティア仕様の設定契約(ヘッダーコメント `# target_catalog_path=` / `# catalog_version=`、予約行の compare_options の `{catalog_path}` `{catalog_version}` `{business_date}`)、検証ルール 7a(`{catalog_version}` `{business_date}` 必須)、検証ルール 9(対象カタログ参照の解決)、UC 仕様の BDD(SPEC-004-01 / SPEC-004-04 の対象カタログの Given / Then)。
  - CLI 契約: `validate-config.sh --target-catalog`、`final-crosscheck-runner.sh --business-date --catalog-version`、確報比較ツールの launch(`{catalog_path}` の置換と `input/target-catalog.csv` の抜き出し)、config_files の `target-catalog.csv`、crosscheck-job-map.csv のヘッダーコメント宣言。
  - RDB スキーマ: `final_crosscheck_requests.business_date` / `catalog_version` 列と、そのユニーク制約の検討記録。
  - USDM: SPEC-004-01(所有者の表の「比較対象と対象カタログ」)、SPEC-004-04(対象カタログも CSV)、SPEC-006-01(確報依頼の business_date と対象カタログの版)、SPEC-011-03(final_crosscheck_request の列と対象カタログの紐付け)、SPEC-013-01(対象カタログは適用側がジョブマップで定義)。
  - 確報クロスチェックフローの UC 4 件: 確報比較依頼を登録して終端状態まで待機する(runner の引数と版の存在検証)、確報比較依頼を claim する、比較ツールで日次全量比較を実行して結果を保存する(該当版の抜き出しと置換)、保存済みの確報結果をジョブスケジューラへ返す。
- 本 UC の名称「クロスチェックのジョブマップと比較定義を定義する」は速報・確報の両方を含むが、確報側に残るのは比較ツールの起動コマンドだけになる。

### 変更してほしいこと

1. 確報クロスチェック runner は business_date / catalog_version の引数を持たず、起動されるだけにする。依頼レコードには識別子・状態・担当 worker・時刻・実行結果だけを持つ。
2. 確報クロスチェック worker は、比較定義の予約行 `final-crosscheck` の compare_command / compare_options を、プレースホルダ置換なしでそのまま起動する。該当版の行を抜き出して渡す処理と `input/target-catalog.csv` は廃止する。
3. 対象カタログ CSV(`target-catalog.csv`)と `validate-config.sh --target-catalog` を廃止する。CLI 契約の config_files / options / stdout / readers から該当項目を外す。
4. 比較定義(crosscheck-job-map.csv)から次を削除する。ヘッダーコメント `# target_catalog_path=` / `# catalog_version=` とその宣言検証、検証ルール 7a の `{catalog_version}` `{business_date}` 必須、検証ルール 9(対象カタログ参照の解決)、`{catalog_path}` `{catalog_version}` `{business_date}` のプレースホルダ。stdout の `target_catalog_path:` / `catalog_version=` も外す。
5. RDB スキーマの `final_crosscheck_requests` から business_date / catalog_version 列を削除し、ユニーク制約の検討記録を整理する。
6. USDM の SPEC-004-01 / SPEC-004-04 / SPEC-006-01 から対象カタログの記述を削除する。SPEC-011-03 / SPEC-013-01 にも同じ記述があるため、同じ方針でそろえる。
7. 本 UC の確報側ティア仕様(tier-final-crosscheck.md)を削除し、UC「クロスチェックのジョブマップと比較定義を定義する」は速報の比較定義(予約行 `final-crosscheck` の起動コマンドを含む)だけを対象にする。UC 名の見直しは任意とする。
8. 確報クロスチェックフローの UC 4 件(確報比較依頼を登録して終端状態まで待機する / 確報比較依頼を claim する / 比較ツールで日次全量比較を実行して結果を保存する / 保存済みの確報結果をジョブスケジューラへ返す)の仕様を、上記 1〜5 に合わせて書き直す。
9. 推論記録(`_inference.md` #5)の対象カタログに関する仮採用を、利用者決定で解消した旨に更新する。方針資料の確報依頼データ項目(business_date / 対象カタログの版)は利用者が方針資料側で削除する。

### 完了条件

- 仕様・契約・スキーマ・USDM のどこにも、relay-gate が対象カタログと business_date を定義・検証・配布する記述が無い。
- 確報クロスチェック runner / worker の仕様が「起動されたら比較定義の予約行のコマンドをそのまま起動し、結果を返す」だけで読める。
- 本 UC の対象が速報の比較定義だけになり、確報側のティア仕様が無い。
- 方針資料と仕様で、確報依頼のデータ項目が一致する。
