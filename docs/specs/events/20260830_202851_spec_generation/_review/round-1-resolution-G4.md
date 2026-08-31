# round-1 resolution (G4)

所有範囲: `実行監視業務/background 実行監視フロー/hang_detect_limit_minutes をジョブごとに調整する/`、`実行復旧業務/実行中止フロー/`、`実行復旧業務/background 側リランフロー/`。契約(`_cross-cutting/`)は別担当のため未編集。

## 対応表

| finding id | severity | resolution | 内容 | 変更ファイル |
|---|---|---|---|---|
| F-002 | major | fixed | `--role rapid-crosscheck` の事前検証は execution-spec.json を要求せず `rapid_crosscheck_requests` のみで元実行を特定するよう、検証 UC の概要・データフロー・sequence(role で最初に分岐)・バリエーション「元実行の特定元」・分岐条件・計算ルール・事前検証表を分岐。数珠つなぎ用 BDD(E2E「rapid-crosscheck リランで作られた run を再度リラン元にできる(SPEC-009-01)」、tier「rapid-crosscheck は execution-spec.json が無い run でも依頼レコードだけで通過する」、依頼再作成 E2E「再作成した run をさらに再作成して系譜を伸ばす(SPEC-009-01)」)を追加。依頼再作成 UC(spec / tier-ops / tier-rapid-crosscheck)と BUC spec に数珠つなぎ成立の記述を追加 | リラン対象を検証する/{spec.md, tier-ops.md, _api-summary.yaml}、速報比較依頼だけを新規作成する/{spec.md, tier-ops.md, tier-rapid-crosscheck.md}、background 側リランフロー/buc-spec.md |
| F-025 | major | fixed | abort-final-crosscheck.sh は RAPID_CROSSCHECK_MODE を参照せず、`final-crosscheck.env` / FINAL_DB_CONN_REF の有無だけで管理 DB 有無を判定(不在は `error: management db is not configured run_id=...` 終了コード 3)。off 時の 3 は abort-blue / abort-green / abort-rapid-crosscheck のみに限定。tier-ops「RAPID_CROSSCHECK_MODE=off」節を「管理 DB 有無の判定」節に書き換え、終了コード表・spec sequence・分岐条件・BUC 共有条件を修正。BDD(tier 2 本、E2E「確報の中止は速報モードに依存しない」)を追加 | 現在状態を確認して停止確認に応答する/{spec.md, tier-ops.md}、実行を ABORTED へ遷移させる/spec.md、実行中止フロー/buc-spec.md |
| F-026 | major | fixed | 計算ルール「元 mode の解決」を「`slots.{role}` 節が存在しない → mode=off とみなす」に改め、tier-ops の Given を「execution-spec.json に slots.blue 節が無く」に修正。事前検証表・stderr 表・バリエーション off 行にも節なし判定を明記 | リラン対象を検証する/{spec.md, tier-ops.md, _api-summary.yaml} |
| F-007(所有範囲分) | major | fixed | 復元起動 UC の Then の固定 run_id(`20260830T124500Z-JOB001-7b2d9e01`)を `{新 run_id}` + 正規表現 `^[0-9]{8}T[0-9]{6}Z-JOB001-[0-9a-f]{8}$` の形式検証に書き換え(正常系 1 本 + 異常系 2 本、計算ルール「新 run_id」に注記)。abort の `aborted_at=2026-08-30T12:40:00Z` は Given にテスト専用環境変数 `RELAY_GATE_NOW=2026-08-30T12:40:00Z` を置く形に書き換え、計算ルール aborted_at と tier-ops に「設定時は now() の代わりに使う。本番未設定」を明記。他 BUC(判定・通知 UC、確報 claim UC)は所有範囲外 | 元の execution-spec.json から復元して新しい run_id で起動する/spec.md、実行を ABORTED へ遷移させる/{spec.md, tier-ops.md} |
| uc-dependencies 残件 (b) | — | fixed | 復元起動 UC の `_api-summary.yaml` で runner IF(`--execution-spec` モード)を `role: uses` に変更し、定義元 UC「slot runner の実体スクリプトを割り当てる」を invoked_by に明記。tier-facade.md 冒頭と spec.md のティア別仕様リンクも「使用契約(定義元は別 UC)」の表現に修正 | 元の execution-spec.json から復元して新しい run_id で起動する/{_api-summary.yaml, tier-facade.md, spec.md} |
| 必須オプション欠落文言 | — | no change | 所有範囲内はすべて `error: option required option=--xxx` で統一済み(background-rerun / abort-* / run-lineage / hang-detect-trend)。修正なし | — |
| F-029 | minor | deferred | 所有範囲外(実装切替業務・適用構成業務の UC) | — |
| F-034(所有範囲分) | minor | fixed | Scenario タグと SPEC ID の食い違いを複数 SPEC 併記に修正: 検証 UC「foreground の blue は拒否する(SPEC-009-03 / SPEC-009-04)」、abort UC「background かつ RUNNING の green を中止する(SPEC-010-01 / SPEC-010-03)」。関連 USDM 表も更新。他 UC 分は所有範囲外 | リラン対象を検証する/spec.md、実行を ABORTED へ遷移させる/spec.md |
| F-042 | minor | fixed | (1) 契約の readers「started-at.txt なし = 未起動」に UC 側を合わせ、計算ルール「元状態の解決(off)」に「started-at.txt 無し → 未起動(status=`-`、理由コード `source_not_started`)」を追加、E2E「RAPID_CROSSCHECK_MODE=off で started-at.txt が無い元 run は未起動として拒否する」を追加、`_model-summary.yaml` に started-at.txt を追加。(2) 追跡 UC tier-ops 終了コード表 6 に `lineage cycle detected` を追記。(3) 検証 spec sequence の `path=` を `path:` に統一 | リラン対象を検証する/{spec.md, tier-ops.md, _model-summary.yaml, _api-summary.yaml}、リラン結果を parent_run_id で追跡する/tier-ops.md |
| F-043 | minor | deferred | buc-spec の状態遷移全体図・マッピング表(RUNNING → ABORTED のみ)と UC / 契約(STARTED → ABORTED を含む)の食い違いは、buc-spec 注記どおり rdra-feedback(状態.tsv への STARTED → ABORTED 追加)の採否待ち。採否確定前に図を UC 側へ寄せると RDRA 正本との乖離が確定してしまうため round-2 で再確認 | — |

