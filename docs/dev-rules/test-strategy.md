# テスト戦略 正本(4 段テスト階層)

distillery-impl が生成・運用するテストは 4 段。**上 3 段の gherkin は distillery 仕様からの転写**であり、
実装ハーネスが創作しない。第 4 段(TDD)だけが実装者の設計物である。

| 段 | 名称 | gherkin の出典(転写元) | 配置 | 実行ゲート |
|---|---|---|---|---|
| ① | ATDD(受け入れ) | `docs/usdm/latest/requirements.yaml` の `requirements[].specifications[].acceptance_criteria[]` | `features/atdd/{spec_id}.feature` | ゲート 6(S7) |
| ② | UC BDD | `docs/specs/latest/{業務}/{BUC}/{UC}/spec.md` の「E2E 完了条件(BDD)」gherkin ブロック | `features/uc/{uc_slug}.feature` | ゲート 5(S6) |
| ③ | tier BDD | 同 UC 配下 `{tier_id}.md`(例 `tier-frontend.md`)の「ティア完了条件(BDD)」gherkin ブロック | `{tier_dir}/features/{uc_slug}.feature` | ゲート 4(S4) |
| ④ | TDD(単体) | 出典なし(実装者が red→green→refactor で設計) | `{tier_dir}/test/` | ゲート 3(S4) |

`{uc_slug}` = uc-map(`docs/impl/latest/uc-map.yaml`)の `branch_slug`(UC 英語名の kebab-case)。
uc_id ハッシュはファイル名に使わない(外側から UC の意味が読み取れないため)。step definition
(`steps/{uc_slug}.steps.*`)も同じ slug で揃える。uc_id との対応は uc-map が正本。

## 転写ルール(①〜③)

- **意訳・要約・補完を禁止**する。gherkin ブロックをそのまま転写する
- 転写先 feature ファイルの先頭に出典コメントを残す:
  `# source: docs/specs/latest/貸出管理業務/貸出管理フロー/書籍を貸出する/spec.md#E2E完了条件(BDD)`
- ① の `acceptance_criteria` は 1 行 Given/When/Then 文字列。**1 criterion = 1 Scenario、
  Scenario 名は `{SPEC-ID}-{連番}`、一意タグ `@atdd_{SPEC-ID}-{連番}` を付与**して展開する
  (文言は原文のまま)。1 つの SPEC が複数 UC の基準を含むことがあるため、S7 での実行は
  uc-map の `atdd_scenarios` に基づく**タグ完全一致の選択実行**が前提(名前の部分一致は誤選択するため禁止)
- 仕様側の gherkin が空・欠落・不正(パース不能)なら転写せず、**S1 の input-preflight で変更要求として起票**する

## red baseline 規約(S2 test-scaffold の完了条件)

テスト先行を「feature ファイルの存在」でなく「**期待した理由で fail する実行可能テスト**」で担保する:

- ①〜③: feature + step definition skeleton(全 step が `pending`/`not implemented` を明示的に投げる)+ runner 設定
- ④: 実装対象(UC × tier)ごとに最初の failing 単体テストを 1 本以上
- S2 の done 条件 = 全 4 段のテストが「**未実装を理由に fail する**」こと(エラー種別を確認する。
  設定ミス・パースエラーによる fail は red baseline と認めない)
- **scoped 再実行(spec 変更起因で S2 が指定 tier のみ再実行される場合)は red baseline を
  done 条件にしない**: 既存実装が残っているため全段 fail は成立しない。再生成した feature /
  テストが parse 可能かつ実行可能であることを確認し、既実装分の green を許容する
  (done 条件の正本は dist-impl-implement の mode=test-scaffold「scoped 再実行」)

## テストメソッド命名規約(④ TDD)

```
テスト対象_XXXの場合_YYYであること
```

- 例: `貸出登録_在庫が0の場合_貸出不可エラーを返すこと`
- 言語のテストフレームワークに合わせて表現する(例: Python は `test_貸出登録_在庫が0の場合_貸出不可エラーを返すこと`、
  Java/Kotlin は バッククォート や `@DisplayName`、TypeScript(vitest/jest)は `describe('貸出登録', () => { it('在庫が0の場合、貸出不可エラーを返すこと', ...) })` の 2 分割も可)
