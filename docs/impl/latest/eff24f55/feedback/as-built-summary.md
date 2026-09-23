# as-built summary(eff24f55 slot ごとのジョブマップを定義する / 仕様還流 2 回目の後の attempt 6)

- 対象: `validate-config.sh --job-map`(tier-facade のみ)
- 位置づけ: 変更要求 `20260922_130000_impl_feedback_eff24f55`(CR-eff24f55-006 / 007)を仕様へ反映した後の再実装の記録
- 結論: **未解決の仕様起因の要求は 0 件**。今回は変更要求の draft を作らない
- 根拠:
  - `docs/impl/latest/eff24f55/stages/attempt-6/S5_verify.tier-facade.findings.yaml`(blocker 0 / major 0 / minor 24)
  - `docs/impl/latest/eff24f55/stages/attempt-6/S4_tier-impl.tier-facade.assumptions.yaml`(前提 23 件)
  - `docs/impl/latest/eff24f55/stages/attempt-6/S4_tier-impl.tier-facade.done.yaml`
  - `docs/impl/latest/eff24f55/stages/S6_uc-bdd.done.yaml` / `S7_atdd.done.yaml`
  - `docs/impl/latest/eff24f55/issues/` の 6 件(すべて解消済み)
  - `docs/impl/latest/eff24f55/review/review-notes.md`(`spec_change` の却下 0 件)
- 本ファイルは dist-pipeline への入力ではない

## 1. 全体の状態

```mermaid
flowchart LR
  FB1[1 回目の変更要求 5 件<br/>仕様へ反映済み] --> FB2[2 回目の変更要求 2 件<br/>仕様へ反映済み]
  FB2 --> A6[attempt 6 再実行<br/>blocker 0 / major 0]
  A6 --> S67[統合テスト<br/>UC BDD 24 / ATDD 2 pass]
  S67 --> R[今回の変更要求 0 件]
```

| 項目 | 値 |
|---|---|
| ゲート(format / lint / tdd / bdd_tier) | すべて pass(bats 334 件、tier BDD 41 Scenario) |
| UC BDD | pass(対象 feature 24 Scenario、全体 36 Scenario) |
| ATDD | pass(2 Scenario) |
| 独立検証 | blocker 0 / major 0 / minor 24 |
| 性能(NFR B.2.1.1) | 5,000 行の最悪条件で 3.503 秒(上限 10 秒。独立検証の実測) |

## 2. issues の解消判定

| issue | 論点 | 解消の根拠 | 判定 |
|---|---|---|---|
| `20260919_161456_cross-uc-scenarios.md` | UC 横断 Scenario の責務分担の記録 | 仕様疑義ではない(起票時から blocker ではない)。S6 / S7 はハーネス注入なしで pass | 要求不要 |
| `20260919_183305_control-char-notation-and-internal-error-undefined.md` | 制御文字の表記・内部障害の出力 | CLI 契約 `conventions.output_format.control_chars` と `config_input_rules.internal_failure`(1 回目の CR-002 / 003 の反映) | 解消 |
| `20260919_195500_malformed-input-policy-undefined.md` | 入力の守備範囲 | CLI 契約 `config_input_rules`(1 回目の CR-001 の反映) | 解消 |
| `20260919_210000_file-replaced-between-scan-and-parse.md` | 検証中の差し替え | CLI 契約 `config_input_rules.snapshot.validate_config`(単一スナップショット)。実装は複製だけを読み、UC BDD「検証中に差し替わったファイル」が 5 回連続 pass | 解消 |
| `20260922_120000_duplicate-job-id-lines-contract-vs-bdd.md` | 重複 job_id の `lines=` の列挙対象の矛盾 | CLI 契約 `validate-config.sh.stderr` / tier-facade.md 列検証表 / spec.md の本文と BDD が「初出行を含む」に統一(2 回目の CR-006 の反映) | 解消 |
| `20260922_120100_credential-ref-warning-boundary-undefined.md` | credential_ref の形式外の値の扱い | CLI 契約 `columns.credential_ref.on_format_violation` と tier-facade.md「credential_ref の形式の扱い」が「理由を問わず同じ warn で受理、値は出さない」と明記(2 回目の CR-007 案 A の反映) | 解消 |

- 前提 A-012(credential_ref の warn)は、仕様に明記されたため attempt 6 の前提一覧から消えた(仕様の復唱になった)。
- attempt 6 の S4 done、S6 done、S7 done は、いずれも新規 issue 0 件。

## 3. 仕様との対応(実装済みの契約)

HTTP endpoint・状態遷移・header は本 UC に無い。CLI の出力と終了コードで整理する。

### 仕様どおり

- 必須 5 列・任意 4 列、列名での対応付け、ホストとユーザーの片方だけの拒否、ヘッダー列名の重複の拒否
- 入力の守備範囲(NUL / 不正な UTF-8 / BOM / CR)の原因別の拒否と hint、単一スナップショット(TMPDIR、0600、成功・失敗・HUP / INT / TERM で削除)
- 複製の失敗(`config snapshot failed`)と補助コマンドの失敗(`internal command failed commands=<name>`)の区分、終了コード 6
- 重複 job_id の `lines=`(初出行を含む全行番号を出現順)
- credential_ref の形式外の値(`/` や `BEGIN` を含む値、空白・非 ASCII を含む値)は同じ warn 1 行で受理し、値は出さない
- 任意入力の制御文字の可視表記、stdout の固定順、終了コード 0 / 2 / 3 / 6

### 仕様の矛盾

- なし(独立検証の contradicts 0 件)

### 仕様の不足

