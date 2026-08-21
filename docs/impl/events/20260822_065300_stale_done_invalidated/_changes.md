# 仕様還流後の stale done を一括退避

input-manifest を現物から再計算した結果、S1〜S9 の全 done の `manifest_sha256` が projection と不一致になった。
全 done と attempt-5 の S5 findings を `invalidated/20260822_065300_stale_done_invalidated/` へ退避し、
同一 attempt(5)内で S1 から順に再実行する(stale 由来のため attempt は進めない)。