- 「テスト対象」はメソッド・関数・振る舞いの名前。「XXXの場合」は前提条件。「YYYであること」は期待結果

## AAA 構造規約(④ TDD)

テストメソッド内は Arrange-Act-Assert を空行または最小限のコメントで 3 区画に分ける:

```
// Arrange: 前提の準備
// Act: テスト対象の実行(原則 1 呼び出し)
// Assert: 期待結果の検証
```

- Act は原則 1 呼び出し。複数の Act が必要になったらテストを分割する
- ①〜③ の gherkin は Given=Arrange / When=Act / Then=Assert に自然対応するため、step definition も同じ規律で書く

## 実体テストの環境前提(I/O 境界)

I/O 境界(RDB / メッセージング / 外部プロセス / ファイル)はモックでなく実体で検証する。環境前提は次のとおり固定する:

- **実 DB 等はテストが自前で起動・破棄する一時インスタンス**を使う(例: PostgreSQL は `initdb` + `pg_ctl`、
  または使い捨ての docker コンテナ)。開発機や CI の常設サービスに接続しない
- **環境不足は fail にする(暗黙 skip 禁止)**。意図的に外すときだけプロジェクトで定めた明示 skip の
  環境変数を使い、skip 理由をテスト出力に残す
- CI のテストジョブは必要バイナリを `PATH` に載せる(runner のプリインストール先が PATH 外のことがある)
- 独立検証(S5)をサンドボックス付きで動かすと loopback / shared memory が禁止され実体テストが開始できない。
  検証環境の制限は実装の blocker ではなく環境失敗として分離する(dist-impl-verify 手順 2)
- **テスト用 DDL は正本ではない**: migration は `datastore_owner` tier の migration 資産が正本。
  未整備の間に他 tier が置く DDL fixture は契約 source(rdb-schema)から生成し、先頭に暫定である旨を明記する
- E2E Scenario の Then に後続 UC の責務が含まれる場合、S2 の時点で「UC 横断 Scenario」として issues/ に
  一覧化し、ハーネス注入の要否を着手前に決める(注入箇所には issue 参照と「暫定注入・契約確定後に削除」を残す)

## DOM 一致テストの転写規約(dom_snapshot が true な frontend tier のみ)

`tiers[].capabilities.ui_review.dom_snapshot: true`(state-schema.md)の frontend tier では、
④ TDD の一部として「story と実装画面の DOM 構造一致」を検証するテストを追加で持つ。
生成の責務は Implementer(dist-impl-implement の S2/S4)であり、本節は転写規約(何をどう作るか)の正本。
**共通 helper(下記)だけは生成条件が異なる**: `dom_snapshot: true` **または**
`capture_review: enabled` のいずれかを満たせば生成する(capture_review が SSR 静的 HTML 生成に
この helper を要するため。D11)。DOM 一致テスト自体(stub adapter・結線 module・テストコード)の
生成は引き続き `dom_snapshot: true` のみで変更しない。

### 生成物の構造(不変 helper と差し替え可能な結線 module)

DOM 一致テストの生成物は役割の異なる 2 種に分離する。**同じ「adapter」という言葉を 2 つの
異なる対象に使わない**(以下では「結線 module」「(variant→props) adapter」で明確に呼び分ける):

| 生成物 | 生成条件 | 生成タイミング | S4 での変更可否 | 役割 |
|---|---|---|---|---|
| **共通 helper**(構造署名 extractor + variant→実装 props の adapter + HTML shell 生成) | `dom_snapshot: true` **または** `capture_review: enabled` | S2 が tier 内 1 箇所だけ生成 | **変更不可**(S2 生成のまま使う) | 構造署名の抽出規則・story args→実装 props の変換規則(fixture 契約)・SSR 静的 HTML 化の単一の正。S5 UI Reviewer が dom_snapshot 再実行と capture_review の SSR 静的 HTML 生成の両方でこれを再利用する(D9・D11) |
| **結線 module**(画面 adapter。variant ごと) | `dom_snapshot: true` | S2 が not-implemented stub として生成 | **S4 が変更可能**(結線先を書き換えるのはここだけ) | テストが render する窓口。S2 時点は「未実装」を理由に fail する stub、S4 で実装画面への参照に書き換える |

### S2(test-scaffold): not-implemented stub 経由の red baseline

