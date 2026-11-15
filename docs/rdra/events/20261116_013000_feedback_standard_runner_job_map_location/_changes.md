# 変更サマリ

- event_id: 20261116_013000_feedback_standard_runner_job_map_location
- 元USDM: docs/usdm/events/20261116_013000_feedback_standard_runner_job_map_location/requirements.yaml
- 生成日時: 2026-11-16T01:30:00
- feedback request: 20261116_standard_runner_job_map_location(direct / causal work unit: CR-65b09d93-001#1、CR-65b09d93-002#1。packet: docs/pipeline/feedback-runs/20261116_standard_runner_job_map_location/stage-packets/requirements.md)

```yaml
feedback_request:
  feedback_request_id: "20261116_standard_runner_job_map_location"
  input_sha256: "733163f9092ac7055b410880c40f85fd312b2684f25fb0fb20d8d3412626822a"
  request_ids: ["CR-65b09d93-001","CR-65b09d93-002"]
  work_unit_ids: ["CR-65b09d93-001#1","CR-65b09d93-002#1"]
```

マージ規則の補足:

- 情報.tsv / アクター.tsv はマージキー(どちらも 2 列目)で該当行をイベント側の内容に置き換える。
- 条件.tsv / バリエーション.tsv はコンテキスト(1 列目)+名前(2 列目)のキーで該当行をイベント側の内容に置き換える。
- BUC.tsv は 業務(1 列目)+BUC(2 列目)+UC(6 列目)のグループを、イベント側の全行で置き換える(1 UC = 複数関連行のため、関連行の集合単位の置換)。関連行の増減は無く、変えたのは各グループ先頭行の説明だけ。

本イベントは、次の 2 つの要求(どちらも利用者が 2026-11-16 に決定)を、既存要素の属性と説明へ反映する。新しい要素は追加しない。

1. relay-gate が、そのまま feature flag の BLUE_RUNNER / GREEN_RUNNER に割り当てられる標準の slot runner(ローカル実行と SSH 実行)を正式に提供する(CR-65b09d93-001。USDM SPEC-001-04 / SPEC-013-01)。
2. feature flag に、slot ジョブマップの場所を書く任意のキーを blue 用と green 用に 1 つずつ足し、書かなければこれまでの固定の名前を使う(CR-65b09d93-002。USDM SPEC-001-01 / SPEC-004-01)。

方針資料との照合:

- tmp/RelayGateのしくみ.md の feature flag の設定例は 9 キーで、ジョブマップの場所の行は無い。足す 2 キーは任意で、9 キーだけの設定はそのまま通るため、設定例と矛盾しない。
- tmp/RelayGateの利用イメージ.md の設定例は、feature flag にジョブマップの場所を相対パスで書く行(適用側が決めたキー名)を持つ。足す 2 キーはこの設定例に寄せた利用者決定で、キー名は slot の名前(BLUE / GREEN)に合わせて仕様で確定する。
- tmp/RelayGateのしくみ.md は「BLUE_RUNNER と GREEN_RUNNER は適用ごとに実体を割り当てる」と書き、標準の runner の提供には触れていない。標準の slot runner の正式な提供は方針資料に明記の無い利用者決定で、割り当てる実体として標準の slot runner を選べる形で両立させる。利用イメージの資料が示す、案件固有の接続のために適用側が runner を用意する例は、自作の runner を割り当てる道としてそのまま残る。

## 追加

- なし

## 変更

- 情報: feature flag 設定 → 属性に slot ジョブマップの場所(任意の 2 キー。キー名は仕様で確定、推奨は BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)を加え、BLUE_RUNNER / GREEN_RUNNER の実体が標準の slot runner か自作の runner であることを加える。関連情報にジョブマップを加える。説明の「設定契約どおり 9 キーで構成」を「9 キーに任意の 2 キーを加えて構成」に直し、無い・空のときの固定の名前、絶対パスと相対パスの受け付け、相対パスの基準、9 キーだけの設定がそのまま通ること、未知のキーの範囲を加える(CR-65b09d93-002、CR-65b09d93-001)
- 情報: slot runner 割当 → 属性の runner 実体スクリプトパスに標準の slot runner と自作の runner の別を、ジョブマップの所在に feature flag の任意のキーでの指定を加える。説明に、標準の slot runner の正式な提供、扱う範囲(ローカル実行と SSH 実行)、利用者が用意するもの、自作の道が残ること、ファイル構成は仕様で確定すること、方針資料との関係を加える(CR-65b09d93-001、CR-65b09d93-002)
- 情報: ジョブマップ → 関連情報に feature flag 設定を加え、説明に、場所を feature flag の任意のキーで指定できること、無い・空なら固定の名前を使うこと、検証コマンドと実行時の読み手が同じジョブマップを選ぶことを加える(CR-65b09d93-002)
- 情報: 適用構成文書 → 説明の「runner の差し替え」を、標準の slot runner の割り当て、または自作した runner への差し替えに直す(CR-65b09d93-001)
- 条件: 実装固有事項の runner への閉じ込め → 標準の slot runner の正式な提供と、標準の slot runner が扱わない起動方式・プロトコルは自作の runner に閉じ込めることを加える(CR-65b09d93-001)
- 条件: 設定所有区分 → feature flag が所有する項目に slot ジョブマップの場所(任意のキー)を加える(CR-65b09d93-002)
- 条件: ジョブマップ解決条件 → ジョブマップの場所の決まり方(feature flag の任意のキー、無い・空なら固定の名前)と、標準の slot runner がローカル実行の行と SSH 実行の行を解決することを加える(CR-65b09d93-002、CR-65b09d93-001)
- バリエーション: 設定所有区分 → 説明の feature flag が所有する項目に slot ジョブマップの場所(任意のキー)を加える(CR-65b09d93-002)
- アクター: 基盤適用設計者 → 役割の runner 実体スクリプトを、標準の slot runner の割り当て、または自作する runner に直し、slot ジョブマップの場所を feature flag に書けることを加える(CR-65b09d93-001、CR-65b09d93-002)
- BUC: 適用構成定義フロー → UC「feature flag を設定する」の説明に slot ジョブマップの場所を書く任意の 2 キーを、UC「slot runner の実体スクリプトを割り当てる」の説明に標準の slot runner の割り当てと自作の runner の割り当ての使い分けを、UC「slot ごとのジョブマップを定義する」の説明にジョブマップの場所の指定を加える(CR-65b09d93-002、CR-65b09d93-001)

## 削除

- なし
