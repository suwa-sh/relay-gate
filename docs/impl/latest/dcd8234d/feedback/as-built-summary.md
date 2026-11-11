# as-built summary(dcd8234d クロスチェックのジョブマップと比較定義を定義する / `--verbose` の info 行の規則の還流後の再実装)

- 対象: `validate-config.sh --rapid-crosscheck`(速報の起動コマンド `RAPID_COMPARE_COMMAND` の設定検証。tier-facade のみ)
- 位置づけ: 前回公開した変更要求(`feedback-requests/20261110_080548_impl_feedback_dcd8234d.md`。info 行の文言・出力順・途中の段で止めた回の扱い)が仕様へ反映された後(spec-decision-033、CLI 契約 `config_input_rules.env_files`、tier-facade.md)の再実装サイクルの記録。前サイクルの本ファイルは今回の内容で置き換えた
- 結論: **仕様起因の要求は 0 件**(blocker 0)。draft は作っていない
- 今回新しく出た「仕様に書かれていない前提」2 件(A-003 / A-004)は、人の判断がまだ無い。レビューで利用者が「仕様を変える」と判断した場合だけ、同じサイクルの中で要求に加える(3 章)
- 本ファイルは dist-pipeline への入力ではない

## 根拠にした入力

| 入力 | 内容 |
|---|---|
| `issues/` 7 本 | 過去サイクルの 7 本だけ。今回サイクルの新規起票は無い |
| `stages/attempt-4/S4_tier-impl.tier-facade.assumptions.yaml` | 実装者が補った前提 4 件(候補 8 件のうち 4 件は仕様に明記ありとして除外) |
| `stages/attempt-4/S5_verify.tier-facade.findings.yaml` | blocker 0 / major 0 / minor 4。前提の判定は仕様どおり 1 / 仕様に記載なし 3 / 矛盾 0 |
| `stages/S6_uc-bdd.done.yaml` / `S7_atdd.done.yaml` | UC BDD 46/46、受け入れテスト 7/7 pass。どちらも新規 issue 0 件 |
| `review/review-notes.md` | 最終記録は 2026-11-10。今回サイクルの前提について人の判断はまだ無い |
| `docs/impl/events/20261027_112730_review_approved_dcd8234d_feedback_publish/event.yaml` | 2026-10-27 の前提の承認記録(A-006 = 今回の A-002 と同じ内容が approved) |
| `git show --stat` 0a022fd / ddfe67f / 919a798 | 下記 1 章の実装事実 |

## 1. 今回の実装事実

```mermaid
flowchart LR
  R[仕様の還流<br/>info 行の規則] --> S1[UC 初期化<br/>完了済み段を再実行へ]
  S1 --> S2[テストを規則に合わせる<br/>BDD 4 場面・bats 5 件]
  S2 --> S4[tier-facade<br/>コメントだけ修正]
  S4 --> S5[独立検証<br/>blocker 0 / major 0 / minor 4]
  S5 --> S67[UC BDD 46/46<br/>受け入れ 7/7]
  S67 --> FB[要求 0 件]
```

| 項目 | 値 | 根拠 |
|---|---|---|
| 変更したソース | `facade/src/usecase/validate_rapid_crosscheck.sh`(7 行)、`facade/src/repository/rapid_crosscheck_env.sh`(6 行)。どちらもコメントだけで、動作は変えていない | commit 919a798、S5 readability の note |
| 追加したテスト | tier BDD に 4 場面(stderr の行の並びを完全一致で判定)、bats に 5 件(行数と各行の文言・位置を判定) | commit ddfe67f |
| ゲート | format / lint / tdd / bdd_tier すべて pass。bats 384 件、tier BDD 57 シナリオ・197 ステップ | `S5_verify.tier-facade.findings.yaml` verification_evidence |
| Linux での確認 | ubuntu24 / bash 5.2.21 / GNU sed 4.9 / coreutils 9.4 で対象 42 件 pass(全ゲートの再実行ではない) | 同上 |
| `--verbose` の有無による違い | 14 入力 × 2 ロケール × verbose 有無の 56 実行で、stdout と終了コードは不変、stderr は info 行が増えるだけ | S5 operability の note |
| 補助コマンドの失敗 | tr / sed / cat / mv / mktemp / rm を失敗させた 6 種類すべてで終了コード 6、stdout なし、info / warn なし | S5 fault_tolerance の note |
| UC BDD | 全体 46 シナリオ pass(この UC 10 件、先行 UC 36 件) | `stages/S6_uc-bdd.done.yaml` |
| 受け入れテスト | 7 件 pass | `stages/S7_atdd.done.yaml` |
| 性能(5,000 行、verbose 有効) | 0.472〜1.186 秒。共通前提の 10 秒以内 | S5 performance の note |
| 管理 DB | この UC は DB に触れない | 同上 |

