# select-slot 実行境界の契約不足

## 仕様の記載

- `tier-facade.md` は `RELAYGATE_JOB_MAP_PATH` によりジョブマップを解決し、`RELAYGATE_RDB_DSN` の RDB へ記録したうえで SSH 経由で slot を起動すると定めている。
- ただし、ジョブマップのファイル形式・必須フィールド、DSN が指す RDB 種別と接続クライアント、SSH の接続先・認証方法・リモート起動コマンドは定義していない。
- 同文書は blue/green の両 slot を起動する一方、`execution_specs.impl_version` は単数であり、どちらの実装版を保存するかも定義していない。

## 実装で判明した事実

これらの境界契約がないと、本番で相互運用可能なジョブマップ解決、RDB 書込み、SSH 起動を決定できない。任意の形式や接続方式を実装側で固定すると仕様の創作になる。

## 提案

CLI/ジョブマップ/RDB/SSH の契約に、ジョブマップ JSON Schema、RDB 製品・DSN 形式・ドライバ、SSH 認証とリモート実行の引数規約、blue/green 両方を起動する際の `impl_version` 保存規則を追加する。S4 の検証では、契約確定までの限定的なテスト・ローカル実行境界として JSON ジョブマップ、SQLite DSN、PATH 上の `ssh` を用いる。

## attempt 3 の as-built 判断

- `execution-spec.json` は `RELAYGATE_EXECUTION_SPEC_DIR` を指定した場合はその配下、未指定の場合は解決済みの `work_dir` 配下の `{run_id}/execution-spec.json` に保存する。一時ファイルを同じディレクトリに作成し、権限を `0600` にしてから rename する。
- SSH 起動では `RELAYGATE_RUN_ID` と `RELAYGATE_EXECUTION_SPEC_PATH` をリモート環境へ渡す。後者は facade と runner がこのパスを共有していることを仮定する。共有ストレージ種別・配置・所有者は未定義である。
- 実装は既存の SQLite 限定 DSN と `sqlite3` CLI を継続して用いる。正式な RDB gateway/driver が確定するまで、他の DSN は受理しない。
- `runner_results` の主キーが `(run_id, role_type)` で slot を含まず、同一 run の両 background 起動試行を個別レコードとして保存できない。また SSH timeout 後にリモート実行が継続したかを判定する handshake 契約もない。このため attempt 3 では foreground の事前 `RUNNING` レコードを execution spec と同一トランザクションにし、SSH 失敗を `FAILED` と補償記録する範囲に留める。background の一貫した起動試行状態と timeout 後の確定状態は、主キーと remote handshake の仕様化後に S8 feedback で解決する。
