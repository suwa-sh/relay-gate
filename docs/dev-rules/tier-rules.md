# tier 種別規約 正本(distillery-impl)

実装 tier は `impl-config.yaml` の `tiers[]` 宣言が正。ここでは tier 種別ごとの実装規約を定める。
どの tier がどの種別か(frontend / backend / worker / data-pipeline / cli / mcp-server)は
tier id の意味と tier md の構成から bootstrap が判定して impl-config に記録する。

**全種別共通**: tier 間の依存面は `impl-config.yaml` の `contracts[]` 宣言が正
(実装リポで読める対応物は contracts[] の source と `docs/impl/latest/contracts.lock.yaml` の
generated[]。種別定義の正本は distillery-impl プラグイン側の contract-registry.md)。
自 tier が provider / consumers に含まれる契約の生成物・source だけを読み、
契約に無い tier 間依存が必要になったら実装で直接依存せず issues → feedback で契約宣言の
追加を要求する。

## Spec の参照解決

UCの業務ルールは spec.md、データ操作は _model-summary.yaml、型・制約は登録済み契約、
固有の原子性・再送・副作用は tier md を読む。旧形式のデータモデル変更表・ビジネスルールも受け付ける。
共有定義は明示されたファイル + 見出し / ID だけを読み、契約sourceの読込範囲はcontracts.lockに従う。
共通UIの型・既定値は共通定義、UC固有のvariant・供給値はtierのマッピング表で確認する。
図や表の再掲がないことを仕様不足としない。

## frontend 系(例: tier-frontend)

- **入力**: `tier-frontend.md`(画面仕様・コンポーネントマッピング・操作フロー)+
  `docs/design/latest/design-event.yaml` の `screens[]`(uc / story / variants)
- **UI コンポーネントは `packages/ui/` のみ使用**。`packages/ui/` は
  `docs/design/latest/storybook-app/src/`(components / tokens / stories と依存モジュール)を
  bootstrap が実ファイル列挙で取り込んだもの(design-event.yaml はコンポーネント名と
  screen 結線の照合にのみ使う。`.imported.yaml` が取り込みの記録)
- 不足コンポーネント・不足variantは自作せず、designへの変更要求（issues/ → 単一feedback draft）を経由する
- 画面と UC の結線は design-event.yaml の `screens[].uc` が正。結線が無い UC は S1 が警告済みのはず
  (素の packages/ui 部品で組む選択がユーザー合意済みの場合のみ進む)
- openapi 契約の consumer である場合、API 呼び出しは `packages/contracts/api-client`(生成物)経由。
  fetch/axios の直書き禁止

### story = 画面構造の正(転写起点)

画面実装は **story の画面構成(使用コンポーネント・画面状態の出し分け)を構造の正として転写する**
(参照例ではなく転写起点)。乖離が必要になったら実装で曲げず issues → feedback の既存経路で
変更要求する。**明示する限界**: 本規約が担保するのは構造的整合(コンポーネント在庫・画面結線・
画面状態)までであり、レイアウト・スタイル・レスポンシブ挙動などのピクセル忠実度は未保証。

### 用語の正本分離

UI に関する「正本」は 3 つに分離する。混同しない。

| 対象 | 正本 | 例 |
|---|---|---|
| 画面のコンポーネント在庫 | design-event.yaml `screens[].components` | `["BookCard", "Button"]` |
| 画面状態(Story の named export) | design-event.yaml `screens[].variants` | `["Default", "Error", "Loading"]` |
| コンポーネントの prop variant / size | tier-frontend.md のコンポーネントマッピング表 | `BookCard (detailed)`, `Button (default/outline)` |

宣言と実体が食い違う場合の実装優先順位: **story 実体(取り込まれた実ファイル)>
design-event 宣言 > tier md 記載**(実装を止めないための優先。差分は issues へ)。

### 入力ソース間矛盾の扱い(実装欠陥と区別・停止理由にしない)

