# 単一 deadline と process group cleanup を組み合わせる

## 何が起きたか

各 SSH 呼出しの個別 timeout では複数 slot と前後の I/O を合計した CLI 応答時間を制限できず、timeout した親の子プロセスが残留することもあった。

## 原因

期限を操作単位ではなく外部呼出し単位で管理し、timeout が直接の子プロセスだけを終了していたためである。

## 回避方法

CLI 開始時に monotonic な単一 deadline を確定し、すべての blocking I/O に残余時間を渡す。外部コマンドは専用 process group で起動し、timeout 時に group 全体を終了する。

## 次回の対応

複数外部 I/O の累積時間、通常の子、TERM を無視する子の残留を実時間テストする。
