# S4 tier-impl 完了(eff24f55 / tier-facade / attempt 3)

- blocker を解消した: NUL バイトを含む行を bash へ取り込む前に検出し、契約にある既存の行 `error: csv quote is invalid line=N` と終了コード 2 で拒否する
- バイトレベル入力の自己点検を実施し、実ファイルのテストで挙動を確定した(最終行の改行なし / CRLF / BOM / 不正な UTF-8 / 引用符内の改行 / 空ファイル / 長い行 など)。仕様に定めの無い挙動は前提として記録した
- job_id などの正規表現をロケール非依存(LC_ALL=C)に固定した
- 長い行の解析が行長の 2 乗時間だったため走査方式を変更した(10 万文字の行で約 100 秒 → 0.2 秒)
- 前提は 17 件 → 28 件。bats 219 件、tier BDD 23 Scenario が pass
- major(credential_ref の形式不一致を警告のみで受理)は仕様に定義が無いため前提として維持
