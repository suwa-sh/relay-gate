# UC 6078c4ed as-built summary(再実装サイクル: spec 20260819_114307 基準)

本書は仕様還流(`20260818_113601` / `20260818_164000`)を反映した仕様に対する再実装の事実を記録する。旧サイクル(execution-spec.json ファイル生成・SQLite 限定・FAILED 補償)の記述は本書で全面的に置き換える。dist-pipeline への入力ではない。

## 確定済み as-built(tier-facade attempt 6 時点)

- CLI `relaygate concurrent-run select-slot --job-id <JOB_ID> [-- <追加引数...>]` を `facade/bin/relaygate` + `facade/src/{presentation,usecase,domain,job_map_gateway,rdb_gateway,launch_gateway,id_gateway}.sh` の層構成で実装した
- 入力検証(presentation 層 `validate_select_slot_environment`)は BLUE_MODE / GREEN_MODE の列挙値・同時 foreground の排他制約・RAPID_CROSSCHECK_MODE・RELAYGATE_OPERATOR をまとめて検証し、違反を全件 stderr へ出して exit 2 にする(LP-001)
- 起動前 transaction を単一 transaction で commit してから外部 slot を起動する: `BEGIN` → execution_specs / slot_execution_specs INSERT → 選択 slot ごとの runner_result_events(attempt_started)+ runner_results(STARTING)INSERT → `SELECT head_hash FROM audit_chain_heads WHERE run_id = ... FOR UPDATE` → audit_logs INSERT(slot_launch_accepted 1 件 + slot_launch_attempted を slot 数)ごとに audit_chain_heads INSERT / UPDATE → `COMMIT`
- RDB gateway は DSN 種別で切り替える: PostgreSQL(`postgresql://` / `postgres://`)は `psql -X -q -w -v ON_ERROR_STOP=1 -c <SQL>` の単一リクエスト、SQLite は `BEGIN IMMEDIATE` + FOR UPDATE 無し(限定検証境界)。psql 不在 = `postgresql_client_unavailable`(exit 1)、接続不能 = `connection`(exit 1)、RDB timeout = exit 124
- 時刻は `clock_now_utc`(perl Time::HiRes)でマイクロ秒精度の UTC ISO 8601 を生成し、accepted_at / occurred_at / updated_at / 監査 occurred_at に同一値を記録する
- 監査 event_hash は契約 fields 順 13 項目を `|` 連結、null は空文字、末尾に `|previous_hash`、SHA-256 hex で算出する(仮置き。CR-011 参照)
- additional_args / fixed_args は各引数を `%q` でクォートした空白連結の 1 文字列として保存・伝播する(仮置き。CR-014 参照)
- 起動順は background → foreground。SSH は起動イベントの送出(handshake)として扱い、全外部 I/O を単一 deadline 8 秒で打ち切る。送出失敗は stderr 診断(`boundary=ssh, reason=ssh_failure|timeout`)+ exit 1 のみで、runner_results / audit_logs は STARTING 固定のまま変更しない(CR-012 参照)
- credential_ref は参照名のみ保存し、SSH 鍵解決には使っていない(CR-017 参照)。ジョブマップは JSON slot-entry 形式を jq で読み、未知フィールドは無視する(CR-018 参照)
- テスト: TDD 51 件(うち実 PostgreSQL 5 件。`initdb`/`pg_ctl` 一時インスタンスまたは docker、暗黙 skip 無し)× 3 回連続 pass、tier BDD 3 Scenario、UC BDD 9 Scenario(2 回連続)、ATDD 6 Scenario(3 回連続)が pass。独立検証(attempt 6)は blocker 0
- テスト DDL は `facade/test/fixtures/generate-postgresql-schema.py` が rdb-schema.yaml から生成した `facade/test/fixtures/relay-gate-db.postgresql.sql`(正本は rdb-schema.yaml / `worker/migrations`。後者は未整備)

## 仕様との対応(仕様どおり / 不足 / 矛盾)

| 項目 | 区分 | 内容 |
|---|---|---|
| CLI 契約(引数・環境変数・stdout 行・終了コード 0/1/2/124) | 仕様どおり | tier BDD 3 Scenario の Gherkin 27 行が仕様と完全一致。exit 130 は未検証 |
| 起動前監査ゲート・FOR UPDATE・同一 transaction | 仕様どおり | 実 PostgreSQL の statement ログで検証 |
| status=STARTING 固定・後続遷移は後続 UC | 仕様どおり | attempt 5 の FAILED/UNKNOWN 補償を撤回して整合 |
| event_hash 正規化形式 | 不足 | 契約未定義。仮置き形式(CR-011) |
| 起動失敗後の STARTING 滞留の扱い | 不足 | foreground role は検知・確定 UC が無い(CR-012) |
| E2E Scenario「並走」の Then 2・3 行目 | 矛盾 | 後続 UC の責務、CTP-009 10 秒と 60 秒待ちが両立しない(CR-013)。UC BDD はハーネス注入で通過 |
| additional_args / fixed_args の保存形式 | 不足 | `%q` 連結を仮採用(CR-014) |
| 物理型・datetime 精度・uuid 形式 | 不足 | fixture 生成器の対応表を仮採用(CR-015) |
| USDM SPEC-009-03「execution-spec.json」「role ごと」 | 矛盾 | spec.md / rdb-schema と食い違う(CR-016) |
| credential_ref の解決・Given 値 | 不足 | facade 側の SSH 認証契約無し、Given に値無し(CR-017) |
| ジョブマップ形式 | 不足 | JSON slot-entry 形式を限定境界として採用(CR-018) |
| バリデーション順序(tier Scenario 2 で RAPID_CROSSCHECK_MODE 未設定) | 仕様どおり(吸収) | 全パラメータ一括検証(LP-001)で成立。CR 化しない |

