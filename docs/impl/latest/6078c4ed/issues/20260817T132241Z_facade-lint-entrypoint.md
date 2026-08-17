# facade CLI エントリポイントが公式 lint gate の対象外

## 仕様の記載

`docs/impl/latest/impl-config.yaml` の `tier-facade.commands.lint` は、S4 の公式 lint gate を定義する。

## 実装で判明した事実

現在のコマンドは `find facade -name '*.sh'` であり、拡張子を持たない実行ファイル
`facade/bin/relaygate` を検査しない。そのため S4 でこのファイルの ShellCheck 違反を公式ゲートで検出できない。

## 提案

オーケストレータまたは設定所有者が、`tier-facade.commands.lint` に
`facade/bin/relaygate` を明示的に追加し、tier-facade の公式 lint gate が全 Bash 実装を検査するよう更新する。
