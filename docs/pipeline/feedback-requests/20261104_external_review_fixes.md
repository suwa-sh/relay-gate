---
schema_version: distillery.feedback-request/v1
feedback_id: 20261104_external_review_fixes
created_at: 2026-11-04T09:00:00+09:00
source: distillery-impl
uc_id: c5e19a72
---

# 外部レビューの指摘の反映(ハング検知・ハウスキープ・設定の文字の検査)

2026-11-03〜04 の仕様変更(メール送信の削除、ハウスキープ新設、env 形式の設定規則)を別系統の AI で第三者レビューした。指摘 7 件を利用者が承認した(2026-11-04)。

## CR-c5e19a72-001: ハング検知の通知済み判定の穴を埋める

- severity: spec-gap
- related_ids: [REQ-008, SPEC-008-07]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md]

### 観測した事実

- CLI 契約の hang-detector.sh の renotification は、RAPID_CROSSCHECK_MODE が off 以外で管理 DB に接続できない回、成果物から判定した全対象の通知済み状態を MONITORING とみなして alert 行を出し、監視記録を保存せずに終了コード 6 で終える(次回同じ異常を再び知らせる)と定めている。ハング検知 UC の tier-ops.md も同じ。
- 方針資料(RelayGateのしくみ)は「通知済みの異常は、次回以降の監視で再び通知しません」と定める。DB 障害が続くと、通知済みの異常が見回りのたびに届く。
- RAPID_CROSSCHECK_MODE=off の通知済みの印(hang-detector-notified/<run_id>.<role>)は、内容が規定の値(HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED)以外のとき、または読めないときの扱いが定められていない。
- 横断規約(conventions.output_format.stderr と ui-design.md)は error 行を原則 1 回とし、hang-detector の例外を alert 行についてだけ書いている。一方、ハング検知 UC は対象ごとの保存失敗(monitor record save failed / notified mark save failed)を 1 対象 1 行の error で出し、次の対象へ続ける。

### 現在の仕様と問題

- DB 障害が続くあいだ、通知済みの異常が見回りのたびに届き、方針資料に反する。
- 印が壊れたときと保存失敗が複数あるときの出力が、実装によって変わる。

### 変更してほしいこと

1. off 以外で管理 DB に接続できない回は、alert 行を出さない。`error: management db connection failed ...` だけを出して終了コード 6 で終える。異常は通知済みにならないので、DB に接続できた最初の回に通常の規則で一度だけ知らせる。速報比較依頼は判定しない(今のまま)。契約、ハング検知 UC(spec.md / tier-ops.md / BDD / _api-summary.yaml)を揃える。
2. off の通知済みの印が、内容が規定の値以外・読めないときは、対象ごとに error 行(文言は仕様で確定。例 `error: notified mark invalid run_id=... role=... path: ...`)を出し、その対象の通知済み状態を印が無いもの(MONITORING)として判定する(知らせ漏れより重複を選ぶ今の方針と揃える)。alert 行を出した対象は印を規定の手順で書き直す。終了コードは 6。他の対象の判定は続ける。
3. 横断規約に、hang-detector の対象ごとの保存失敗の error 行(と 2 の印の不正の error 行)を、1 対象 1 行で複数出してよい例外として書き足す。

### 完了条件

- 管理 DB に接続できない回の stderr と終了コードが 1 つに決まり、通知済みの異常を再び知らせない。
- 印の内容が不正・読めないときの stderr、判定、終了コード、印の扱いが 1 つに決まる。
- 横断規約とハング検知 UC の error 行の数の規則が食い違わない。

## CR-c5e19a72-002: 構築手順のハング検知設定の検査を CLI 契約に合わせる

- severity: spec-gap
- related_ids: [REQ-008]
- related_files: [docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml]

### 観測した事実

