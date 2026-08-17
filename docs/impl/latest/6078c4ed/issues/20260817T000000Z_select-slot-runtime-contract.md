# select-slot 実行境界の契約不足

## 仕様の記載

- `tier-facade.md` は `RELAYGATE_JOB_MAP_PATH` によりジョブマップを解決し、`RELAYGATE_RDB_DSN` の RDB へ記録したうえで SSH 経由で slot を起動すると定めている。
- ただし、ジョブマップのファイル形式・必須フィールド、DSN が指す RDB 種別と接続クライアント、SSH の接続先・認証方法・リモート起動コマンドは定義していない。
- 同文書は blue/green の両 slot を起動する一方、`execution_specs.impl_version` は単数であり、どちらの実装版を保存するかも定義していない。

## 実装で判明した事実

これらの境界契約がないと、本番で相互運用可能なジョブマップ解決、RDB 書込み、SSH 起動を決定できない。任意の形式や接続方式を実装側で固定すると仕様の創作になる。

## 提案

CLI/ジョブマップ/RDB/SSH の契約に、ジョブマップ JSON Schema、RDB 製品・DSN 形式・ドライバ、SSH 認証とリモート実行の引数規約、blue/green 両方を起動する際の `impl_version` 保存規則を追加する。S4 の検証では、契約確定までの限定的なテスト・ローカル実行境界として JSON ジョブマップ、SQLite DSN、PATH 上の `ssh` を用いる。
