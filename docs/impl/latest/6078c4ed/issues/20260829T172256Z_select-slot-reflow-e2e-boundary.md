# select-slot 還流後仕様(spec 20260829_210828_spec_generation)の UC 横断 Scenario と検証境界

S2 test-scaffold(scoped 再実行・tier-facade。feedback 20260822_085257 の CR-6078c4ed-011〜018 反映後)で
spec.md / tier-facade.md の gherkin を転写した際に判定した、E2E Scenario の Then ごとの担当 UC と、
仕様と検証境界が両立しない点。いずれも blocker ではない(足場は生成済み)。
S4 / S6 / S7 の着手前に判断が必要なものを列挙する。前回の issue(20260821T220045Z)の §2 / §7 / §8 は
今回の還流で仕様側に取り込まれ、ハーネス注入を削除した(§4 参照)。

## 1. UC 横断 Scenario 一覧(E2E 17 Scenario の Then ごとの担当 UC 判定)

| Scenario | 他 UC の責務を含む Then | 判定 | ハーネス注入 |
|---|---|---|---|
| BLUE_MODE=foreground, GREEN_MODE=background で両 slot を起動する | なし(全 Then が本 UC の起動受付・永続化・監査・標準出力) | 本 UC 単独 | 不要 |
| RAPID_CROSSCHECK_MODE=off の場合は速報管理 DB へ接続しない | なし | 本 UC 単独 | 不要 |
| BLUE_MODE=off, GREEN_MODE=foreground で新実装単独本番として起動する | なし | 本 UC 単独 | 不要 |
| BLUE_MODE=background, GREEN_MODE=background の場合は大きい方を採用する | なし | 本 UC 単独 | 不要 |
| background role を先に起動し foreground の完了を待たずに応答する | Given「blue 実装の foreground 実行が完了まで 60 秒かかる」は SSH 先の remote runner(UC c3c7ab31 / handshake 契約 issues/20260817T230000Z)の振る舞い。Then は「送出順」「green が STARTING で存在」「10 秒以内に exit 0」で、いずれも本 UC の観測範囲 | 本 UC 単独(remote runner は模擬) | **不要**(ssh スタブが起動イベントを受領して即応答し、60 秒の実行を detached プロセスで模擬する。RUNNING 遷移の注入は不要になった) |
| job map の固定引数の後ろに追加引数を順序を変えず連結する | なし | 本 UC 単独 | 不要 |
| 空白・引用符・改行を含む引数が往復で同一になる | なし | 本 UC 単独 | 不要 |
| credential_ref から認証情報を解決し実値を露出させない | なし | 本 UC 単独 | 不要 |
| runner 設定の差し替えのみで新世代実装を起動できる | なし | 本 UC 単独 | 不要 |
| 異常系 8 Scenario(同時 foreground / JOB_ID 未解決 / 必須フィールド欠落 / slot_type 不一致 / 起動前監査の追記失敗 / 送出失敗 FAILED / 送出 timeout UNKNOWN / 認証情報未解決) | なし(FAILED / UNKNOWN の補償記録と slot_launch_failed / slot_launch_timeout の追記は CR-6078c4ed-012 で本 UC の責務になった) | 本 UC 単独 | 不要 |

結論: 還流後の 17 Scenario に UC 横断の Then は無い。S6 は本 UC 単独で全 Scenario を結合できる。
S8 で仕様側へ「Then の責務分離」を要求する項目も無い。

## 2. 検証境界の注意(S4 / S6 / S7 が従う前提)

### 2.1 仕様の絶対パス(/etc/relaygate/...)と一時ディレクトリ

- 仕様の Given / Then は `/etc/relaygate/job-map.blue.json` 等の絶対パスを使い、標準エラーの期待文言にも
  `path=/etc/relaygate/job-map.green.json` が含まれる
- ハーネスは一時ディレクトリ配下に同じ相対構造(`{testDir}/etc/relaygate/{job-map.blue.json, job-map.green.json, credentials/}`)
  を作り、標準エラーの照合時に `{testDir}` 接頭辞を取り除いてから仕様の文言と突き合わせる
  (steps: `normalizedStderr` / bats: `strip_test_dir`)。実装は path に実パスを出力すればよい

### 2.2 起動イベント送出の失敗 / timeout の再現

- PATH 先頭の ssh スタブが接続先ホスト(`<user@host>`)で振る舞いを切り替える:
  `RELAYGATE_TEST_SSH_FAIL_HOST` = exit 255、`RELAYGATE_TEST_SSH_HANG_HOST` = 応答しない(sleep)
- timeout の Scenario は facade の deadline(起動受付 10 秒以内)まで待つ。cucumber は `setDefaultTimeout(60s)`、
  bats は実装 seam `RELAYGATE_SSH_TIMEOUT_SECONDS=2`(facade/src/launch_gateway.sh、上限 9 秒)で短縮している。
  S4 で seam 名を変える場合は bats を追随させる
