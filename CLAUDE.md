# CLAUDE.md

## このリポジトリの正体

**relay-gate** — 既存実装(blue)と新実装(green)をジョブスケジューラの同一ジョブ定義から並行稼働させ、クロスチェックで整合性を検証しながら段階的に切り替えるための、feature flag 付きストラングラーファサード型の実行基盤。シェルスクリプト + RDB(ジョブキュー兼管理DB)で構成し、エアーギャップ環境のオンプレミス Linux で動作する。MIT の OSS。

**現在のステータス**: 仕様策定フェーズ完了(distillery パイプライン Step1〜6b 実施済み)。実装フェーズは distillery-impl でブートストラップ済み(実装本体は未着手)。

## 開発規約の必須 5 項(正本: docs/dev-rules/)

Verifier が reject する違反。詳細は `docs/dev-rules/`(coding-rules.md / test-strategy.md / tier-rules.md)を必ず読むこと。

1. **契約型の直接編集禁止**: `packages/contracts/` 配下(contracts[] からの生成物)を手で書き換えない。再生成は S0/S3 のみ
2. **UI コンポーネントは `packages/ui/` のみ使用**: 新規自作は禁止。不足は design への変更要求を経由する
3. **formatter / linter を通過する**: コマンドは `docs/impl/latest/impl-config.yaml` の `commands` が正。S4 並走中は check-only
4. **仕様を実装側で曲げない**: 矛盾したら実装を仕様に合わせるか issues/ に起票する
5. **Conventional Commits**: コミットはオーケストレータのみが `impl({uc_id}): ...` 形式で行う

## 実装フェーズの構成(distillery-impl)

| 項目 | 場所 |
|---|---|
| 実装状態(イベントソーシング) | `docs/impl/`(events/ + latest/。正本は events + done ファイル) |
| 実装構成 | `docs/impl/latest/impl-config.yaml`(tier / 契約 / コマンドの正) |
| UC 対応表 | `docs/impl/latest/uc-map.yaml`(23UC、uc_id 8桁) |
| 実装 tier | `facade/`(tier-facade, cli, bash) / `worker/`(tier-worker, worker, bash) |
| 契約生成物 | `packages/contracts/relay-gate-db/`(rdb-schema → bash 定数。S4 中 read-only) |
| UI 資産 | `packages/ui/`(design の storybook-app 由来。read-only) |
| DB migration | `worker/migrations/`(datastore_owner: tier-worker) |
| テスト 4 段 | `features/atdd/`(①) / `features/uc/`(②) / `{tier}/features/`(③) / `{tier}/test/`(④) |

## 開発プロセス(必ずこの順で)

このリポジトリは **distillery(要件・仕様パイプライン)を正本とした仕様駆動開発**で運用する。コードを直接変更する前に、必ず仕様側から入る。

### 1. 要件・仕様の整理は distillery で行う

- 機能の追加・変更は、まず **distillery で要件を整理**する: `dist-requirements`(変更要望テキスト → USDM 分解 → RDRA 差分更新)
- 続けて **`dist-spec` で仕様化**する(UC 単位 spec + cross-cutting)。初期構築では間に `dist-quality-attributes`(NFR)と `dist-architecture` が必須(実施済み)
- 成果物の置き場(イベントソーシング。`events/` は不変、`latest/` が最新スナップショット):

| パス | 内容 |
|---|---|
| `docs/README.md` | 全成果物のナビゲーション(`generateReadme.js` で自動生成。手動編集しない) |
| `docs/usdm/latest/` | USDM 要求仕様(REQ 12 / SPEC 38) |
| `docs/rdra/latest/` | RDRA モデル(アクター/情報/状態/条件/バリエーション/BUC 23UC) |
| `docs/nfr/latest/` | IPA 非機能要求グレード(model2・97 メトリクス) |
| `docs/arch/latest/` | アーキテクチャ設計(BC 4 件、4 ティア × 5 層、依存ルール、ADR) |
| `docs/infra/latest/` | インフラ設計(オンプレ限定 MCL 成果物) |
| `docs/design/latest/` | デザインシステム(CLI 出力規約 + Storybook) |
| `docs/specs/latest/` | **実装の正本**。UC 別 spec.md / tier-*.md、cross-cutting |
| `docs/todo.md` | 低確信度の仮採用値の記録(2026-08-17 承認済み・closed。実運用値の判明時に feedback request で見直す) |

