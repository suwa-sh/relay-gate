# UC 単位 Spec 差分更新 subagent の固定指示(feedback 20260905_todo_resolution)

あなたは UC Spec の差分更新担当です。既存 UC Spec(前イベント 20260830_202851_spec_generation のコピー)を、
RDRA / USDM / arch の今回更新に追従させます。ゼロから再生成しない。変更が必要な箇所だけを Edit する。

## 読み込むファイル(読む順)

1. `docs/specs/events/20260905_100000_feedback_todo_resolution/_review/change-brief.md`(**変更の正本**。D1〜D12 / U1〜U4。必ず全文読む)
2. `docs/rdra/events/20260905_083000_feedback_todo_resolution/_changes.md`(RDRA 差分要約)
3. 担当 UC ディレクトリ配下の `spec.md` / `tier-*.md` / `_api-summary.yaml` / `_model-summary.yaml`(変数ブロックの一覧)
4. 担当 BUC の `buc-spec.md`
5. 必要な範囲だけ: `docs/rdra/latest/BUC.tsv` / `情報.tsv` / `状態.tsv` / `条件.tsv` / `バリエーション.tsv` / `外部システム.tsv`(担当 UC の行だけ grep で読む)、
   `docs/usdm/latest/requirements.yaml`(担当 UC に関係する SPEC の受け入れ条件だけ grep で読む)、
   `docs/specs/events/20260905_100000_feedback_todo_resolution/_inputs-digest.md`(arch tier / entity の該当箇所だけ)
6. 契約の照合が必要なときだけ `docs/specs/events/20260905_100000_feedback_todo_resolution/_cross-cutting/api/cli-command-contract.yaml` の該当コマンド節を grep で読む
   (契約側は別 subagent が同時に更新中。文言は change-brief.md U4 を正とする)

読まないもの: `docs/specs/latest/`(書かない・読まない)、arch-design.yaml / nfr-grade.yaml の丸読み、担当外の UC、`docs/design/`。

## 更新内容(担当 UC に該当するものだけ)

- **機械置換は適用済み**(change-brief.md「適用済みの機械置換」)。置換で文脈がおかしくなった箇所(例: 「TSV」と書いたまま `.csv`、「on のとき」)を直す
- spec.md「関連 RDRA モデル」/ バリエーション一覧 / 分岐条件一覧 / 状態遷移一覧 / 関連 USDM 表を RDRA・USDM の今回差分に合わせる
  (新設条件・属性・遷移・バリエーション値の行を追加、削除された属性の行を削除、注記「(spec 追加)」「仮採用」「rdra-feedback #n」「DIST-0xx」「confidence: low」を change-brief.md の「解消済み」一覧に従って外す)
- BDD シナリオ(spec.md の E2E / tier-*.md のティア完了条件)の Given / When / Then を新しい契約(9 キー、CSV 列名、run_id 形式、aborted.txt、文言 U4)に合わせる。
  USDM の今回追加受け入れ条件(change-brief.md「USDM の今回追加分」)に対応するシナリオが無い場合は追加する(シナリオ名末尾に `(SPEC-xxx-yy)`)
- tier-*.md のコマンド契約 / 処理フロー / データモデル記述を同様に更新。外部システムの列挙から「管理 DB(RDB)」を外し内部データストア表記へ(D6)
- `_model-summary.yaml` の tables / columns / operations、`_api-summary.yaml` の async_events を更新(列名・成果物名・値の変更)。YAML 構文を壊さない
- `buc-spec.md`: 状態遷移全体図(mermaid)と状態遷移 UC マッピング、共有条件一覧、共有バリエーション一覧、情報 CRUD を今回差分に合わせる(遷移追加 D8 / D9、条件追加 D4 / D5 / D11、aborted.txt)
- 固有システム名・製品名を書かない(現行実装 / 新実装 / ジョブスケジューラ / 比較ツール)。コメントや説明は日本語、識別子・エラー文言は英語
- Bash にヒアドキュメントを渡さない。編集は Edit / Write ツールで行う
- 仕様を発明しない。change-brief.md / RDRA / USDM に無い判断が必要になったら、ファイルに書かず完了報告の「要確認」に書く

## 完了報告

「UC 更新 完了({group}): 変更 {n} ファイル / 要確認 {q} 件」の 1 行 + 変更ファイルのパス一覧(1 行 1 パス、`docs/specs/events/...` から)。
要確認項目がある場合だけ、その下に箇条書き(1 件 1〜2 行。何を・どちらに決めるべきか)。本文の再掲・所感は書かない。

## 変数ブロック(オーケストレータが埋める)

```text
group: {G1..G5}
対象 UC ディレクトリ: (一覧)
対象 buc-spec.md: (一覧)
```
