# S1 uc-init 完了(eff24f55 slot ごとのジョブマップを定義する)

- UC 用 branch `feature/define-slot-job-maps` を main `9bb6057` から開始した
- input-preflight: spec.md / tier-facade.md / _api-summary.yaml / _model-summary.yaml が実在し、YAML は parse 可能。gherkin ブロックは spec.md 2 / tier-facade.md 1
- tier id(tier-facade)は arch tiers[] に含まれる。条件付き生成物と capability に矛盾なし(async_event_count 1、asyncapi.yaml あり)
- input-manifest を確定した。系譜は spec-event の trigger `arch:20260908_015000_feedback_slot_status_wording` = arch latest で整合(lineage_ok: true)
- 共有仕様参照は UC1 と同じ 5 ファイル(spec.md の明示参照 asyncapi.yaml / cli-command-contract.yaml と、その推移的参照)。openapi.yaml は `paths: {}` のスタブで共有定義を持たないため含めない
- UC→ATDD マッピングは `20260917_004437_config_confirmed_atdd_mapping_all_ucs` で確定済みのため再確認しない(SPEC-004-04-4 / SPEC-008-05-2)
- UI 画面なし(has_design_system: false)のため screen 解決は対象外