- 仕様に無いものを実装で発明しない。実装中に仕様の不足・矛盾を見つけたら、コードでごまかさず distillery の差分更新に戻す
- distillery のスキルを個別実行したら、最後に `generateReadme.js` で `docs/README.md` を再生成する
- 成果物には特定案件の固有システム名称・業務名・製品名を記載しない(中立表現: 現行実装 / 新実装 / ジョブスケジューラ / 比較ツール 等)

### 2. 実装は distillery specs に従う

- `docs/specs/latest/` の該当 UC の spec.md / tier-*.md を読んでから着手する
- レイヤー構成と依存ルールは `docs/arch/latest/arch-design.yaml` に従う: presentation → usecase → domain → repository / gateway
- cross-cutting の正本:
  - CLI コマンド契約 = `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml`(24 コマンド。HTTP API は無い。`openapi.yaml` はバリデータ互換スタブ)
  - DB スキーマ = `docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml`(3NF + Event/Snapshot 併用)
  - CLI 出力・終了コード規約 = `docs/specs/latest/_cross-cutting/ux-ui/` + `docs/design/latest/design-event.yaml`

### 3. ATDD: specs の受け入れ条件を先にテスト化する

- 各 UC spec.md の **BDD シナリオ(Given/When/Then)を受け入れテストとして先に書く**
- 受け入れテストが RED であることを確認してから実装に入る
- シナリオの具体値は spec の記述をそのまま使う

### 4. TDD: ユニットレベルも specs を起点に RED → GREEN → REFACTOR

- ドメインルールは spec のトレーサビリティ表にある条件・状態遷移を 1 ケースずつテスト化してから実装する
- I/O 境界は実体(一時ディレクトリ・実ファイル・実 DB コンテナ等)でテストする(モックで誤魔化さない)
- バグ修正は必ず再現テストを先に書く

### 5. qlty check 指摘ゼロをキープ

- 実装開始時に `qlty init` で formatter / linter / SAST を導入し、security 指摘ゼロまで潰してからこの節を「指摘ゼロをキープ」に確定する(現時点は未導入)
- 導入後は変更のたびにローカルで実行する:

```bash
qlty check --all --no-progress --no-formatters --fail-level medium   # CI と同じゲート。exit 0 を維持
qlty fmt --all                                                        # formatter
```

- **medium 以上(security 系等)の指摘を残したまま commit しない**
- プラグイン設定は `.qlty/configs/`、ルール除外は `.qlty/qlty.toml` の `[[exclude]]`(plugins + rules + file_patterns の 3 点必須)

### 6. 作業単位ごとのレビュー(サブエージェント → Codex の二段)

**(a) サブエージェントレビュー**: 実装が一区切りしたら、生成した本人とは別のサブエージェントに、仕様(`docs/specs/latest/`)と突き合わせたレビューをさせる。観点: 仕様トレーサビリティ / クラッシュ耐性・冪等性 / テストの実効性。

**(b) Codex レビュー**: 作業単位(コミットのまとまり)ごとに `toolbox:review-refute-loop` skill で外部レビューを実施する(「レポートだけ、修正不要」と明示)。

**(c) 反証**: 指摘ごとに実体(コード・テスト実行・仕様)と照合して反証を試みる。誤検出・意図した設計判断・スコープ外は根拠つきで不採用にする。

**(d) 取り込み**: **反証しきれない指摘は必ず修正する**(回帰テスト追加 → 再テスト → qlty ゲート確認)。反証内訳(指摘数 / 不採用数と根拠 / 対応数)をコミットメッセージまたは PR に残す。

## 実装規約

- 実装言語はシェルスクリプト(bash)中心。DB アクセス・比較処理等の補助実装の言語は実装フェーズ開始時に確定し、本節へ追記する
- **コメントは日本語**で書く(仕様の制約・設計判断を示す最小限のもの。コード・識別子・エラーメッセージ・ログは英語)
- 関数ヘッダコメントも日本語(`# func_name は〜する。` のように対象名から始める)

## テスト規約