design-event / story 実体 / tier md が互いに食い違うケースは**実装の欠陥ではない**。
上記の優先順位規則で常に実装続行可能なため、S4 の停止(blocker)理由にしない。

矛盾として扱うのは次の 3 つのみ(optional 項目の単純な不在は矛盾ではない):

1. screens[] に宣言された story path の実体が packages/ui 取り込みに存在しない
2. screens[].variants と story 実体の named export が一致しない
3. screens[].components に宣言されたコンポーネントが、story 実体(import closure 展開後)に存在しない

**story path の解決規則**(条件 1 の判定に使う): `screens[].story` は storybook-app 相対
(`src/` 始まり)、`.imported.yaml` の path は `storybook-app/src/` 基準(packages/ui 相対)。
先頭の `src/` を厳密に 1 回除去して packages/ui 相対へ変換してから実体を照合する
(例: `src/stories/Foo.stories.tsx` → `packages/ui/stories/Foo.stories.tsx`)。

frontend の実装開始前に上記 3 条件を確認し、矛盾があれば
`issues/{ts}_{slug}.md` に起票した上で、**story 実体を優先して実装を続行**する(停止しない)。

### uc 結線の 0 / 1 / N 件の扱い

design-event.yaml の Screen スキーマは `uc` / `story` / `variants` が任意で uc の一意性制約もない。
screen 解決は uc-map の `ui_screens` / `ui_screen_resolution`(S1 が確定・永続化済み。
両者は XOR — ui_screens が非空なら resolution は置かれない)を起点にする:

- **`ui_screens` に 1 件以上**: 各行について突合する(複数画面 UC は全行が対象。
  resolution が残存していても ui_screens 非空を優先する)
- **`ui_screen_resolution: plain_ui_confirmed`**(ui_screens が空): UI 突合をスキップ
  (素の packages/ui で進める合意済み)
- **`ui_screen_resolution: feedback_requested`**(ui_screens が空): design への変更要求が起票済み。
  素の packages/ui で実装を続行する(UI 突合はスキップ)
- 行に `story` / `variants` が無い(optional 不在): その項目の転写はスキップする
  (スキーマ上正常な入力であり矛盾ではない)

`_api-summary.yaml` の `schema_version: distillery.api-summary/v2` は索引である。
対象UCの `_contract-slice.json` を追加で読み、summaryの `contract_sha256` と実ファイルのSHA-256を照合する。
型・認可・エラー・イベントpayload/headerはslice内のOpenAPI/AsyncAPIから取得する。
欠落やhash不一致をlegacy形式として補完しない。提供操作だけでなく `consumes` の依存操作も対象にする。

### read-set 定義(Implementer / Verifier 対称)

frontend の追加読込は次で構成する:

- uc-map の `ui_screens` の各エントリ(`{name, route}`)に name + route 一致する
  design-event.yaml の該当 `screens[]` 行(全行。screen name は一意制約が無いため route で同定を補う)
- 各行の結線 story ファイル
- 結線 story から到達する **packages/ui 内**の推移的 import closure
  (closure は packages/ui 内に限定。packages/ui 外への展開はしない)

### 検証所有表(UI 一致確認の担当分担)

frontend の UI 一致確認は対象・手段が異なる複数レーンで分担する(有効化は
`tiers[].capabilities.ui_review` の宣言に応じる)。混同しない:

| 検証 | 手段 | 担当 | 有効化条件 |
|---|---|---|---|
| 構造(読解) | 上記「UI 構造整合」の照合表(story vs コード読解) | Verifier(dist-impl-verify)手順 6 | 常時(has_design_system) |
| dom_snapshot | story と実装画面を両方 render して構造署名を比較(決定論・CI 常設) | ④ TDD の DOM 一致テスト + S5 UI Reviewer(dist-impl-ui-review)の再実行 | `capabilities.ui_review.dom_snapshot: true` |
| capture_review | browser でキャプチャした story と実装画面をアドホックに目視比較(環境依存・CI では回らない) | S5 UI Reviewer(dist-impl-ui-review) | `capabilities.ui_review.capture_review: enabled`(実施可否はセッション実行時に判定) |

