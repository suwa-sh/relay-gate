# UC 6078c4ed as-built summary

## 確定済み as-built

- `BLUE_MODE`、`GREEN_MODE`、`RAPID_CROSSCHECK_MODE` を execution-spec.json に完全保存し、SSH 環境にも同じ確定値を渡す。
- CLI 開始時点から単一の 8 秒 monotonic deadline を用い、初期化、ジョブマップ、DB、SSH、補償処理を残余時間内に実行する。
- execution-spec.json は同一ディレクトリの一時ファイルを `0600` で作成して atomic rename する。
- DB の初期記録は transaction で作成し、ファイル、DB、SSH の失敗を補償する。timeout 時は process group を終了する。
- TDD 22件、UC BDD 5件、ATDD 6件が pass している。S6/S7 は指定 manifest projection v2 で pass している。

## 未確定または矛盾する仕様

- remote 受理・開始・冪等再送・timeout 後状態、execution-spec の共有配送、ジョブマップ/RDB/SSH の相互運用契約、slot 別 impl_version と runner_results 識別は未確定である。
- slot 起動の監査 event schema、sink、保持・保全、run_id 相関は未確定である。

## issues の分類

| 入力 | 分類 | 根拠と扱い |
|---|---|---|
| `20260817T000000Z_select-slot-runtime-contract.md` | 仕様起因 | `tier-facade.md` は job map/RDB/SSH を要求するが、形式・製品・認証・slot別 version を定義しない。CR-001へ統合。 |
| `20260817T132241Z_facade-lint-entrypoint.md` | 環境/ツール起因 | `impl-config.yaml` の `find facade -name '*.sh'` が extensionless Bash を漏らす。business/spec の不足ではないため feedback に含めない。 |
| `20260817T230000Z_remote-handshake-rdb-audit-contract.md` | 仕様起因 | `tier-facade.md`、`rdb-schema.yaml`、`cli-command-contract.yaml` に remote/RDB/監査の境界契約がない。CR-001、CR-002へ統合。 |

## S5 findings の分類と履歴

| findings | 分類 | 根拠 path | 最終扱い |
|---|---|---|---|
| F-001, F-002 | 実装起因 | `attempt-1/S5_verify.tier-facade.findings.yaml` | timeout と SSH 失敗補償を実装済みで閉鎖。 |
| F-003 | 環境/ツール起因 | `attempt-1/S5_verify.tier-facade.findings.yaml`, `impl-config.yaml` | lint entrypoint 漏れ。設定改善の学びとして記録し、feedback 対象外。 |
| F-004〜F-008 | 実装起因 | `attempt-1/S5_verify.tier-facade.findings.yaml` | 入力検証、診断、テスト、nullable、構造を後続 attempt で修正し閉鎖。 |
| F2-001〜F2-005, F2-007, F2-009〜F2-010 | 実装起因 | `attempt-2/S5_verify.tier-facade.findings.yaml` | execution-spec、deadline、transaction、入力/SSH、診断、nullable を後続 attempt で修正し閉鎖。 |
| F2-006 | 仕様起因 | `attempt-2/S5_verify.tier-facade.findings.yaml`, `tier-facade.md` | RDB 接続契約未定義。CR-001へ統合。 |
| F2-008 | 環境/ツール起因 | `attempt-2/S5_verify.tier-facade.findings.yaml`, `impl-config.yaml` | lint 対象漏れと当時のテスト範囲。lint は設定起因、テスト不足は後続で閉鎖。 |
| F3-001, F3-002, F3-004, F3-006, F3-008, F3-009 | 実装起因 | `attempt-3/S5_verify.tier-facade.findings.yaml` | mode 保存、deadline、file/DB 補償、引数境界、テスト、診断を後続 attempt で修正し閉鎖。 |
| F3-003, F3-005 | 仕様起因 | `attempt-3/S5_verify.tier-facade.findings.yaml`, `tier-facade.md`, `rdb-schema.yaml` | runtime 境界と remote handshake の未定義。CR-001へ統合。 |
| F3-007 | 仕様起因 | `attempt-3/S5_verify.tier-facade.findings.yaml`, `arch-design.yaml`, `rdb-schema.yaml` | slot 起動監査の実装可能な契約がない。CR-002へ統合。 |
| F3-010 | 仕様起因 | `attempt-3/S5_verify.tier-facade.findings.yaml`, `_model-summary.yaml`, `rdb-schema.yaml` | model summary の INSERT 要求と `used_by` の不整合。CR-001で runner_results 契約と併せて解消する。 |
| F4-001, F4-002 | 実装起因 | `attempt-4/S5_verify.tier-facade.findings.yaml`, `attempt-5/S5_verify.tier-facade.findings.yaml` | attempt 5 closure が deadline 初期化と process group cleanup の閉鎖を確認。 |
| F4-003 | 仕様起因 | `attempt-4/S5_verify.tier-facade.findings.yaml`, `tier-facade.md`, `rdb-schema.yaml` | CR-001へ統合。 |
| F4-004 | 仕様起因 | `attempt-4/S5_verify.tier-facade.findings.yaml`, `arch-design.yaml`, `rdb-schema.yaml` | CR-002へ統合。 |
| F5-001 | 仕様起因 | `attempt-5/S5_verify.tier-facade.findings.yaml` | 最終 ACCEPT 後も残る runtime 境界。CR-001。 |
| F5-002 | 仕様起因 | `attempt-5/S5_verify.tier-facade.findings.yaml` | 最終 ACCEPT 後も残る監査境界。CR-002。 |

最終 attempt は blocker 0 である。実装で閉鎖済みの blocker（F-001、F-002、F2-001、F2-002、F3-001、F3-002、F4-001、F4-002）は feedback request に含めない。
