# 変更サマリ

- event_id: 20261103_133000_feedback_housekeeping_db_required
- trigger_event: usdm:20261103_131000_feedback_housekeeping_db_required, rdra:20261103_131000_feedback_housekeeping_db_required, nfr:20261103_132000_feedback_housekeeping_db_required
- created_at: 2026-11-03T13:30:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクション: domain_architecture(bounded_contexts / context_map)/ system_architecture(tiers)/ app_architecture(tier_layers)/ data_architecture(entities))
- dialogue_policy: interactive(確認推奨項目は完了報告で返却)
- feedback request: 20261103_housekeeping_db_required(direct work unit: なし。causal work unit: CR-9d2e6c41-001#1(管理 DB を使う機能が 1 つでもあれば、ハウスキープの管理 DB 接続参照名を必須にする)。packet: docs/pipeline/feedback-runs/20261103_housekeeping_db_required/stage-packets/architecture.md)

マージ規則: bounded_contexts / context_map / tiers は `id`、tier_layers は `tier_id`、entities は `name` で照合して diff の要素で置き換えた(diff の要素は latest の当該要素と同一の内容)。meta(event_id / created_at / source)を本イベントの値へ更新した。`confidence: "user"` の要素は変更していない。

## 追加

- decisions: arch-decision-026(接続参照名は管理 DB を使う機能が 1 つでもある設置では必須、欠けたら設定エラーで何も削除しない。arch-decision-025 の「off では省略できる」を改める)(CR-9d2e6c41-001)

## 変更

- system_architecture/tiers/tier-ops/SP-027「ハウスキープの削除判定」: 接続参照名は RAPID_CROSSCHECK_MODE が off 以外の設置と確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置)では必須、無い・空なら設定エラーで非 0 終了し成果物・管理 DB の行・確報比較依頼を削除しない(置き場の中身も消さない。設定の検査を先に行う)ことを追加。off でも確報クロスチェックを使う設置では確報比較依頼を同じ規則で削除することを追加。管理 DB に接続しない条件を「off で確報クロスチェック worker の設定が無く、接続参照名が無い・空」に絞った。仕様で確定するものに判定方法と設定エラーの終了コードを追加。reason と source_model(NFR F.1.2.1)を追記(CR-9d2e6c41-001)
- system_architecture/tiers/tier-ops/SP-028「ハウスキープの削除順序と回復」: 管理 DB に接続しないのは管理 DB を一切使わない設置だけであること、設定の検査を置き場の残りの削除を含むすべての削除より先に行い、設定エラーなら何も削除せず非 0 で終わることを追記(CR-9d2e6c41-001)
- app_architecture/tier_layers/tier-ops/usecase: responsibility の housekeep のフローの先頭に「ハウスキープ設定の検査(設定エラーなら何も削除せず終了)」を追加し、housekeep の usecase の方針に最初の設定検査と設定エラー時の振る舞いを追記(CR-9d2e6c41-001)
- domain_architecture/bounded_contexts/BC-005: 語「ハウスキープ設定」の接続参照名の説明を、必須の設置(off 以外・確報クロスチェックを使う)と省略できる設置(管理 DB を一切使わない)に分けて書き直した(CR-9d2e6c41-001)
- domain_architecture/bounded_contexts/BC-006: 語「削除待ちの置き場」の「次回の実行で無条件に削除する」に、ハウスキープ設定の検査を通った実行に限り、設定エラーのときは置き場の中身も消さないことを追記(CR-9d2e6c41-001)
- domain_architecture/context_map/CM-013(BC-006 → BC-005): ハウスキープが RAPID_CROSSCHECK_MODE に加えて確報クロスチェック worker 設定の有無を判定に使い、必須の設置で欠けたら設定エラー、接続しないのは管理 DB を一切使わない設置だけであることに改めた。reason と source_model(条件: ハウスキープの削除判定)を追記(CR-9d2e6c41-001)
- data_architecture/entities/E-028 ハウスキープ設定: 属性 db_conn_ref の説明を必須の設置と省略できる設置に分けて書き直した。nullable: true は維持(CR-9d2e6c41-001)

## 削除

- なし(arch-decision-025 は過去の判断の記録として書き換えず、deprecated にもしない。「off では省略できる」の 1 項目を arch-decision-026 で改めた)

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-9d2e6c41-001#1 | changed | SP-027 / SP-028 / tier-ops usecase / BC-005 / BC-006 の語 / CM-013 / E-028、arch-decision-026 |

確認したが変更不要だった箇所: CTR-008(削除の所有と専用ロール)、LP-025 / LP-026(削除の順序とアダプタ)、CM-009〜012、tier-ops repository / gateway(接続参照名で接続する説明のみで省略の前提を含まない)、storage_mapping E-028。
