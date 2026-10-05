# S2 test-scaffold 完了(eff24f55 slot ごとのジョブマップを定義する)

- UC BDD 16 Scenario / tier BDD(tier-facade)14 Scenario を spec.md / tier-facade.md の gherkin からそのまま転写した
- ATDD は SPEC-004-04-4 / SPEC-008-05-2 の step skeleton のみ追加した(feature 本文は不変)
- TDD は `validate-config.sh --job-map` のエントリポイント経由 bats 4 件
- red baseline: 追加分はすべて未実装を理由に fail。undefined / ambiguous step は 0 件。先行 UC のテストは全件 pass のまま
- 申し送り(issues/20260919_161456_cross-uc-scenarios.md): ATDD の When「設定を検証する」は先行 UC の step と同一文言のため、S7 で検証種別による起動切替へ拡張する