- 送出失敗と timeout の混在時の終了コードは 1(cli-command-contract.yaml exit_codes 124 の注記)。足場の Scenario は
  混在しない(green 失敗 → exit 1 / blue timeout → exit 124)

### 2.3 audit_logs の event_hash 再計算(E2E Scenario 1 の Then)

- 「各行の event_hash は audit-event-contract.yaml の hash_chain.canonical_form に従って再計算した値と一致する」は、
  テスト側(JS)にも canonical_form(13 項目 `|` 連結・null 空文字・`\` と `|` のエスケープ・末尾 `|previous_hash`・SHA-256)の
  実装を要する。S6 で契約から転写して実装する(実装側 facade/src/domain.sh の関数を流用しない。独立に再計算する)

### 2.4 credential_ref から解決した秘密鍵の起動イベントへの反映

- E2E「blue 実装への起動イベントは /etc/relaygate/credentials/cred-blue-batch を秘密鍵として送出される」は
  ssh 引数列(起動ログ)に鍵ファイルパスが現れることで観測する前提(bats は `-i` 相当のパス出現を assert)。
  cli-command-contract.yaml credential_resolution は「解決したファイルを秘密鍵とする」とだけ定め、ssh への渡し方
  (`-i <path>` / `IdentityFile` オプション)は実装判断。S4 が決めた渡し方に S6 の step を合わせる
- 鍵のパーミッション検査(0600 以外は業務エラー exit 1)は E2E に Scenario が無い。S4 の単体テストで扱う

### 2.5 ATDD SPEC-009-03-2 の「role 別・slot 別の値は保存されない」

- rdb-schema.yaml に role 別 / slot 別の hang_detect_limit_minutes 列が無いことと、execution_specs の 1 値が
  background role の slot の値(green=45)であることで検証する(スキーマ検査 + 値検査)

## 3. 契約再生成で attempt 6 の実装が既に赤になっている(S2 前のベースライン)

- bootstrap S0 の再実行で `packages/contracts/relay-gate-db/schema-constants.sh` が再生成され
  (`job_map_version` が execution_specs から slot_execution_specs へ移動)、attempt 6 の実装は契約定数の列で
  INSERT 文を組み立てるため、S2 着手前の時点で tier BDD 3 Scenario 中 1 件が fail していた(execution_specs の
  INSERT が新スキーマで失敗 → 起動前監査ゲートにより exit 1)
- 旧仕様の単体テスト `facade/test/6078c4ed_select_slot.bats`(38 件)は 18 件 fail。原因は上記の契約再生成と
  旧環境変数 `RELAYGATE_JOB_MAP_PATH`(契約で廃止)前提の fixture。S4 で新仕様に合わせて整理する(削除 / 更新の判断は S4)
- PostgreSQL 経路のテスト(`6078c4ed_select_slot_postgresql.bats`)はハーネスを新契約に差し替え、fixture DDL
  (`facade/test/fixtures/relay-gate-db.postgresql.sql`)を rdb-schema.yaml から再生成した。assertion の期待値も
  新仕様(JSON 配列 / hang_detect 45 / slot 別 job_map_version)へ改めたため、S4 完了まで 5 件とも fail する

## 4. 前回 issue(20260821T220045Z)の解消状況

| 前回の項目 | 状況 |
|---|---|
| §2 並走 Scenario の RUNNING 遷移(UC c3c7ab31 依存) | CR で Then が「STARTING で存在」「送出順」「10 秒以内に応答」へ改められ解消。`SSH_STUB_CONCURRENT` の RUNNING 注入を削除した |
| §3 credential_ref が Given に無い | Background に credential_ref と認証情報ディレクトリが追加され解消 |
| §5 event_hash の正規化形式 | audit-event-contract.yaml hash_chain.canonical_form が追加され解消(§2.3 で S6 が転写する) |
| §6 additional_args / fixed_args の保存形式 | JSON 配列(argument_serialization)で確定。足場は JSON 配列を assert する |
| §7 10 秒以内の対象 | 「起動受付(transaction commit と起動イベント送出)まで」に限定され解消 |
| §8 送出失敗 / timeout の補償記録 | FAILED(attempt_failed)/ UNKNOWN(attempt_unknown)と slot_launch_failed / slot_launch_timeout が本 UC の仕様になり解消 |
| §10 テスト用 DDL の所有 | 未解消(worker/migrations は未整備)。fixture は生成器で再生成する運用を継続 |
| §12 USDM SPEC-009-03 の文言 | USDM が「run 共通の実行設定(execution_specs)と slot 別実行設定(slot_execution_specs)」へ改められ解消。SPEC-009-03-2 が追加された |
