# bootstrap 再実行(仕様還流後)の完了

feedback 還流で spec / arch / usdm / design / storybook src / rdb-schema のハッシュが変わったため、
P2〜P7 を invalidate して再実行した。

- P2: 導出結果は既存と一致(scope は 20260822_064510 で確定済み)。書き換えなし
- P4: `packages/contracts/relay-gate-db/schema-constants.sh` を 11 テーブルで再生成。lock 更新
- P5: `packages/ui/` を storybook-app/src(59 ファイル)から再取り込み。内容変更 12 件
- P7: `features/atdd/` を 42 SPEC / 56 Scenario で再生成(追加 15、削除 0、文言変更 2)
- P3 / P6: 差分なし。`docs/dev-rules/test-strategy.md` はリポ側ローカル改訂(uc_slug 命名)を維持