- テストフレームワークは実装フェーズ開始時に確定する(bash なら bats 系を第一候補)。確定したら本節に追記する
- **AAA パターン**: 各テスト本文を `Arrange` / `Act` / `Assert` のコメントで 3 区画に分ける(準備・実行・検証を混ぜない)
  - 準備が不要なテストは `Arrange` を省く。空の区画にコメントだけ置かない
  - 異常終了だけを検証するテストは実行と検証が同一文になるので `Act & Assert` に統合する
- **テスト名**: `{テスト対象}_{XXXの場合}_{YYYであること}` 形式(テスト対象 = 実際に呼ぶ関数・スクリプト名を英語のまま、条件と期待は日本語)
- CLI を実プロセス起動するテストは `<cli名>_<subcommand>` を対象名にする
- テスト規約は conformance test / lint で機械検査し CI から実行する(規約を CLAUDE.md に書いただけで完了としない)

## README とドキュメントの構成

- **README は入口ハブに徹する**。置くのはヘッダー要素(プロジェクト名 H1 + バッジ + 言語リンク + 任意のステータス注記)と、**概要 / 特徴 / アーキテクチャ / Getting Started / ドキュメント一覧**の本文 5 ブロックだけ。利用者マニュアルは `docs/guide/`、開発者マニュアルは `docs/development/` に分割し、README の「ドキュメント」表から入口ファイルへ 1 行要約つきでリンクする。分割先の内容を README に再掲しない。README のドキュメント表にはヘルプ・問い合わせ先(Issues 等)とコントリビュートの行を必ず含める
- **Getting Started は「最短で 1 回動く手順」に限定**し、コピペで通ること(未公開タグ・未配布物を実行コマンドに書かない)
- **想定ワークフロー(何を用意→どの順で実行→出力をどう読む)**は `docs/guide/` の入口に必ず 1 本置く(実装提供開始時に作成)
- 入口ファイルは 2 状態をとる。初期は入口 1 枚に本文を直接書いてよい。150 行を超えたら標準ファイル名(`use-cases.md` / `configuration.md` / `cli-reference.md` / `troubleshooting.md`、development 側は `setup.md` / `architecture.md` / `testing.md` / `release.md` / `contributing.md`)へ分割する。該当内容が無いファイルは作らない
- 各分割ファイルの冒頭に「前提(これだけ知っていれば読める)」を置く
- 図は **mermaid** で書き、追加・変更したら `npx md-mermaid-lint <ファイル>` で検証する

## 変更完了チェックリスト

1. `git rev-parse --show-toplevel` / branch / status で対象リポと既存差分を再確認する
2. 主要機能・CLI・利用手順を追加 / 削除した場合、README(本文 5 ブロック)、`docs/guide/`、`docs/development/`、設計 doc、目次、サンプル、CLI help の古い列挙数・ステップ数・リンクを `rg` で横断確認する
3. specs / schema / 設定等の正本を先に更新し、複製は生成またはドリフトテストで追従させる
4. test / lint / doc link / mermaid / build の該当ゲートを実行する
5. version や配布タグを次版へ進めた状態は **release pending** と報告し、実体確認後に解消する。README の実行コマンドには未公開タグを書かない

## 検証コマンド

```bash
# 実装フェーズ開始時に test / lint / build のコマンド一式を確定して本節へ追記する
# 現時点で実行できる検証:
cd docs/design/latest/storybook-app && npm install && npx storybook build   # Storybook build
find docs/guide docs/development README.md README.ja.md -name '*.md' -print0 2>/dev/null | xargs -0 npx md-mermaid-lint   # mermaid 構文
```

## 横断的な注意点

- **並行実行の一貫性**: ジョブキューは RDB の lease / claim による排他制御を正本とする(`docs/arch/latest/arch-design.yaml` CTP-006)。重複比較依頼を作らない冪等性を常に維持する
- **Runner Result Contract**: `stdout.log` / `stderr.log` / `exitcode.txt` + `execution-spec.json` の 3 ファイル契約が外部 IF の正本。一時ファイル → リネームで書き込み途中の読み取りを防ぐ
- **エアーギャップ前提**: 実行時にインターネット接続・外部 SaaS を要求する実装を入れない
- **CI / リリース**: 未整備。実装フェーズで `.github/workflows/` を整備したら本節を実態に合わせて更新する(GitHub Actions は SHA ピン + workflow トップ `permissions: {}` + `persist-credentials: false`)
- 自動生成物(`docs/README.md`)は手動編集しない
