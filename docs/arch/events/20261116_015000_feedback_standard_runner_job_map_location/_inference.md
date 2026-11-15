# 推論根拠サマリ

## 標準の slot runner の正式な提供(CR-65b09d93-001、causal)

- 根拠: 前段の要求仕様の変更(SPEC-001-04 / SPEC-013-01)、RDRA の情報「slot runner 割当」「feature flag 設定」「適用構成文書」と条件「実装固有事項の runner への閉じ込め」、アクター「基盤適用設計者」の説明更新
- 判定: latest は slot runner を「適用ごとに割り当てる実体スクリプト」とだけ書き、relay-gate が runner を提供するかどうかを定めていなかった。提供物の範囲が変わるため、構成要素として明記した(changed)
- 置き場所: 標準の slot runner は、既存の「facade / slot runner ティア」の構成要素とした。ティアもコンテキストも増やさない
- facade との関係: facade は設定された runner を起動するだけで、標準の slot runner か自作の runner かを区別しない。runner を差し替えて世代交代できる構造は変わらない
- 語の追加: 適用構成コンテキストに語「標準の slot runner」を足した。RDRA の情報「slot runner 割当」の説明に対応する語で、RDRA に無い要素の追加ではない
- 方針資料との関係: しくみの資料は標準の runner の提供に触れていない。方針資料に明記の無い利用者決定(2026-11-16)として、SR-002 の reason と arch-decision-027 に書いた
- 変更しない: Runner Result Contract、完了通知の系統独立、実装固有事項を runner に閉じ込める原則、共通ライブラリと runner の外部 IF

## feature flag の任意 2 キーとジョブマップの場所(CR-65b09d93-002、causal)

- 根拠: 前段の要求仕様の変更(SPEC-001-01 / SPEC-004-01)、RDRA の情報「feature flag 設定」「ジョブマップ」「slot runner 割当」、条件「設定所有区分」「ジョブマップ解決条件」、バリエーション「設定所有区分」の説明更新
- 判定: latest は feature flag を「9 キー」と書く箇所が 7 か所あり(語、ティアの説明、SP-001、SP-025、domain 層、repository 層、storage_mapping)、ジョブマップの所在を指定する手段を持たなかった。「9 キー + 任意の 2 キー」に揃えた(changed)
- 所有: slot ジョブマップの場所の所有者は feature flag。設定所有区分の語と SP-025 に加えた
- 解決規則の置き場所: 場所の解決規則(無い・空なら固定の名前、相対パスの基準)は副作用の無い判定のため、tier-facade の domain 層に置いた。読み書きは repository 層
- 読み手の一致: 解決した後の場所を、検証コマンド・slot runner・運用系のコマンドが同じく使うことを SP-006 に書いた。slot runner は feature flag の設定ファイルを読まない契約のままとし、渡す方法は仕様で確定する
- nullable: 任意のキーのため、E-001 の 2 属性は nullable: true。E-002 の job_map_location は、解決した後の場所が必ず 1 つ決まるため nullable: false のまま
- 方針資料との関係: しくみの資料の 9 キーの設定例はそのまま通る。利用イメージの資料の設定例に寄せた利用者決定(2026-11-16)
- 仕様で確定するもの: キー名(推奨は BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)、相対パスの解決規則の詳細(runner / worker の 4 キーと同じ)、解決した後の場所を runner へ渡す方法

## 非機能要求

- 前段の非機能要求は変更なし。NFR の網羅に影響する方針・規則の追加と削除は無い
