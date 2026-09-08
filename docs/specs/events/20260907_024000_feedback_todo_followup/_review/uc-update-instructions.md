# UC 単位 Spec 差分更新 subagent の固定指示(feedback 20260907_todo_followup)

あなたは UC Spec の差分更新担当です。既存 UC Spec(前イベント 20260905_100000_feedback_todo_resolution のコピー)を、
RDRA / USDM / arch の今回更新(CR-013 / CR-014 / CR-015 の 3 件)に追従させます。ゼロから再生成しない。変更が必要な箇所だけを Edit する。

## 読み込むファイル(読む順)

1. `docs/specs/events/20260907_024000_feedback_todo_followup/_review/change-brief.md`(**変更の正本**。D1〜D3。必ず全文読む)
2. `docs/rdra/events/20260907_011000_feedback_todo_followup/_changes.md`(RDRA 差分要約)
3. 担当 UC ディレクトリ配下の `spec.md` / `tier-*.md` / `_api-summary.yaml` / `_model-summary.yaml`(変数ブロックの一覧)
4. 担当 BUC の `buc-spec.md`
5. 必要な範囲だけ: `docs/rdra/latest/BUC.tsv` / `情報.tsv` / `状態.tsv` / `条件.tsv` / `バリエーション.tsv`(担当 UC の行だけ grep で読む)、
   `docs/usdm/latest/requirements.yaml`(SPEC-005-02 / SPEC-005-06 / SPEC-010-01 の受け入れ条件だけ grep で読む)、
   `docs/specs/events/20260907_024000_feedback_todo_followup/_inputs-digest.md`(arch tier / entity の該当箇所だけ grep で読む。丸読みしない)
6. 契約の照合が必要なときだけ `docs/specs/events/20260907_024000_feedback_todo_followup/_cross-cutting/api/cli-command-contract.yaml` の該当コマンド節を grep で読む
   (契約側は別 subagent が同時に更新中。文言は change-brief.md D1 / D2 / D3 を正とする)

読まないもの: `docs/specs/latest/`(書かない・読まない)、arch-design.yaml / nfr-grade.yaml の丸読み、担当外の UC、`docs/design/`、`docs/pipeline/`。

## 更新内容(担当 UC に該当するものだけ)

- **機械置換は適用済み**(change-brief.md「適用済みの機械置換」)。置換で文脈がおかしくなった箇所(「aborted.txt と同値」、started-at.txt / aborted.txt の中身を「ローカル」と書いてしまった箇所、「UTC ISO 8601」の単独表記)を D3 に従って直す
- 担当 UC のファイル内に残る `UTC` を全件確認する(`grep -n UTC`)。残してよいのは D3-8(started-at.txt / aborted.txt の中身)、D3-9(`RELAY_GATE_NOW=...Z`、「TZ=UTC 前提」)だけ
- spec.md「関連 RDRA モデル」/ 分岐条件一覧 / 状態遷移一覧 / 関連 USDM 表を RDRA・USDM の今回差分に合わせる(D1-4 / D2-5)。新設条件・情報・遷移の行を追加し、「仮採用」「RDRA 未定義」の注記を change-brief.md「解消済み」に従って外す
- BDD シナリオ(spec.md の E2E / tier-*.md のティア完了条件)の Given / When / Then を新しい契約に合わせる。
  USDM の今回追加受け入れ条件(change-brief.md「USDM の今回追加分」)に対応するシナリオが担当 UC に無い場合は追加する(シナリオ名末尾に `(SPEC-xxx-yy)`)。日時の例示は D3-9
- tier-*.md のコマンド契約 / 処理フロー / データモデル記述を D1〜D3 に合わせて更新する(D2 の判定表・条件付き UPDATE・実行ログ行、D3 の日時規則)
- `_model-summary.yaml` の models / tables / columns を更新する(D1-3 の設定モデル追加、rdra_info、日時の値表現)。YAML 構文を壊さない(`node <skill_root>/scripts/validateModelSummary.js <UC dir>` で確認)
- `buc-spec.md`: 状態遷移全体図(mermaid)と状態遷移 UC マッピング、共有条件一覧を今回差分に合わせる(D2-5)
- 固有システム名・製品名を書かない(現行実装 / 新実装 / ジョブスケジューラ / 比較ツール)。コメントや説明は日本語、識別子・エラー文言は英語
- Bash にヒアドキュメントを渡さない。編集は Edit / Write ツールで行う
- 仕様を発明しない。change-brief.md / RDRA / USDM に無い判断が必要になったら、ファイルに書かず完了報告の「要確認」に書く
- 今回の 3 CR に関係しない記述は変えない

## 完了報告

「UC 更新 完了({group}): 変更 {n} ファイル / 要確認 {q} 件」の 1 行 + 変更ファイルのパス一覧(1 行 1 パス、`docs/specs/events/...` から)。
要確認項目がある場合だけ、その下に箇条書き(1 件 1〜2 行。何を・どちらに決めるべきか)。本文の再掲・所感は書かない。

## 変数ブロック(オーケストレータが埋める)

```text
skill_root: /Users/suwa_sh/.claude/plugins/cache/suwa-sh-claude-plugins/distillery/1.9.4/skills/dist-spec
group: {G1..G5}
対象 UC ディレクトリ: (一覧)
対象 buc-spec.md: (一覧)
重点: (このグループで D1 / D2 / D3 のどれが意味的変更を伴うか)
```
