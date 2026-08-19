# 推論根拠 (20260819_113049_design_system)

## 入力

| 入力 | 内容 |
|---|---|
| `docs/rdra/latest/状態.tsv` | background slot実行状態に STARTING / UNKNOWN の遷移が追加され6値になった |
| `docs/rdra/latest/情報.tsv` | クロスチェック定義管理コンテキストに「比較定義」エンティティが追加された |
| `docs/rdra/latest/BUC.tsv` | 比較定義は速報・確報クロスチェックの実行 UC が参照する情報。画面列は空 |
| `docs/rdra/latest/条件.tsv` | relay-gateエラーの退避終了コード: 未確定・取得不能・中止済み=125 / バリデーションエラー=124。foreground の exitcode.txt は0を含む全値を透過 |
| `docs/arch/latest/arch-design.yaml` | 同上の退避終了コード規約と、relay-gateエラー時の stderr 併記(foreground stderr.log + relay-gate エラー内容) |

## 判断

### CR-6078c4ed-008 → changed

- 前回イベント `20260818_143057_design_system` では、arch が6値でも RDRA 状態.tsv が4値だったため、RDRA 整合性ルールに従い states セクション(RDRA 状態モデル由来)を4値に据え置き、DIST-023 / DIST-024 として保留した。
- 今回 RDRA 状態.tsv が6値になったため、据え置きの根拠が消滅した。states セクションを6値へ整合させる。
- 追加2値のラベルは、既にコンポーネント層で確定済みの `StatusBadge`(starting=起動受付 / unknown=結果不明)に一致させ、新規トークンを作らない。
- 色は states スキーマの enum(amber/green/blue/gray/red/violet/orange)に制約されるため、UNKNOWN は `status-badge-unknown`(orange) と一致する `orange`、STARTING は enum に cyan が無いことから同一モデル内で識別可能な `violet` を採る。実際の描画色の正本は `status-badge-starting`(cyan系)トークンで、states の color はモデル内の粗い色区分を指す。

### CR-6078c4ed-009 → not_impacted

- 比較定義は JOB_ID ごとの比較対象・比較実装・有効期間を保持する設定マスタ。
- BUC.tsv で比較定義を参照するのは「速報クロスチェックを実行する」「全テーブル・全ファイルを対象に確報クロスチェックを実行する」の2 UC のみで、いずれも画面定義を持たない。
- RDRA に存在しない管理画面を design で発明することは整合性ルールで禁止されている。よってポータル・画面・コンポーネント・トークンいずれにも変更は生じない。

### CR-6078c4ed-010 → changed

- 表示契約に2点の欠落があった。
  1. foreground 応答の exitcode を「0を含む全値そのまま透過」する規約が design に記載されていなかった。既存記述は「stdout/stderr/exitcodeのみに限定表示」までで、値の丸めの有無に触れていない。
  2. relay-gate 自身のエラーを退避終了コード(125 / 124)で区別すること、およびそのとき stderr 欄へ foreground stderr.log と relay-gate エラー内容を併記することが未記載だった。
- いずれも RunnerResultPanel の表示契約であるため、description と nfr_decisions へ反映する。
- props は増やさない。既存の `exitCode`(number) は退避終了コードを含む任意値を保持でき、`stderr`(文字列) は併記内容を保持できる。storybook-app の実装(`RunnerResultPanel.tsx` は exitCode をそのまま描画し stderr を TerminalPanel へ流す)は既にこの契約を満たすため、コード変更・再ビルドは不要。
- 退避終了コードの具体値は RDRA 条件.tsv と arch を正本とし、design 側は表示上の扱いだけを規定する(値の二重定義を避けるため、トークン化はしない)。
