# S5 verify 完了(eff24f55 / tier-facade / attempt 3)— attempt 上限に到達

- attempt 2 の blocker(NUL バイトの黙殺)は解消を確認
- 新しい blocker 3 件:
  - ジョブマップの値やファイルパスに含まれる制御文字(ESC シーケンス・改行)がそのまま出力され、ANSI 禁止と「1 行 1 事実」の出力契約に違反する(対象は先行 UC と共有する表示用の共通関数)
  - プロセス置換内の補助コマンド(sort / tr / sed)が失敗しても検知せず、重複 job_id や NUL 行を成功扱いにする(意図的な障害注入で立証)
  - UTF-8 として不正なバイト列を受理する(前提 A-031 が「形式は UTF-8」の設定契約と矛盾)
- major 1 件(credential_ref の前提。仕様に定義なし)、minor 28 件
- 前提 verdict: consistent 2 / spec_absent 25 / contradicts 1 / unlisted 1(ヘッダーのみ 0 行の受理境界)
- attempt 上限 3 に到達したため自動続行せず、ユーザー判断(続行 / 仕様ブロック / 手動介入)を仰ぐ