- インフラの Ansible ロール relay-gate-config は、hang-detector.env に `HANG_DB_CONN_REF=` の行があることを必須とし、それ以外の非コメント行を拒否する(`grep -q '^HANG_DB_CONN_REF=' ... && ! grep -Ev '^(#|$|HANG_DB_CONN_REF=)' ...`)。
- CLI 契約では HANG_DB_CONN_REF は RAPID_CROSSCHECK_MODE が off 以外でだけ必須で、RAPID_HANG_DETECT_LIMIT_MINUTES と HANG_SCAN_WINDOW_HOURS は任意キー。字下げしたコメント行もコメントとして扱う。
- このため、off の設置や監視閾値を調整した正当な設定で構築が失敗する。

### 現在の仕様と問題

- 仕様どおりの正当な設定で、構築が失敗する。

### 変更してほしいこと

- 配置時の検査はファイルがあることの確認だけにする(ハウスキープ設定の配置と同じ考え方)。中身の検査(キーの許可・必須判定・行の形)は validate-config.sh(CLI 契約)に任せる。タスク名・コメント・関連する infra 記述(README、product-impl 等)も揃える。

### 完了条件

- CLI 契約が許すすべての hang-detector.env で、構築の検査が失敗しない。

## CR-c5e19a72-003: ハウスキープの判定手順と置き場の処理順を一意にする

- severity: spec-gap
- related_ids: [REQ-014, SPEC-014-05]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- CLI 契約の shared_rules.housekeep_rules.member_source は「判定の順は、(1) execution-spec.json の形式の検査 …」と書き、管理 DB に parallel_runs 行がある実行(DB の行で判定)にもこの手順が適用されるように読める。要求 SPEC-014-05 は、成果物を削除したあと DB 行の削除に失敗した場合、次回にその行を削除することを求める。成果物が無い実行に (1) を適用すると execution-spec missing で残り続ける。
- 削除待ちの置き場(housekeep-pending/)の残りのエントリを削除する順序が定められておらず、複数件の削除に失敗したときの `error: pending entry delete failed` 行の順が実装の列挙順に依存する。

### 現在の仕様と問題

- DB 行の削除だけが失敗した実行が、消えずに残り続けるように読める。
- 置き場の削除に複数件失敗したときの出力の順が、実装によって変わる。

### 変更してほしいこと

1. member_source の判定の順 (1)〜(3) は、成果物だけで判定する実行に適用すると明記する。parallel_runs 行がある実行は管理 DB の行で判定し、execution-spec.json の有無を問わない。判定 UC の記述も揃える。
2. 置き場の直下のエントリは名前の昇順(バイト順)で処理し、失敗の error 行もその順に出すと、契約と削除 UC に定める。

### 完了条件

- 成果物が無く DB 行だけが残った終了済みの実行が、次回の実行で削除される(SPEC-014-05 と一致する)。
- 置き場の残りの削除に複数件失敗したときの stderr の行順が 1 つに決まる。

## CR-c5e19a72-004: 文字と改行の違反が複数あるときの報告を一意にする

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- CLI 契約の config_input_rules の表は、NUL バイト・UTF-8 として不正なバイト列・BOM・CR の文言を定めるが、同じファイルに種類の違う違反が重なったときに、どれを何行どの順で出すかを定めていない。env 形式の第 1 段は「違反があれば上表の規則の error 行だけを出して止める」とし、validate-config.sh の violations は出した error 行の数としている。
- 同じ入力でも、一方だけを報告する実装と両方を報告する実装があり得て、stderr と violations が変わる。

### 現在の仕様と問題

- 同じ入力に対する stderr と violations が、実装によって変わる。

### 変更してほしいこと

- 第 1 段(バイト・改行の検査)の違反は、ファイル内の全件を行番号の昇順で出す。同じ行に複数の種類があれば表の順(NUL → UTF-8 → BOM → CR)で出す。CR の hint は今のとおり最後の CR の error 行の次に 1 回だけ。CSV と env の両方に適用する(config_input_rules の全ファイル共通)。BDD や例があれば揃える。

### 完了条件

- 種類の違う文字・改行の違反が同じファイルにあるとき、stderr の行と順、violations の数が 1 つに決まる。