前回のレビューで「次の実装修正の機会に直す」とした `validate_rapid_crosscheck.sh` 102 行目付近のコメントは、今回直った。いまのコメントは「info 行すべて → 未知キーの warn 行すべて → 検証表の error 行」で、実際の出力順と一致する。

## 2. 原因の分類

| 入力 | 分類 | 扱い | 理由 |
|---|---|---|---|
| 前提 A-001(空・欠落時の stdout は `command_path: -` / `has_job_id_placeholder=false`) | 仕様どおり | 要求にしない | 独立検証の判定は「仕様どおり(既存規則の組み合わせの言い直し)」 |
| 前提 A-002(「実行可能」は通常ファイルかつ実行権限) | 承認済み | 要求にしない | 2026-10-27 に同じ内容(当時の A-006)を利用者が承認済み。番号が振り直されただけで内容は同じ |
| 前提 A-003(行数の不一致時に `commands=tr,sed`) | 判断待ち | いまは要求にしない | 人の判断が無い。レビューで利用者が決める(3 章) |
| 前提 A-004(複製の削除の失敗は `commands=rm`、両方失敗なら複製の失敗を優先) | 判断待ち | いまは要求にしない | 同上 |
| 前回公開した要求 2 件(info 行の文言・順・止めた回) | 反映済み | 再び要求にしない | spec-decision-033 と CLI 契約 `config_input_rules.env_files` の「validate-config.sh の --verbose の info 行」(a)〜(d) に入った |
| 他 UC の未追従(4 章) | 実装起因(他 UC) | 要求にしない | 仕様は決まっている。各 UC の再実行で直す |

前提の判定で「仕様と矛盾する」ものは 0 件、記録漏れの前提も 0 件。

### 過去サイクルの issue 7 本(すべて解消済み、または扱いが決まっている。要求にしない)

| issue | 判断 | 根拠 |
|---|---|---|
| 20261010_084142_cross-uc-scenarios | 解消済み | 対象の Scenario(比較定義 CSV・対象カタログ)が仕様から無くなった。spec.md は旧検証種別を未知のオプションとして拒否する |
| 20261010_084142_facade-dispatch-and-csv-parser-outside-tiers | 解消済み | CLI 契約 validate-config.sh の tier_note が「tier-facade が全設定ファイルを自身の解析関数で検証し、他ティアを source しない」と定め、この UC の tier も tier-facade だけになった |
| 20261010_092630_tier-handler-function-namespace-collision | 解消済み | arch-design.yaml の CTR-007 が名前空間の一般規則を定めた。同じシェルに複数ティアを source する構成も無くなった |
| 20261010_093000_tier-bdd-placeholder-scenario-given-then-mismatch | 解消済み | `compare_options` 列と `{blue}` / `{green}` が仕様から無くなった |
| 20261027_083500_cross-uc-scenarios | 置き換え済み | 20261110_073100 に置き換わった |
| 20261027_083600_params-rule-vs-usdm-two-checks | 解消済み | USDM の SPEC-004-04 が検証 3 点に改まり、`_api-summary.yaml` にも反映済み |
| 20261110_073100_cross-uc-scenarios | 該当なし | 責務分担の記録。UC BDD のハーネス注入 0 件(S6 done が参照) |

## 3. 実装の到達点(仕様どおり / 不足 / 矛盾)

この UC は HTTP endpoint・状態遷移・header を持たない。CLI の引数・出力・終了コードで分ける。

