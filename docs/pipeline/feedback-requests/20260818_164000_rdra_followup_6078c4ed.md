---
schema_version: distillery.feedback-request/v1
feedback_id: 20260818_164000_rdra_followup_6078c4ed
created_at: 2026-08-18T16:40:00+09:00
source: distillery-impl
uc_id: 6078c4ed
---

# パイプライン還流からの変更要求

本書は feedback request `20260818_113601_impl_feedback_6078c4ed` の完了時に確認された後続課題を、ユーザーレビュー確定済みの採用案として再定義する。次の事項は確定済みであり、再選定を求めない。

- slot 別実行設定・起動試行 identity・実行状態 6 値は RDRA モデルへ追随反映する(docs/todo.md DIST-023 の案A)
- RDRA 状態モデルへ STARTING / UNKNOWN を追加し、design の states セクションにも反映する(docs/todo.md DIST-024 の案A)
- 比較定義の情報エンティティを RDRA へ追加し、SPEC-012-03 の網羅ギャップを解消する(rdra-feedback.md の対応方針を採用)
- respond-foreground の終了コードは foreground の exitcode.txt 値をそのまま透過し、relay-gate 自身のエラーは専用退避コードへ分離する。relay-gate エラー時の stderr には foreground の stderr.log 内容(取得可能な場合)と relay-gate のエラー内容を併記してジョブスケジューラへ返す
- 反映後、DIST-023 / DIST-024 は closed にし、網羅ギャップ解消後は rdra-feedback.md の要望を解消済みとして扱う

## CR-6078c4ed-008: slot別実行設定・起動試行identity・実行状態6値をRDRAへ追随反映する

- severity: spec-gap
- related_ids: [E-001, E-007, SPEC-008-01]
- related_files: [docs/rdra/latest/情報.tsv, docs/rdra/latest/状態.tsv, docs/arch/latest/arch-design.yaml]

### 観測した事実

アーキテクチャ設計イベント `20260818_135504_arch_slot_config_attempt_identity` は、run 共通の execution spec(E-001)と slot 別実行設定(E-007: host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref)の分離、Runner 実行結果の identity への attempt_id / attempt_no / accepted_at の導入、実行状態 6 値(STARTING / RUNNING / SUCCEEDED / FAILED / UNKNOWN / ABORTED。timeout 後は推測で FAILED を確定せず UNKNOWN)を正式定義した。一方、RDRA の情報モデルは execution-spec.json を単一情報のまま保持し、状態モデルの background slot 実行状態は RUNNING / SUCCEEDED / FAILED / ABORTED の 4 状態のままである。デザインシステムはコンポーネント層(StatusBadge / RunnerResultPanel)でのみ 6 値を反映し、RDRA 状態モデル由来の states セクションは 4 値に留まる。この粒度差は docs/todo.md の DIST-023 / DIST-024 として記録された。

### 現在の仕様と問題

上位モデル(RDRA)と設計正本(arch)で、実行設定の構造と実行状態の粒度が食い違う二重正本になっている。RDRA 整合性ルールにより下流スキルは RDRA に無い要素を自動追加できないため、このままでは以後の差分再生成のたびに同じ粒度差が確認事項として再浮上し、トレーサビリティも arch 起点でしか追えない。

### 変更してほしいこと

確定済みの採用案を反映する: RDRA の情報モデルへ slot 別実行設定の分離(run 共通 execution spec と slot 別実行設定)と Runner 実行結果の起動試行 identity(attempt_id / attempt_no / accepted_at)を追随反映し、状態モデルの background slot 実行状態へ STARTING と UNKNOWN の遷移(起動受付 → STARTING、timeout 等の結果不明 → UNKNOWN、UNKNOWN からの回復遷移)を追加する。arch イベント `20260818_135504` の定義を正とし、意味を変えずに RDRA の粒度へ写像すること。反映後、下流(design の states セクションを含む)を整合させ、DIST-023 / DIST-024 を closed にする。

### 完了条件

RDRA の情報・状態モデルが arch の slot 別実行設定・起動試行 identity・実行状態 6 値と矛盾なく対応し、下流成果物(design states セクション、spec のトレーサビリティ)が RDRA 起点で 6 値と attempt identity を追跡できる。DIST-023 / DIST-024 が closed である。

## CR-6078c4ed-009: 比較定義の情報エンティティをRDRAへ追加しSPEC-012-03の網羅ギャップを解消する

