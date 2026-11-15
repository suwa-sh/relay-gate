# 変更サマリ

- event_id: 20261116_015000_feedback_standard_runner_job_map_location
- trigger_event: usdm:20261116_013000_feedback_standard_runner_job_map_location, rdra:20261116_013000_feedback_standard_runner_job_map_location, nfr:20261116_014000_feedback_standard_runner_job_map_location
- created_at: 2026-11-16T01:50:00Z
- mode: 差分更新(arch-design-diff.yaml。変更セクション: domain_architecture(bounded_contexts / context_map)/ system_architecture(tiers)/ app_architecture(tier_layers)/ data_architecture(entities / storage_mapping))
- dialogue_policy: interactive(確認推奨項目は完了報告で返却)
- feedback request: 20261116_standard_runner_job_map_location(direct work unit: なし。causal work unit: CR-65b09d93-001#1(relay-gate が標準の slot runner を正式に提供する)、CR-65b09d93-002#1(slot ジョブマップの場所を feature flag に書けるようにし、書かなければ固定の名前を使う)。packet: docs/pipeline/feedback-runs/20261116_standard_runner_job_map_location/stage-packets/architecture.md)

マージ規則: bounded_contexts / context_map / tiers は `id`、tier_layers は `tier_id`、entities は `id`(名前も同一)、storage_mapping は `entity_id` で照合して diff の要素で置き換えた(diff の要素は latest の当該要素と同一の内容)。meta(event_id / created_at / source)を本イベントの値へ更新した。`confidence: "user"` の要素は変更していない。

方針資料との照合:

- しくみの資料の feature flag の設定例は 9 キー。足す 2 キーは任意で、9 キーだけの設定はそのまま通るため矛盾しない。
- 利用イメージの資料の設定例は、feature flag にジョブマップの場所を相対パスで書く。足す 2 キーはこの設定例に寄せた利用者決定(2026-11-16)。
- しくみの資料は「BLUE_RUNNER と GREEN_RUNNER は適用ごとに実体を割り当てる」と書き、標準の runner の提供には触れていない。標準の slot runner の正式な提供は方針資料に明記の無い利用者決定(2026-11-16)として書いた。割り当てる実体として標準の slot runner を選べる形で両立する。

## 追加

- decisions: arch-decision-027(標準の slot runner を正式な構成要素として持つ。feature flag は 9 キー + slot ジョブマップの場所を書く任意の 2 キー)(CR-65b09d93-001、CR-65b09d93-002)
- domain_architecture/bounded_contexts/BC-005: 語「標準の slot runner」を追加(RDRA の情報「slot runner 割当」の説明に対応する語。新しい RDRA 要素ではない)(CR-65b09d93-001)
- data_architecture/entities/E-001 feature flag 設定: 属性 blue_job_map_location / green_job_map_location(任意。nullable: true)と、ジョブマップへの関連を追加(CR-65b09d93-002)

## 変更

### 標準の slot runner の正式な提供(CR-65b09d93-001)

- system_architecture/tiers/tier-facade: description に、slot runner には標準の slot runner か自作の runner を割り当てること、標準の slot runner がローカル実行と SSH 実行を扱うことを追加
- system_architecture/tiers/tier-facade/SR-002「実装固有事項の runner への閉じ込め」: 標準の slot runner を本ティアの正式な構成要素(提供物)として置くこと、扱う範囲、利用者が用意するもの、特殊な接続は自作の runner に閉じ込めること、共通ライブラリと runner の外部 IF を残すこと、参考実装としては扱わないこと、ファイル構成は仕様で確定することを追加。reason に利用者決定と方針資料との関係を追記
- system_architecture/tiers/tier-facade/SP-001: facade は、割り当てられた runner が標準の slot runner か自作の runner かを区別しないことを追記
- system_architecture/tiers/tier-facade/SP-006: 標準の slot runner が host と user が両方空の行をローカル実行、それ以外を SSH 実行として扱うことを追記
- app_architecture/tier_layers/tier-facade/presentation: responsibility の「blue-runner / green-runner」を、標準の slot runner(blue と green の両方に割り当てる。ファイル構成は仕様で確定)に直した
- domain_architecture/bounded_contexts/BC-005: 語「feature flag」に、BLUE_RUNNER / GREEN_RUNNER へ割り当てる実体(標準の slot runner か自作の runner)を追記
- domain_architecture/context_map/CM-001: reason に、標準の slot runner でも自作の runner でも同じであることを追記
- data_architecture/entities/E-001: blue_runner / green_runner の説明に、標準の slot runner か自作の runner であることを追記
- data_architecture/entities/E-002 slot runner 割当: runner_script_path の説明に同じ区別を追記
- data_architecture/entities/E-005 適用構成文書: runner_location の説明を、標準の slot runner の割り当て、または自作した runner の所在に直した
- data_architecture/storage_mapping/E-002: 割り当てる実体が標準の slot runner か自作の runner のスクリプトファイルであることを追記

### feature flag の任意 2 キーとジョブマップの場所(CR-65b09d93-002)

- domain_architecture/bounded_contexts/BC-005: 語「feature flag」を「9 キー + 任意の 2 キー」に直し、9 キーだけの設定がそのまま通ることと未知のキーの範囲を追記。語「ジョブマップ」に場所の決まり方(任意のキー、無い・空なら固定の名前、相対パスの基準、検証コマンドと実行時の読み手が同じジョブマップを選ぶ)を追記。語「設定所有区分」に、ジョブマップの場所を feature flag が所有することを追記
- domain_architecture/context_map/CM-001: translator_description に、ジョブマップの場所も feature flag の任意のキーに従うことを追記
- system_architecture/tiers/tier-facade: description の「feature flag(9 キー)」を「9 キー + 任意の 2 キー」に直し、ジョブマップの場所の決まり方を追記
- system_architecture/tiers/tier-facade/SP-001: 9 キーに任意の 2 キーを加えた構成、未知のキーの範囲、9 キーだけの設定がそのまま通ることを追記
- system_architecture/tiers/tier-facade/SP-006: ジョブマップの場所の決まり方、相対パスの基準、解決した後の場所をすべての読み手が同じく使うこと、slot runner は feature flag の設定ファイルを読まない契約のままであること、ジョブマップ単体の検証コマンドは変えないことを追加。reason と source_model(条件: 設定所有区分、情報: feature flag 設定)を追記
- system_architecture/tiers/tier-datastore/SP-025「設定所有区分に基づく設定ファイル配置」: feature flag が所有する項目にジョブマップの場所(任意の 2 キー)を加え、「env 形式 9 キー」を「9 キー + 任意の 2 キー」に直した。reason に利用者決定を追記
- app_architecture/tier_layers/tier-facade/domain: 「feature flag 9 キーの検証」を「9 キーと任意の 2 キーの検証」に直し、ジョブマップの場所の解決規則を追加
- app_architecture/tier_layers/tier-facade/repository: feature flag を「9 キー + 任意の 2 キー」に直し、ジョブマップの場所の解決を追記
- data_architecture/entities/E-002: job_map_location の説明に、feature flag の任意のキーで指定し、無い・空なら固定の名前であることを追記
- data_architecture/storage_mapping/E-001: 9 キーに任意の 2 キーを加えた構成に直した
- data_architecture/storage_mapping/E-002: ジョブマップの所在も feature flag の任意のキーとして所有されることを追記
- data_architecture/storage_mapping/E-003: 置き場所を feature flag の任意のキーで指定でき、無い・空なら固定の名前を使うことを追記

## 削除

- なし

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-65b09d93-001#1 | changed | tier-facade の description / SP-001 / SP-006 / SR-002、tier-facade の presentation、BC-005 の語、CM-001、E-001 / E-002 / E-005、storage_mapping E-002、arch-decision-027 |
| CR-65b09d93-002#1 | changed | BC-005 の語、CM-001、tier-facade の description / SP-001 / SP-006、tier-datastore の SP-025、tier-facade の domain / repository、E-001 / E-002、storage_mapping E-001 / E-002 / E-003、arch-decision-027 |

確認したが変更不要だった箇所: technology_context(方針資料の構成と設定所有区分を維持する制約のまま)、tier-datastore の description(設定ファイルの種類の列挙のみ)、CTR-007(設定検証を facade 単独で完結させる構成。キーの数を書いていない)、tier-facade の gateway(host / user 省略時のローカル実行を既に持つ)、AG-005(ジョブマップの行の不変条件のみ)、E-003 の属性(列構成は変わらない)、tier-rapid-crosscheck / tier-final-crosscheck / tier-ops(feature flag のキーの数と runner の提供元に触れていない)。
