# S4 tier-impl 完了(eff24f55 / tier-facade / attempt 2)

- blocker 3 件を解消した: JSON 文字列内の未エスケープ制御文字を拒否 / verbose の fixed_params を必ず 1 行の JSON で出力 / 版の集計を全行の distinct 値(空も 1 値)へ変更
- major: job_id 重複検査を sort と隣接比較へ変更し、repository の配列スライスも添字アクセスへ変更(2000 行で約 14 秒 → 約 1 秒)
- major: credential_ref の形式不一致を警告のみで受理する判断は、仕様に照合先が無いため前提として維持(S9 の確認対象)
- 前提は 23 件 → 17 件(仕様の復唱 8 件を除外、探索方式と重複 job_id の出力順を追加)
- 再発防止の bats を先に追加(RED 確認後に修正)。bats 168 件、tier BDD 23 Scenario が pass
- 申し送り: 対象 bash の版が dev-rules / 仕様 / impl-config に定義されていない(版に依存しない構文で実装)