- severity: spec-gap
- related_ids: [SPEC-012-03, REQ-012]
- related_files: [docs/rdra/latest/情報.tsv, docs/usdm/latest/requirements.yaml, docs/specs/latest/_cross-cutting/rdra-feedback.md]

### 観測した事実

仕様生成の USDM acceptance criteria 逆引き行列で、SPEC-012-03「比較定義は job_id ごとに差し替えられる」に対応する検証 Scenario を定義できず、網羅率が 42/43(97.7%)に留まった。比較定義(job_id ごとの比較対象・比較実装を保持する情報)に相当するエンティティが RDRA 情報モデルに存在せず、RDRA 整合性ルールにより Spec 側での発明が禁止されているためである。この事実は `docs/specs/latest/_cross-cutting/rdra-feedback.md` に記録された。

### 現在の仕様と問題

USDM には要求(SPEC-012-03)が存在するのに、RDRA 情報モデルに対応する情報が無いため、検証可能な Scenario を仕様に書けない。実装フェーズでは比較定義の差し替えを実装対象に含められない状態が続く。

### 変更してほしいこと

確定済みの採用案を反映する: RDRA 情報モデルへ「比較定義」の情報エンティティを追加する。属性の候補は job_id / 比較対象テーブル / 比較対象ファイル / 比較実装識別子 / 有効期間(rdra-feedback.md 記載の候補を出発点とし、既存の情報モデルの粒度に合わせて確定する)。追加後、下流の仕様再生成で SPEC-012-03 の acceptance criterion(job_id に応じた比較定義の適用)を検証する Scenario を定義し、逆引き行列の網羅率を 100% にする。

### 完了条件

RDRA 情報モデルに比較定義エンティティが存在し、SPEC-012-03 を検証する Scenario が仕様成果物に定義され、USDM acceptance criteria 逆引き行列の網羅率が 43/43(100%)である。rdra-feedback.md の変更要望 #1 が解消済みとして扱われている。

## CR-6078c4ed-010: respond-foregroundの終了コードを透過にしrelay-gateエラーを分離する

- severity: spec-gap
- related_ids: [REQ-002, SPEC-002-01]
- related_files: [docs/usdm/latest/requirements.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

USDM SPEC-002-01 の acceptance criterion は「stdout.log / stderr.log / exitcode.txt の内容がそのままジョブスケジューラへ中継される」と透過を規定している。UC spec のデータフロー図・シーケンス図も「プロセス終了コード = exitcode.txt 値」と透過を記述している。一方、CLI コマンド契約(`relaygate concurrent-run respond-foreground` の exit_codes)は「exit_code=0 → 0、非0 → 一律 1、未確定 / UNKNOWN / ABORTED → 1、run_id 未指定 → 2」の写像を定義しており、USDM および UC spec の図と矛盾する。非0 の終了コードを検証する BDD シナリオは存在せず、どちらが正かを仕様から確定できない。

### 現在の仕様と問題

写像のままでは、業務ジョブの終了コードの具体値(例: 3)が 1 に潰れ、ジョブスケジューラ側の終了コード分岐が既存ジョブ直接実行時と互換にならない。また業務ジョブの失敗(非0)と relay-gate 自身のエラー(実行結果未確定等)が同じ終了コード 1 になり、スケジューラから区別できない。ストラングラーファサードとしてスケジューラから見た挙動を既存ジョブと揃える前提に反する。

### 変更してほしいこと

確定済みの採用案を反映する: respond-foreground の終了コードは foreground の exitcode.txt 値をそのままプロセス終了コードとして透過する(0 を含む全値)。relay-gate 自身のエラーは業務ジョブが通常使用しない専用退避コードへ分離する(候補: 実行結果未確定・取得不能・中止済み = 125、バリデーションエラー = 126。bash 予約コード 126/127 との整合を確認のうえ確定してよい)。relay-gate エラー時の stderr は、foreground の stderr.log の内容(取得可能な場合)と relay-gate のエラー内容(原因と次アクション)を併記してジョブスケジューラへ返す。UNKNOWN を推測で FAILED 相当の終了コードへ変換しない方針は維持する。USDM には relay-gate エラーの退避コード分離と stderr 併記の要求を追記し、CLI コマンド契約・UC spec・BDD シナリオ(非0 透過のケースを含む)を整合させる。

### 完了条件

USDM・UC spec・CLI コマンド契約の終了コード規定が「foreground の exitcode.txt 値の透過 + relay-gate エラーの専用退避コード + relay-gate エラー時の stderr 併記」で一致し、非0 の終了コードが透過されることと relay-gate エラーが退避コードで分離されることを検証する BDD シナリオが存在する。