読解ベースの照合表は dom_snapshot / capture_review の有効化にかかわらず常に実施する(重複ではなく、
構造整合の担保方法が異なる)。`dom_snapshot: false` かつ `capture_review: disabled` のプロジェクトでは、
UI Reviewer は起動せず読解ベースの照合表のみで進む。

## backend 系(例: tier-backend-api)

- **入力**: `tier-backend-api.md`(API 仕様表・データアクセス/実行条件・業務ルール参照)+ `spec.md` +
  `_api-summary.yaml` / `_model-summary.yaml`
- openapi 契約の provider である場合、API の入出力型・ルーティングは
  `packages/contracts/server-stubs` / `api-types`(生成物)起点。ハンドラ実装だけを書く
- データモデルは `_cross-cutting/datastore/rdb-schema.yaml`(+ kvs-schema.yaml)が正。
  migration は `datastore_owner` tier(impl-config 宣言)が所有する。
  ただし contracts[] で provider が宣言されたテーブル群(例: data pipeline の mart)は
  その provider が DDL/migration を所有し、backend は consumer として生成型経由で読む
- ドメインロジックは ddd-tactical-implementation の基準で刻む(集約 1 Tx 1 個・ID 参照・値オブジェクト化)

## worker 系(例: tier-worker)

- **入力**: `tier-worker.md`(イベント処理仕様)+ 自 tier が関与する契約の生成型
  (asyncapi 契約が宣言されていれば `packages/contracts/async-types`)
- asyncapi が無い環境(capability `has_asyncapi: false`)では `_api-summary.yaml` の `async_events[]` から
  型を起こす(縮退モード。生成するのは bootstrap P4 であり、Implementer は生成物を使うだけ)
- 冪等性: イベント再配送を前提に、処理は冪等に書く(tier-*.md の冪等性欄が正)

## data-pipeline 系(例: tier-data-pipeline)

- **入力**: `tier-data-pipeline.md`(変換・集計仕様)+ 自 tier が関与する契約
  (consumer として上流データレイアウト、provider として出力 mart レイアウト —
  `packages/contracts/` の生成型 + source schema)
- **出力レイアウト(mart 等)は契約が正**。実装の都合で列・型・粒度を変えない(変更要求経由)。
  consumer(backend 等)はこのレイアウトを read model として読む
- mart の DDL / migration は provider として自 tier の dir 配下に所有する
- 再実行安全: ジョブは冪等(同一入力での再実行が同一結果)に書き、部分失敗からの再開を前提にする

## cli 系(例: tier-cli)

- **入力**: `tier-cli.md`(コマンド仕様)+ 自 tier が関与する契約の生成型
- コマンド体系・引数・入出力形式が契約面。仕様の記載から転写する(実装の都合で変えない)
- exit code は成功 0 / 失敗非 0。データ出力は stdout、ログ・診断は stderr に分離する
- 対話プロンプトは非対話フラグで抑止できるようにする(CI・パイプラインからの利用を前提)

## mcp-server 系(例: tier-mcp-server)

- **入力**: `tier-mcp-server.md`(tool 仕様)+ 自 tier が関与する契約の生成型
- tool 名・入出力 JSON Schema・エラー形式が契約面。スキーマからの逸脱は変更要求経由
- tool の description・スキーマは仕様の記載から転写する(実装の都合で意訳しない)

## datastore 資産(実装 tier ではない)

- architecture tier に `tier-datastore` 等があっても、それは**実装 tier ではなく共有資産**
- migration / schema 定義ファイルは `datastore_owner` に宣言された tier のディレクトリ配下に置く
  (contracts[] で provider が宣言された資産は provider tier の配下)