| 区分 | 項目 | 状態 |
|---|---|---|
| 仕様どおり | 検証ルール 5 点と違反文言、stdout の固定順 | 実装済み |
| 仕様どおり | env の検査の段(バイト・改行 → 行の構造 → キーごとの検査)、途中で止めた回の stdout | 実装済み |
| 仕様どおり | `--verbose` の info 行の文言・出す回・段の中の順(spec-decision-033) | 実装済み(テストを追加) |
| 仕様どおり | 入力の一時複製(0600、終了時に削除)、補助コマンド失敗時の終了コード 6 と stdout なし | 実装済み |
| 不足(判断待ち) | 原因のコマンドを特定できない行数の不一致時の `commands=` の値 | 実装が補った(A-003) |
| 不足(判断待ち) | 複製の工程と複製の削除が両方失敗したときの診断の優先 | 実装が補った(A-004) |
| 矛盾 | なし | - |

### 実装者が補った前提

| id | カテゴリ | 前提 | 独立検証の判定 | 人の判断 |
|---|---|---|---|---|
| A-001 | data_format | `RAPID_COMPARE_COMMAND` が無い・空のとき、stdout は `command_path: -` と `has_job_id_placeholder=false` | 仕様どおり(F-001、minor。既存規則の言い直し) | 不要 |
| A-002 | input_validation | 「存在し実行可能」は通常ファイルかつ実行権限で判定する(ディレクトリは `file not executable`) | 仕様に記載なし(F-002、minor) | 2026-10-27 に承認済み(当時の A-006、同じ内容)。今回は引き継ぎの確認だけ |
| A-003 | error_handling | バイト点検の行数と行の読み取りの行数が合わないときは `error: internal command failed commands=tr,sed`、終了コード 6 | 仕様に記載なし(F-003、minor) | 未(今回新規) |
| A-004 | error_handling | 読み込み成功後に複製の削除が失敗したら `commands=rm`、終了コード 6。複製の工程も失敗していたら `config snapshot failed` を優先 | 仕様に記載なし(F-004、minor) | 未(今回新規) |

判断待ちの 2 件の補足(レビューで利用者が判断するための材料):

- **A-003**: CLI 契約の `internal_failure` は「`commands=` は実際に失敗したコマンド名だけ」と定める。行数の不一致は、どのコマンドが想定外の出力をしたか特定できない。そのため、いまの実装の「tr と sed を両方書く」は、この定めと一部食い違い得る(実装者も記録している)。独立検証は「矛盾とは立証できない」と判定した。通常の tr / sed の失敗(終了状態が非 0)では、失敗した 1 つの名前だけが出ることを確認済み。起きるのは、補助コマンドが成功を返しながら誤った出力をしたときだけ
- **A-004**: 複製の削除だけが失敗する回の `commands=rm`・終了コード 6 は、契約の工程の区分「(2) 複製完了後の補助コマンドの失敗」に沿う。仕様に無いのは、複製の工程と削除の両方が失敗したときに、どちらの error 行を出すかの優先だけ

## 4. 他 UC の事実(この UC の要求ではない)

| UC | 状態 | 内容 | 根拠 |
|---|---|---|---|
| feature flag を設定する(fd678b04) | completed(再実行待ち) | `validate-config.sh --feature-flag` の `--verbose` の実装が、新しい info 行の規則に未追従。2026-11-11 に利用者が「ほかの 3 種類と同じ規則にそろえ、実装はマージ直後の再実行で直す」と決定済み。前サイクルで記録した env 読み込みの契約への未追従も同じ再実行で直す | spec-decision-033 context、review-notes 2026-11-10 |
| slot ごとのジョブマップを定義する(eff24f55) | completed(再実行待ち) | 前サイクルで記録した tier BDD の Scenario 1 件の不足と、共有のバイト検査の出力順の変化への追従。この機能のマージ直後に再実行する(2026-11-10 利用者決定) | review-notes 2026-11-10 |
| ハウスキープ(validate-config.sh `--housekeep` の担当 UC) | 未実装 | `--housekeep` の検証は未実装。担当 UC の実装時に、info 行の規則も含めて実装する | S5 scope_exclusions |
| 確報クロスチェック(`--final-crosscheck` の担当 UC) | 未実装 | 受け付けて未実装の終了コード 6 を返す(2026-10-27 に承認済みの扱い) | S5 scope_exclusions、review-notes 2026-10-27 |

どれも今回の変更による回帰ではない(今回のソース変更はコメントだけ)。
