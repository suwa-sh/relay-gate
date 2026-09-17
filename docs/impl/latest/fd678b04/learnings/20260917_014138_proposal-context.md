# CLAUDE.md / dev-rules への追記提案(既存ファイルは編集しない。提案のみ)

## 提案 1(CLAUDE.md「実装は distillery specs に従う」): 自 UC が定義するコマンドの細則は他 UC の tier md にも書かれている

追記案:

> `cli-command-contract.yaml` の各コマンドは `defined_in_uc` と `used_by_ucs` を持つ。自 UC が `defined_in_uc` のコマンドを実装するときは、`used_by_ucs` に列挙された UC の tier md も読む。使う側の tier md が「UC『〜』の契約に以下を追加する」として検証項目や待機上限などの細則を持つ(例: `validate-config.sh --feature-flag` の runner `--help` 待機上限は UC「slot runner の実体スクリプトを割り当てる」の tier-facade.md にある)。

理由: 自 UC の spec / tier md / cross-cutting だけを読んで「仕様に無い」と判断し、別 UC にある値と不一致になった。

## 提案 2(docs/dev-rules/coding-rules.md): bash の値出力と外部プロセス起動の必須規約

追記案:

- 利用者由来の値(設定ファイル・引数・外部コマンドの出力)を stdout / stderr に出すときは `printf` の固定書式を使い、`echo` を使わない(`-n` / `-e` を値として保存するため)
- 出力フォーマット規約(`key=value` / `key: value`)の切替は domain 層の共通関数に閉じ込め、各層で個別に書かない
- gateway 層で外部プロセスを起動する関数は、待機上限・上限到達時の停止手順(独自プロセスグループに TERM → KILL)・準備失敗(一時ファイル作成など)の終了コード(6)を持つ。準備失敗を外部側の未応答と同じ warn に写像しない

理由: attempt-1 の blocker 3 件(F-001 / F-002 / F-028)と attempt-2 の major F-001 がいずれもこの 3 点に帰着した。

## 提案 3(docs/dev-rules/test-strategy.md): 統合テストのハーネス規約を明文化する

追記案:

- Scenario ごとの一時ディレクトリを root とし、仕様の絶対パス(`/etc/relay-gate`、`/opt/relay-gate`)は root 配下の同じ相対位置に置く。出力照合時は root 接頭辞を除去する
- `RELAY_GATE_CONFIG_DIR` は root 配下の `etc/relay-gate` を指す
- runner スタブは `--help` で `runner-if-version=1` を返す実行可能ファイルとして Scenario ごとに作る
- 他 UC の成果物(例: facade.sh)を暫定スタブで代替する場合は、根拠 issue・削除条件・「pass はスタブに対するもの」の注記を done の `injections` に残す
- 外部接続(管理 DB クライアント)を「呼ばれないこと」で検証するときは、sentinel 実行ファイルを PATH 先頭に置く

理由: 本 UC の統合テストと ATDD で同じハーネスを再利用した。次の UC(facade.sh 本体)でも同じ規約が必要になる。
