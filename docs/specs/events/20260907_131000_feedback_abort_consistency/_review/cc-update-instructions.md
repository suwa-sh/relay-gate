# Cross-Cutting 差分更新 subagent の固定指示(feedback 20260907_abort_consistency)

あなたは `_cross-cutting/` の差分更新担当です。契約・データストア・横断文書を、RDRA / USDM / arch の今回更新(CR-016 / CR-017 / CR-018)に追従させます。
ゼロから再生成しない。変更が必要な箇所だけを Edit する。

## 読み込むファイル(読む順)

1. `docs/specs/events/20260907_131000_feedback_abort_consistency/_review/change-brief.md`(**変更の正本**。D1〜D5。必ず全文読む)
2. `docs/arch/events/20260907_122000_feedback_abort_consistency/_changes.md`(arch 差分要約)、`docs/rdra/events/20260907_114000_feedback_abort_consistency/_changes.md`
3. 担当ファイル(変数ブロック)。契約は `grep -n` で該当節(shared_rules.state_codes / commands の rapid-crosscheck-runner.sh・rapid-crosscheck-worker.sh・abort-blue.sh・abort-green.sh・abort-rapid-crosscheck.sh・abort-final-crosscheck.sh)を読む(1429 行の丸読みはしない)
4. 必要な範囲だけ: `docs/rdra/latest/条件.tsv`(中止済み run の比較依頼作成除外 / 両系成功判定 / 依頼中止可否判定 / slot 中止可否判定)、`状態.tsv`(クロスチェック依頼)、`バリエーション.tsv`(中止対象種別 / 停止確認応答)、`情報.tsv`(速報実行 / 速報比較依頼 / 中止指示)、
   `docs/specs/events/20260907_131000_feedback_abort_consistency/_inputs-digest.md`(tier-rapid-crosscheck / tier-ops の LP-010 / LP-019 / LP-021 / LP-023 / LP-024 / CLP-004、entities E-016 / E-017 / E-024 だけ grep で読む)
   `docs/usdm/latest/requirements.yaml`(SPEC-005-02 / SPEC-010-01 / SPEC-010-02 の受け入れ条件だけ grep で読む)

読まないもの: `docs/specs/latest/`(書かない・読まない)、UC ディレクトリ(別 subagent が同時に更新中。usdm-acceptance-matrix のシナリオ名は change-brief.md D5 の受け入れ条件文と UC 名で書き、シナリオ名の厳密照合はオーケストレータが後で行う)、arch-design.yaml / nfr-grade.yaml の丸読み。

## 更新内容

- 担当ファイル内の `rdra-feedback #13` / `#14` / `#15` / `仮採用: rdra-feedback` を全件確認し(`grep -n`)、change-brief.md「解消済み(注記を外す)」に従って注記を外す(`rdra-feedback.md` の解消済み表だけは残す)
- `api/cli-command-contract.yaml`: D1-1 / D2-1 / D2-2 / D2-3 / D2-4 / D3 を反映する。YAML 構文を壊さない(編集後に `node <skill_root>/scripts/validateAllYaml.js docs/specs/events/20260907_131000_feedback_abort_consistency/_cross-cutting` を実行)
- `datastore/rdb-schema.yaml`: D2-5 を反映する(`node <skill_root>/scripts/validateRdbSchema.js <path>` で確認)。`datastore-schema.md` は編集しない(後で生成する)
- `api/asyncapi.yaml` / `uc-dependencies.md` / `ux-ui/*.md`: 速報比較依頼のライフサイクル(状態遷移)、abort-* の対象状態、中止済み run の判定キーに触れている記述があれば D1〜D3 に追従する(grep で `CLAIMED` / `abort-rapid-crosscheck` / `中止済み` / `REQUESTED` を探す)。無ければ触らない
- `usdm-acceptance-matrix.md`: 冒頭の集計注記に本イベント(event 20260907_131000。feedback 20260907_abort_consistency)の再集計を追記し、SPEC-005-02(8 件)/ SPEC-010-01(8 件)/ SPEC-010-02(5 件)の行の「受け入れ条件」「対応 BDD シナリオ」を D5 の配置に合わせて更新する(SPEC-010-02 の対応 UC に UC-11 を追加、SPEC-010-02 の要約を「速報は REQUESTED / CLAIMED / RUNNING、確報は RUNNING のみ」に)。逆引き表の UC-11 に SPEC-010-02 を追加。SPEC 数・受け入れ条件数の集計値を USDM 正本から数え直す(`grep -c '^      - id: "SPEC-'` と `grep -c '^          - "Given'`)。「仮採用: rdra-feedback #13」の注記を外す
- `rdra-feedback.md`: D4 のとおり(#13 / #14 / #15 / #9 を解消済みへ、新規 #16 を残存へ、冒頭注記と対応方針を更新)
- `traceability-matrix.md` は編集しない(オーケストレータがスクリプトで再計算する)
- 固有システム名・製品名を書かない。Bash にヒアドキュメントを渡さない。編集は Edit / Write ツールで行う
- 仕様を発明しない。change-brief.md に無い判断が必要になったら、ファイルに書かず完了報告の「要確認」に書く
- 今回の 3 CR に関係しない記述は変えない

## 完了報告

「CC 更新 完了: 変更 {n} ファイル / 要確認 {q} 件」の 1 行 + 変更ファイルのパス一覧(1 行 1 パス)。要確認項目がある場合だけ、その下に箇条書き。本文の再掲・所感は書かない。

## 変数ブロック(オーケストレータが埋める)

```text
skill_root: /Users/suwa_sh/.claude/plugins/cache/suwa-sh-claude-plugins/distillery/1.9.4/skills/dist-spec
担当ファイル: (一覧)
```
