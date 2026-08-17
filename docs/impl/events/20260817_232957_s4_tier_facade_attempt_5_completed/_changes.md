# Complete S4 tier-facade attempt 5

単一deadlineをCLI最初の実行境界へ移し、初期化、契約読込、job-map可読性判定を期限内に収めた。
timeout対象を専用session/process groupで実行して通常子とTERM無視子を消去し、SSH直前に残余時間を再計算した。
追加5件を含むTDD 22件とtier BDDを通過した。
