# Spec Event Summary

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20261123_201000_feedback_impl_feedback_7c41c7cd |
| Created At | 2026-11-23T20:10:00Z |
| Source | Spec 差分更新(design 無しモード。2026-11-23 の利用者決定 3 件の反映。3 件とも案 A)。(1) 入力の複製の作業名: テンプレート relay-gate-<プロセスの番号>-XXXXXX.part を mktemp に渡して作る。番号は BASHPID をコマンド置換の外で取る。.part を外した最終名へ rename し、最終名を先に確保しない定めと両立させた。1 つのプロセスが同時に持つ複製は 1 つまで。複製を作る実行時の読み手にも適用する。予測可能性の代償を判断記録に残した(CLI 契約 config_input_rules.snapshot.work_name。decisions/spec-decision-041)。(2) 共通ライブラリ lib/runner-resolve.sh の 5 関数(引数の違反の報告・解決の入口・補助 2 つ・二重起動の判定)を、自作の runner へ約束する入口として呼び方を定めた。後方互換を保つ対象(CLI 契約 runner IF の standard_runner.runner_resolve_library。spec-decision-042)。(3) あるが読めない・通常のファイルでないジョブマップは、feature flag の検証・ジョブマップの検証・slot runner のどれも error: config file is not readable path: <場所> で報告する。feature flag の検証では job map not found と同じ位置(blue → green)に出す(config_files.feature-flag.env.job_map_location.presence_report。spec-decision-043)。元の方針資料(しくみ・利用イメージ)には 3 件とも記載が無く、食い違いは無い。上流(usdm / rdra / nfr / arch / infra)は今回変わらない。確認推奨項目 5 件への利用者の回答(2026-11-23): (a) シンボリックリンクのジョブマップはリンク先で判定し、表示は解決しない場所の文字列のまま(推奨のとおり。判断記録 043 の 3a)。(b) 関数を呼んだ後の set / trap と set -u / -e / pipefail の下の動作は約束しない(推奨のとおり)。(c) build_argument_list に JSON 配列として不正な文字列を渡したときは、戻り値 1 で ARGUMENT_LIST を空にすることを約束する(推奨と違う選択。runner_resolve_library の build_argument_list.on_failure。判断記録 042 の 11)。(d) RUNNER_RESOLVE_STATUS_NOT_RESOLVED は source すると値 1 で定義される変数で、名前と値を後方互換の対象にする(推奨のとおり)。(e) run_id か role が分からない引数の違反は、終了コード 2、成果物を書かず実行ログだけ(推奨のとおり)。trigger_event: rdra:20261116_013000_feedback_standard_runner_job_map_location, arch:20261116_015000_feedback_standard_runner_job_map_location |
| UC 総数 | 34 |
| API 総数 | 0 |
| 非同期イベント総数 | 3 |
| 業務数 | 6 |
| BUC 数 | 8 |

## UC 一覧

| 業務 | BUC | UC | API数 | 非同期 | インフラ |
|------|-----|-----|:-----:|:-----:|:-------:|
| クロスチェック業務 | 確報クロスチェックフロー | 確報クロスチェック結果を確認する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報比較依頼を claim する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報比較依頼を登録して終端状態まで待機する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 比較ツールで日次全量比較を実行して結果を保存する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 保存済みの確報結果をジョブスケジューラへ返す | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報クロスチェック runner へ完了通知を送信する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報比較依頼を claim する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報比較結果を参照する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 比較ツールでジョブ単位比較を実行して結果を登録する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 両系成功時に速報比較依頼を作成する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | ハング検知ジョブの異常終了を確認する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | background 実行の経過時間と終了状態を判定する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | hang_detect_limit_minutes をジョブごとに調整する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | ハング疑い・実行エラー・比較異常を通知する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | 監視記録を保存する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | リラン結果を parent_run_id で追跡する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | リラン対象を検証する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | 元の execution-spec.json から復元して新しい run_id で起動する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | 速報比較依頼だけを新規作成する | 0 | - | - |
| 実行復旧業務 | 実行中止フロー | 現在状態を確認して停止確認に応答する | 0 | - | - |
| 実行復旧業務 | 実行中止フロー | 実行を ABORTED へ遷移させる | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | execution-spec.json を確定保存する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | foreground slot の結果をジョブスケジューラへ中継する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | slot 実行モードを選択して runner を起動する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | ジョブマップで JOB_ID から実行先を解決する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | 業務ジョブの実行結果を確認する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | 実装スクリプトを実行して Runner Result を出力する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | feature flag を設定する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | slot runner の実体スクリプトを割り当てる | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | slot ごとのジョブマップを定義する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | クロスチェックのジョブマップと比較定義を定義する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | 切り替えた運用モードで業務ジョブを実行する | 0 | - | - |
| ハウスキープ業務 | ハウスキープフロー | 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | 0 | - | - |
| ハウスキープ業務 | ハウスキープフロー | 成果物と管理 DB の履歴を削除する | 0 | - | - |

