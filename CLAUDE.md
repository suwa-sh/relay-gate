# CLAUDE.md

## このリポジトリの正体

**relay-gate** — 既存実装(blue)と新実装(green)をジョブスケジューラの同一ジョブ定義から並行稼働させ、クロスチェックで整合性を検証しながら段階的に切り替えるための、feature flag 付きストラングラーファサード型の実行基盤。シェルスクリプト + RDB(ジョブキュー兼管理DB)で構成し、エアーギャップ環境のオンプレミス Linux で動作する。MIT の OSS。

**現在のステータス**: 仕様策定フェーズ(distillery パイプライン)。実装フェーズの成果物は 2026-08-30 に一度破棄した(復旧用タグ `archive/impl-6078c4ed-20260830`)。仕様を元の方針資料(`tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md`。git 管理外)に戻す還流を行ってから、distillery-impl の bootstrap(S0)から再開する。

## 方針の正本

- **元の方針資料**: `tmp/RelayGateのしくみ.md`(しくみ)と `tmp/RelayGateの利用イメージ.md`(適用例)。要求・仕様の変更要求を出すときは、必ずこの 2 ファイルと照合する(過去に spec 側へ寄せる変更が続き、元の意図から乖離した経緯がある)
- 仕様の変更は、実装や spec の都合ではなく「元の方針資料と一致しているか」を第一の判断基準にする。不一致なら方針資料側の記述へ戻す方向で変更要求を書く

## 開発プロセス(必ずこの順で)

このリポジトリは **distillery(要件・仕様パイプライン)を正本とした仕様駆動開発**で運用する。コードを直接変更する前に、必ず仕様側から入る。

### 1. 要件・仕様の整理は distillery で行う

- 機能の追加・変更は、まず **distillery で要件を整理**する: `dist-requirements`(変更要望テキスト → USDM 分解 → RDRA 差分更新)
- 続けて **`dist-spec` で仕様化**する(UC 単位 spec + cross-cutting)。`dist-quality-attributes`(NFR)と `dist-architecture` は実施済み
- 成果物の置き場(イベントソーシング。`events/` は不変、`latest/` が最新スナップショット):

| パス | 内容 |
|---|---|
| `docs/README.md` | 全成果物のナビゲーション(`generateReadme.js` で自動生成。手動編集しない) |
| `docs/usdm/latest/` | USDM 要求仕様 |
| `docs/rdra/latest/` | RDRA モデル(アクター/情報/状態/条件/バリエーション/BUC) |
| `docs/nfr/latest/` | IPA 非機能要求グレード |
| `docs/arch/latest/` | アーキテクチャ設計(BC、ティア × 層、依存ルール、ADR) |
| `docs/infra/latest/` | インフラ設計(オンプレ限定 MCL 成果物) |
| `docs/specs/latest/` | **実装の正本**。UC 別 spec.md / tier-*.md、cross-cutting |
| `docs/pipeline/` | dist-pipeline の実行記録と feedback run |
| `docs/dev-rules/` | 実装フェーズ向けの開発規約(coding-rules / test-strategy / tier-rules) |
| `docs/todo.md` | 低確信度の仮採用値の記録 |

- **UI 画面は存在しない**(CLI の出力規約のみ)。デザインシステム / Storybook は生成しない(2026-08-30 に破棄。distillery 側で design ステージを skip できるようにする改修は別リポで行う)
- 仕様に無いものを実装で発明しない。実装中に仕様の不足・矛盾を見つけたら、コードでごまかさず distillery の差分更新に戻す
- distillery のスキルを個別実行したら、最後に `generateReadme.js` で `docs/README.md` を再生成する
- 成果物には特定案件の固有システム名称・業務名・製品名を記載しない(中立表現: 現行実装 / 新実装 / ジョブスケジューラ / 比較ツール 等)

### 2. 実装は distillery specs に従う

- `docs/specs/latest/` の該当 UC の spec.md / tier-*.md を読んでから着手する
- レイヤー構成と依存ルールは `docs/arch/latest/arch-design.yaml` に従う: presentation → usecase → domain → repository / gateway
- cross-cutting の正本:
  - CLI コマンド契約 = `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml`(HTTP API は無い)
  - DB スキーマ = `docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml`
  - CLI 出力・終了コード規約 = `docs/specs/latest/_cross-cutting/ux-ui/`

### 3. 実装フェーズ(再開時)

- distillery-impl の `dist-impl-run` で bootstrap(S0)から始める。tier 構成・契約・コマンドは bootstrap で再確定する
- ATDD(spec の BDD シナリオを先にテスト化)→ TDD(RED → GREEN → REFACTOR)。I/O 境界は実体(一時ディレクトリ・実ファイル・実 DB)でテストする
- 作業単位ごとに `toolbox:review-refute-loop` で外部レビューし、反証しきれない指摘は必ず修正する
- 詳細規約は `docs/dev-rules/` を正本とする

## 実装規約(再開時に適用)

- 実装言語はシェルスクリプト(bash)中心。BDD の step 定義のみ JavaScript(CommonJS)
- **コメントは日本語**(仕様の制約・設計判断を示す最小限のもの。コード・識別子・エラーメッセージ・ログは英語)
- **エアーギャップ前提**: 実行時にインターネット接続・外部 SaaS を要求する実装を入れない
- **Runner Result Contract**: `stdout.log` / `stderr.log` / `exitcode.txt` + `execution-spec.json` の契約が外部 IF の正本。一時ファイル → リネームで書き込み途中の読み取りを防ぐ

## README とドキュメントの構成

- **README は入口ハブに徹する**。置くのはヘッダー要素(プロジェクト名 H1 + バッジ + 言語リンク + 任意のステータス注記)と、**概要 / 特徴 / アーキテクチャ / Getting Started / ドキュメント一覧**の本文 5 ブロックだけ。利用者マニュアルは `docs/guide/`、開発者マニュアルは `docs/development/` に分割し、README の「ドキュメント」表から入口ファイルへ 1 行要約つきでリンクする
- **Getting Started は「最短で 1 回動く手順」に限定**し、コピペで通ること(未公開タグ・未配布物を実行コマンドに書かない)
- 図は **mermaid** で書き、追加・変更したら `npx md-mermaid-lint <ファイル>` で検証する

## 変更完了チェックリスト

1. `git rev-parse --show-toplevel` / branch / status で対象リポと既存差分を再確認する
2. 主要機能・CLI・利用手順を追加 / 削除した場合、README(本文 5 ブロック)、`docs/guide/`、`docs/development/`、目次、サンプルの古い列挙数・ステップ数・リンクを `rg` で横断確認する
3. specs / schema / 設定等の正本を先に更新し、複製は生成またはドリフトテストで追従させる
4. lint / doc link / mermaid の該当ゲートを実行する
5. 自動生成物(`docs/README.md`)は手動編集しない
