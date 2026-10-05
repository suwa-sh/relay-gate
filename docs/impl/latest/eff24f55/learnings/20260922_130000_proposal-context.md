# CLAUDE.md / dev-rules への追記提案(eff24f55 仕様還流後のサイクル由来)

既存の CLAUDE.md と dev-rules は変更していない。採否は人が判断する。
前回の提案(`20260919_213000_proposal-context.md`)のうち、提案 2(bash の版)は仕様側で確定した(CLI 契約 `runtime_prerequisites.bash_minimum_version: "5.0"`)。本ファイルはそれを踏まえて書き直す。

## 提案 1: bash 5.0 の前提を dev-rules に転記する

- 追記先の候補: `docs/dev-rules/coding-rules.md`
- 追記案:
  - 全スクリプトは bash 5.0 以上を前提にしてよい(正本: CLI 契約 `conventions.runtime_prerequisites`)。連想配列・`mapfile`・`${var@Q}` を使ってよい。
  - 重複検査と distinct 集計は連想配列で行数に比例させる。配列の線形探索(行数の 2 乗)を使わない。
- 根拠: 版の集計を連想配列に改めて、5,000 行の最悪条件で 36 秒 → 4 秒になった(`learnings/20260922_130000_bash5-associative-array-linear-aggregation.md`)。

## 提案 2: 性能の完了条件を NFR の最悪条件で書く

- 追記先の候補: `docs/dev-rules/test-strategy.md`
- 追記案:
  - 設定ファイルを読む機能は、NFR B.1.1.2 の共通前提(1 ファイル 5,000 行、全列に値、キー列全行一意、版の列全行相違)で実測し、B.2.1.1 の 10 秒以内を完了条件にする。
  - 典型の内容(版の列が全行同一)だけで測らない。
- 根拠: 典型の内容では 3,000 行 2.5 秒だったが、最悪条件では 13.8 秒だった(NFR の reason に記録)。

## 提案 3: bats で stdout と stderr を分けて判定する規約

- 追記先の候補: `docs/dev-rules/test-strategy.md`
- 追記案:
  - stdout と stderr を別々に判定する bats テストは、`bats_require_minimum_version 1.5.0` を宣言して `run --separate-stderr` を使う。`run cmd 2>file` は bats の内側の `2>&1` に上書きされる。
- 根拠: `learnings/20260922_130000_bats-separate-stderr-and-bsd-mktemp.md`

## 提案 4: 開発機(macOS)と実行環境(Linux)の差の扱い

- 追記先の候補: `CLAUDE.md` の「実装規約(再開時に適用)」、または `docs/dev-rules/coding-rules.md`
- 追記案:
  - 実行環境はオンプレ Linux(GNU coreutils)。開発機(macOS / BSD)向けの分岐は、実行環境では通らない経路であることをコメントと前提の記録に書く。
  - 開発機向けの分岐で一時ファイルの名前を変えるときは、元の名前も削除対象に残す。
- 根拠: BSD 系 mktemp のフォールバックで、mv 失敗時に元の作業ファイルが残る指摘(attempt 6 の minor F-004)。

## 提案 5: 「仮採用」注記の扱い

- 追記先の候補: `CLAUDE.md` の「開発プロセス」
- 追記案:
  - spec.md / tier-*.md に「仮採用」の注記がある論点は、実装前に distillery で確定するか、実装後の変更要求で確定する。実装者が確定しない。
- 根拠: credential_ref の形式不一致の扱いが「仮採用」のまま残り、独立検証が 2 attempt 続けて major で確認を求めた(CR-eff24f55-007)。