- **実装画面を直接 import しない**(module resolution error は red baseline と認めない —
  既存の red baseline 規約と同一)。代わりに variant(画面状態)ごとに**結線 module**
  (明示的な not-implemented stub)を生成し、テストは結線 module 経由で render する
  (fail は「未実装」を理由とする assertion failure になる)
- 1 variant(画面状態)= 1 テスト。**対象は executable target のみ**(定義の正本は
  `dist-impl-run/SKILL.md` の S5 dispatch 手順「executable target 集合の算出」— story 実体の存在・
  variants 非空に加え、tier-rules.md の矛盾 3 条件による除外を含む。本節では再定義しない。
  S5 UI Reviewer の dispatch 条件と同一集合を使う)。矛盾 3 条件で除外された行・variant は
  正本の算出規則により既に集合から外れているため、**red baseline の分母にも含めない**
  (テストを生成しない)。除外は `issues/{ts}_{slug}.md` への起票対象であり(除外理由は生成した
  テストファイル側のコメントにも記録し、「未生成=見落とし」と区別できるようにする)、実行ベースの
  検証には持ち込まない(Verifier 手順 6 の major findings で扱う)
- 共通 helper(構造署名 extractor + variant→props adapter + HTML shell 生成)は結線 module とは別に、
  tier 内 1 箇所だけ生成する。**生成条件は `dom_snapshot: true` または `capture_review: enabled`**
  (capture_review のみ enabled で dom_snapshot テスト自体は生成しない場合でも、この helper は生成する)

### S4(tier-impl): 結線 module を実装画面へ結線して green 化

- S2 が生成した**結線 module のみ**を実装画面への参照に書き換え、DOM 一致テストを green にする
- **共通 helper(構造署名 extractor + variant→props adapter)は変更しない**(S2 生成のまま使う。
  結線 module の書き換えと混同しない)

### 共通 helper の単一化

- **構造署名の extractor**(DOM から比較対象の署名を取り出す関数)、
  **variant → 実装 props の adapter**(story args を実装 props へ変換する関数)、
  **HTML shell 生成**(render 出力 + 収集済み style を head に埋め込んだ静的 HTML を組み立てる関数。
  capture_review の SSR 静的 HTML 生成が使う。D11)は、
  **tier 内に 1 箇所だけ生成**する(結線 module とは別の生成物。生成条件は `dom_snapshot: true`
  または `capture_review: enabled`)
- **S2/S4 のテスト(dom_snapshot)と S5 UI Reviewer(dist-impl-ui-review)の dom_snapshot 再実行・
  capture_review の SSR 静的 HTML 生成は、この同一 helper を使う**
  (実装ごとに署名生成・HTML 生成ロジックが異なる事態を構造的に防ぐ。UI Reviewer は自前で
  署名生成・HTML 生成をしない)
- **HTML shell の描画再現範囲(必須項目)**: 再現対象はコンポーネントが自己完結で持つスタイル
  (inline style / CSS-in-JS の SSR 出力)に**限定**する。import される外部 CSS・外部 asset・
  Storybook decorators への依存は再現対象外とする。**片側でも再現できない target は比較せず**、
  capture_review の `captures[].result: skipped`(`reason: render_context_unavailable`)として
  記録する(偽差分を作らないため。dist-impl-ui-review/SKILL.md の判定規則と一致させる)
- story args を実装 props へ変換する adapter は **story(variant)ごとに定義**する(fixture 契約)

### 構造署名の正規化規則(必須項目)

- **比較する**: 文書順の要素タグ列 / role(明示属性に加え、`output`=status・`button`=button 等の
  **要素の暗黙 role を同一視**する — story が明示 role、実装がセマンティック要素の暗黙 role でも
  等価と判定する。縮小実走で確認済みの偽陽性対策)/ aria-* 属性 / 状態依存要素の有無
  (variant ごとに story と実装で同じ要素が現れるか)
- **比較しない**: テキスト内容 / style・class / 動的 id / データ値 / 属性の並び順
- 実装言語・フレームワークごとの extractor の実装詳細は helper 実装に委ねる(本節は必須の
  比較対象/非対象のみを固定する)

これらのテストは gate 3(TDD)に乗るため CI でも常時回る(`references/gates.md` は変更不要)。
