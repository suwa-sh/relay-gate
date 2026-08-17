# 実行境界の仕様コンテキストへの提案

## 何が起きたか

ジョブマップ、RDB、SSH、execution-spec 配布、監査の境界値が個別 UC に散在し、一意な実装値を得られなかった。

## 原因

cross-cutting 文書は CLI、RDB、監査の一部を扱うが、remote launch の通信と状態、共有ファイルの責務、timeout 後の回復をまとめた正本がなかった。

## 回避方法

仕様コンテキストに、実行境界の共通契約として job map schema、RDB gateway、remote handshake、共有 artifact、監査 event を関連付けた参照を置く。

## 次回の対応

仕様所有者は、CR-001 と CR-002 の処理時に関連 UC が参照できる cross-cutting 契約の置き場とトレーサビリティを決める。
