# S5 verify 完了(eff24f55 / tier-facade / attempt 4)— 仕様の確認待ちの経路へ切り替え

- 3 回目の blocker 3 件(制御文字の出力 / 補助コマンド故障の見逃し / 不正 UTF-8 の受理)は解消を確認
- 新しい blocker 1 件: 事前のバイト点検と CSV 読み込みがファイルを別々に開くため、その間に同じ行数のファイルへ差し替えると、NUL を含む job_id を正常値として受理する(差し替えタイミングを注入して立証)
- major 1 件(credential_ref の前提。仕様に定義なし)、minor 34 件。前提 verdict は consistent 2 / spec_absent 32
- 同種(異常な入力・異常な環境)の新規 blocker のため、ユーザーの取り決めに従い S4 へ差し戻さない。issue を起票し、blocker を残したまま統合テスト → feedback → レビューへ進む