## UC ファイル構成

### クロスチェック業務

#### 確報クロスチェックフロー

- **確報クロスチェック結果を確認する**: spec.md, tier-final-crosscheck.md
- **確報比較依頼を claim する**: spec.md, tier-final-crosscheck.md
- **確報比較依頼を登録して終端状態まで待機する**: spec.md, tier-final-crosscheck.md
- **比較ツールで日次全量比較を実行して結果を保存する**: spec.md, tier-final-crosscheck.md
- **保存済みの確報結果をジョブスケジューラへ返す**: spec.md, tier-final-crosscheck.md

#### 速報クロスチェックフロー

- **速報クロスチェック runner へ完了通知を送信する**: spec.md, tier-facade.md, tier-rapid-crosscheck.md
- **速報比較依頼を claim する**: spec.md, tier-rapid-crosscheck.md
- **速報比較結果を参照する**: spec.md, tier-rapid-crosscheck.md
- **比較ツールでジョブ単位比較を実行して結果を登録する**: spec.md, tier-rapid-crosscheck.md
- **両系成功時に速報比較依頼を作成する**: spec.md, tier-rapid-crosscheck.md

### 実行監視業務

#### background 実行監視フロー

- **ハング検知ジョブの異常終了を確認する**: spec.md, tier-ops.md
- **background 実行の経過時間と終了状態を判定する**: spec.md, tier-ops.md
- **hang_detect_limit_minutes をジョブごとに調整する**: spec.md, tier-facade.md, tier-ops.md
- **ハング疑い・実行エラー・比較異常を通知する**: spec.md, tier-ops.md
- **監視記録を保存する**: spec.md, tier-ops.md

### 実行復旧業務

#### background 側リランフロー

- **リラン結果を parent_run_id で追跡する**: spec.md, tier-ops.md
- **リラン対象を検証する**: spec.md, tier-ops.md
- **元の execution-spec.json から復元して新しい run_id で起動する**: spec.md, tier-facade.md, tier-ops.md
- **速報比較依頼だけを新規作成する**: spec.md, tier-ops.md, tier-rapid-crosscheck.md

#### 実行中止フロー

- **現在状態を確認して停止確認に応答する**: spec.md, tier-ops.md
- **実行を ABORTED へ遷移させる**: spec.md, tier-ops.md

### 実装切替業務

#### 実装切替ジョブ実行フロー

- **execution-spec.json を確定保存する**: spec.md, tier-facade.md
- **foreground slot の結果をジョブスケジューラへ中継する**: spec.md, tier-facade.md
- **slot 実行モードを選択して runner を起動する**: spec.md, tier-facade.md
- **ジョブマップで JOB_ID から実行先を解決する**: spec.md, tier-facade.md
- **業務ジョブの実行結果を確認する**: spec.md, tier-facade.md
- **実装スクリプトを実行して Runner Result を出力する**: spec.md, tier-facade.md

### 適用構成業務

#### 適用構成定義フロー

- **feature flag を設定する**: spec.md, tier-facade.md
- **slot runner の実体スクリプトを割り当てる**: spec.md, tier-facade.md
- **slot ごとのジョブマップを定義する**: spec.md, tier-facade.md
- **クロスチェックのジョブマップと比較定義を定義する**: spec.md, tier-facade.md
- **切り替えた運用モードで業務ジョブを実行する**: spec.md, tier-facade.md

### ハウスキープ業務

#### ハウスキープフロー

- **保持日数を過ぎた終了済みの実行と確報比較依頼を判定する**: spec.md, tier-facade.md, tier-ops.md
- **成果物と管理 DB の履歴を削除する**: spec.md, tier-ops.md

## 全体横断仕様

### UX Design

- User Flows: 5
- IA Pages: 18
- Psychology Principles: 8

### UI Design

- Layout Patterns: 0
- Responsive Breakpoints: 0
- Component Guidelines: 0

### Data Visualization

- Target Screens: 3
- Chart Types: 0
