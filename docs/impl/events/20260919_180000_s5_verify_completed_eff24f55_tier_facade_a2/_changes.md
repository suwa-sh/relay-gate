# S5 verify 完了(eff24f55 / tier-facade / attempt 2)

- attempt 1 の blocker 3 件は解消を確認
- 新しい blocker 1 件: CSV に NUL バイト(0x00)があると `read -r` が黙って落とし、不正な fixed_params を終了コード 0 で受理する(固定引数の内容も変わる)
- major 1 件: credential_ref の形式不一致を警告のみで受理する前提(仕様に定義なし。S9 の確認対象)
- minor 16 件。前提 verdict は spec_absent 17(contradicts / unlisted は 0)
- write-set 逸脱なし(done / findings のみ)