## issues の分類

| 入力 | 分類 | 根拠と扱い |
|---|---|---|
| `issues/20260821T220045Z_select-slot-spec-reflow-test-boundary.md` §1(FOR UPDATE と SQLite 境界、CI の PostgreSQL 配線) | 実装・環境起因 | PostgreSQL 経路は attempt 6 で実装済み。CI(`.github/workflows/ci.yml` tdd job)で `initdb`/`pg_ctl`/`psql` を PATH へ載せる対応が write-set 外で未了。feedback に含めない |
| 同 §2 / §7(並走 Scenario の責務、10 秒 vs 60 秒) | 仕様起因 | CR-013 |
| 同 §3(credential_ref Given 欠落) | 仕様起因 | CR-017 に統合 |
| 同 §4(バリデーション順序) | 実装で吸収 | LP-001 の一括検証で成立。feedback に含めない |
| 同 §5(event_hash 正規化) | 仕様起因 | CR-011 |
| 同 §6(引数保存形式) | 仕様起因 | CR-014 |
| 同 §8(起動失敗時の補償・STARTING 滞留、credential_ref 鍵解決) | 仕様起因 | CR-012 / CR-017 |
| 同 §9(旧テスト整理) | 実装起因 | attempt 5 で更新済み |
| 同 §10 / §11(テスト DDL の所有・物理型、サブ秒精度) | 仕様起因 | CR-015。fixture 生成器は migration 整備まで暫定運用 |
| 同 §12(USDM SPEC-009-03 文言) | 仕様起因 | CR-016 |
| 同 §13(認証情報非保存の検証方法) | 記録 | 実装の検証方法の記録。feedback に含めない |
| 同 §14(ATDD feature の uc タグ) | 環境・ツール起因 | bootstrap 再生成時のタグ保持はオーケストレータ判断。feedback に含めない |
| `issues/20260817T000000Z_select-slot-runtime-contract.md` | 一部未解決(仕様起因) | RDB 製品・slot 別 impl_version・attempt identity は反映済み。ジョブマップ形式のみ未契約 → CR-018 |
| `issues/20260817T132241Z_facade-lint-entrypoint.md` | 環境・ツール起因 | `impl-config.yaml` の lint は依然 `find facade -name '*.sh'`。実装は `facade/bin/relaygate` を明示的に shellcheck して補っている。feedback に含めない |
| `issues/20260817T230000Z_remote-handshake-rdb-audit-contract.md` | 反映済み | RDB 製品・監査契約・lock 契約は反映済み。残る remote handshake(timeout 後状態)は CR-012 に包含 |

## S5 findings の分類

| findings | 分類 | 根拠 path | 最終扱い |
|---|---|---|---|
| F-001(attempt 5: PostgreSQL 経路未実装・FOR UPDATE 未発行) | 実装起因 | `stages/attempt-5/S5_verify.tier-facade.findings.yaml` | attempt 6 で psql 経路と実 PostgreSQL テストを実装し resolved |
| F-002(attempt 5: 秒精度 occurred_at による順序 flaky) | 実装起因(契約の精度未定義が背景) | 同上 | マイクロ秒精度で resolved。精度の正本化は CR-015 |
| F-003(attempt 5: SSH 失敗時に FAILED/UNKNOWN 出力) | 実装起因(仕様逸脱) | 同上 | STARTING 固定へ戻して resolved。起動失敗後の扱いの未定義は CR-012 |
| F-001(attempt 6 初回検証: PostgreSQL テスト未実行) | 環境起因 | `invalidated/20260822_103000_s5_attempt_6_verify_env_invalidated/attempt-6/S5_verify.tier-facade.findings.yaml` | 検証環境(codex サンドボックス)で loopback TCP socket と SysV shared memory が拒否され PostgreSQL を起動できなかった。環境を変えて再検証し attempt 6 findings 0 件で閉鎖 |
| attempt 6(再検証) | findings 0 | `stages/attempt-6/S5_verify.tier-facade.findings.yaml` | blocker / major / minor すべて 0 |

## ハーネス注入(UC BDD)

- Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」のみ、ssh スタブ `SSH_STUB_CONCURRENT` で UC c3c7ab31(background 起動 UC)の RUNNING 遷移を模擬している。削除条件は UC c3c7ab31 と foreground 応答 UC(5652f987)の実装後の UC 横断再検証、または CR-013 による Then の改訂
