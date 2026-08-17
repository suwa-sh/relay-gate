# 拡張子なし Bash を lint 対象から漏らさない

## 何が起きたか

`facade/bin/relaygate` は Bash の実行ファイルだが `.sh` 拡張子を持たず、`find facade -name '*.sh'` を使う公式 lint gate では検査されなかった。

## 原因

言語判定をファイル名の拡張子だけに依存しており、shebang と実行権限を持つ CLI entrypoint を対象集合へ含めていなかった。

## 回避方法

lint command では entrypoint を明示的に列挙するか、shebang を検査して Bash ファイルを収集する。対象集合を変更したら、意図的な ShellCheck 違反を含む fixture で gate が失敗することを確認する。

## 次回の対応

bootstrap 時に、各 tier の実行可能ファイルと lint 対象の差分を検査する。設定の所有者が公式 command を更新し、通常の CI gate で確認する。
