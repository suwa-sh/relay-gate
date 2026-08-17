# UC英名とGit delivery境界を確定

対象UCの推奨英名を「Select and launch slots based on feature flags」とし、feature branchを
`feature/select-and-launch-slots-by-feature-flags`に確定した。

旧runの開始HEAD、`origin/main`、merge-baseが同じcommitであることを照合し、このcommitを
最終squashの親として固定した。