- 要求が必要な不足はなし
- spec_absent の前提 22 件は、出力順・並び順・検証の打ち切り範囲・内部障害の細部であり、要求にしない(第 4 節)

## 4. 原因の分類

| 分類 | 項目 | 扱い | 根拠 |
|---|---|---|---|
| 仕様起因 | なし | - | issues 6 件はすべて解消済み(第 2 節)。findings に contradicts 0 件 |
| 実装起因 | なし | - | attempt 6 の findings に blocker / major は無い |
| 環境起因 | 開発機(macOS)の mktemp がテンプレート末尾以外の X を置き換えない | 実装側の互換処理(A-052)で吸収。要求に含めない | attempt-6 findings F-018 |
| 対象外 | 分類差 1 件(F-024。A-019 は error_handling が適切) | verdict と severity は変わらない | attempt-6 findings F-024 |
| 対象外 | 仕様の復唱 1 件(F-021。A-055 の rm 失敗は契約に明記済み) | 前提ではなく契約どおり | attempt-6 findings F-021 |

### 要求にしなかったもの

- spec_absent の minor 前提 22 件(F-001〜F-020、F-022、F-023)
  - 要求の対象は「人が `spec_change` で却下した前提」だけである。`review-notes.md` に `spec_change` の却下は 0 件。
  - 過去 2 回のレビューで、同種の前提は一括承認された。
  - 次のレビューで `spec_change` の却下が出たときだけ、refresh で要求に加える。

### レビューで確認してほしい前提(要求ではない)

- A-016(confidence low): spec.md のバリエーション表は「推奨値 60 との差は `info:`」と書く。実装は専用の info 行を出さず、`--verbose` の `info: resolved` 行の `hang_detect_limit_minutes=N` で示すだけにした。
  - 仕様の文言が「専用行を出す」の意味なら、`spec_change` で却下して要求にする。
  - 現行の扱いでよければ承認する(過去 2 回は一括承認)。

## 5. 実装者が補った前提の一覧(attempt 6、23 件)

人の判断: 今回のレビューは未実施。「前回」列は 2026-09-22 のレビュー(一括承認)の判断。

| id | カテゴリ | 前提(要約) | 判定 | 前回の判断 |
|---|---|---|---|---|
| A-005 | error_handling | ヘッダーのクォート不正時はクォート不正だけを全件報告 | spec_absent | 一括承認 |
| A-006 | error_handling | ヘッダー不一致時は列検証と重複検査を省く | spec_absent | 一括承認 |
| A-008 | data_format | missing= は契約の列順 | spec_absent | 一括承認 |
| A-010 | error_handling | 解析不能行は列検証・重複検査・版集計の対象外 | spec_absent | 一括承認 |
| A-014 | data_format | fixed_params= の JSON は空白なし、`/` と非 ASCII はエスケープしない | spec_absent | 一括承認 |
| A-016 | data_format | 推奨値 60 との差の専用 info 行を出さない | spec_absent | 一括承認 |
| A-017 | data_format | map_version の distinct 値は初出順 | spec_absent | 一括承認 |
| A-018 | data_format | distinct 値の空は `-` で表記 | spec_absent | 一括承認 |
| A-019 | error_handling(記録は data_format) | info: resolved は検証を通過した行だけ | spec_absent | 一括承認 |
| A-020 | data_format | stderr の種別間の出力順(検証を終えてからまとめて出す) | spec_absent | 一括承認 |
| A-022 | input_validation | 形式違反の job_id も重複検査の対象、空は除外 | spec_absent | 一括承認 |
| A-025 | data_format | 複数の重複 job_id の error 行は初出行の昇順 | spec_absent | 一括承認 |
| A-043 | error_handling | 検証器内部の障害も commands=<関数名> で終了コード 6 | spec_absent | 一括承認 |
| A-044 | error_handling | 補助コマンドの出力の妥当性(行数・並び順・終端証跡)も検査 | spec_absent | 一括承認 |
| A-049 | error_handling | 重複列名と必須列欠落を同時に報告し、データ行の検証はしない | spec_absent | 一括承認 |
| A-050 | error_handling | 守備範囲の違反があれば他の検証を打ち切る | spec_absent | 一括承認 |
| A-051 | data_format | 同一行の複数原因は BOM → NUL → 不正 UTF-8 → CR の順 | spec_absent | 一括承認 |
| A-052 | data_format | BSD 系 mktemp では作業名を pid と乱数で付け直す | spec_absent | 一括承認 |
| A-053 | error_handling | tr / sed パイプラインの commands= の帰属規則 | spec_absent | 一括承認 |
| A-054 | data_format | unknown column は出現ごとに 1 行 | spec_absent | 一括承認 |
| A-055 | error_handling | 複製の削除 rm の失敗は commands=rm で終了コード 6 | consistent(復唱) | 一括承認 |
| A-056 | error_handling | 複製の工程と削除の同時失敗は複製の失敗を優先 | spec_absent | 一括承認 |
| A-057 | data_format | 補助コマンドと削除の同時失敗は失敗順に連結 | spec_absent | 一括承認 |

- 判定の内訳: consistent 1 / spec_absent 22 / contradicts 0 / unlisted 0
- 前回(24 件)からの増減: A-012 が仕様に明記されたため外れた
- 人が `spec_change` で却下した前提: 0 件

## 6. 方針資料との照合

- 今回は要求が 0 件のため、新たに照合する論点は無い。
- 前回の 2 件の反映結果は、方針資料(認証情報は参照名だけを保存する / 1 行 1 job_id)と矛盾しない。
