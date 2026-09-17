# 自 UC が定義するコマンドの規則が、別 UC の tier md に「追加」されていることがある

## 何が起きたか

`validate-config.sh --feature-flag` の runner `--help` 問い合わせについて、実装者は「待機上限は仕様に無い」として NFR から逆算した 4 秒を前提(A-022)に置いた。独立した検証も同じ箇所を spec_absent と判定した。しかし UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md には「`--help` の呼び出しは 5 秒でタイムアウト(仮採用)」があった。実装と検証の双方がこの記述を参照しなかった。

## 原因

- CLI 契約は validate-config.sh を「UC『feature flag を設定する』が定義し、5 つの UC が使う(used_by_ucs)」と記述している。使う側の UC の tier md が「UC『feature flag を設定する』の契約に以下を追加する」として検証項目と細則を書いている
- 実装時に読む仕様の集合(自 UC の spec.md / tier md / cross-cutting)に、used_by_ucs の tier md が含まれていなかった。前提の抽出も検証も、その集合の中だけで「仕様に無い」と判断した
- 仮採用 5 秒 × 2 slot 逐次 = 10 秒は NFR B.2.1.1(10 秒以内)と両立しないため、仮に読んでいても値の確定には仕様側の判断が必要だった

## 回避方法

- 自 UC が定義するコマンドについて、CLI 契約の `used_by_ucs` に列挙された UC の tier md を全部開き、「〜の契約に以下を追加する」節を抽出してから前提を置く
- spec_absent と判断する前に、`docs/specs/latest` 全体を対象に対象語(例: `--help`、タイムアウト、秒)で横断検索する
- 見つかった値が NFR と両立しない場合は、実装で調整せず仕様側へ変更要求を出す(CR-fd678b04-002)

## 次回の対応

- UC 着手時の共有仕様参照集合(shared_spec_refs)に、CLI 契約の `used_by_ucs` に載る UC の tier md を含める
- AssumptionRecord の `reason` に「横断検索した語と範囲」を書き、検証者が同じ検索を再現できるようにする