## 集計

- fixed: 7(F-002 / F-025 / F-026 / F-007 / F-034 / F-042 / uc-dependencies (b))
- deferred: 2(F-029 所有範囲外 / F-043 rdra-feedback 待ち)
- no change: 1(必須オプション欠落文言。統一済み)

## 検証

- `npx md-mermaid-lint`: 変更 md 14 ファイルすべて PASS
- `validateApiSummary.js` / `validateModelSummary.js`: 変更 UC 6 ディレクトリすべて PASS

## 契約側(`_cross-cutting/api/cli-command-contract.yaml`)への要求

1. **background-rerun.sh stderr に hint を 1 行追加**: `hint: source run has not started; rerun the scheduler job instead`(off 時に元 slot の started-at.txt が無い = 未起動。error は既存の `source run is not rerunnable ... mode=background status=-`)。exit 3 の condition に「元 slot が未起動(off 時 started-at.txt なし)」を追加
2. **background-rerun.sh exit 3 の condition を role で分岐**: 「元実行・依頼・execution-spec.json なし」→「元実行なし(blue / green: execution-spec.json なし、rapid-crosscheck: 依頼なし。rapid-crosscheck は execution-spec.json を要求しない)」。`artifact_layout.files.execution-spec.json.readers` に background-rerun.sh がある場合は「blue / green のみ」を付記
3. **abort-final-crosscheck.sh**: stderr の管理 DB 未設定文言を `error: management db is not configured run_id=...`(`(RAPID_CROSSCHECK_MODE=off)` 付記なし)とし、exit 3 の condition を「final-crosscheck.env / FINAL_DB_CONN_REF が無い(RAPID_CROSSCHECK_MODE は参照しない)」に修正。abort-blue / abort-green / abort-rapid-crosscheck の 3 は従来どおり `(RAPID_CROSSCHECK_MODE=off)` 付き
4. **environment_variables にテスト専用 `RELAY_GATE_NOW` を宣言**(ISO 8601 UTC。本番未設定。設定時は abort-* の aborted_at / completed_at など now() の代わりに使う)。readers に abort-blue / abort-green / abort-rapid-crosscheck / abort-final-crosscheck を含める(他 BUC の hang-detector / worker も同変数を使う想定)
