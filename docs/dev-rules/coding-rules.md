# コーディング規約 正本(distillery-impl)

実装先リポの `CLAUDE.md` に bootstrap が抜粋を埋め込み、Verifier の合否判定にも使う。
テストの階層・命名・AAA は `test-strategy.md` が正本(ここでは重複させない)。

## 必須(Verifier が reject する違反)

1. **契約型の直接編集禁止**: `packages/contracts/` 配下(契約宣言 contracts[] からの生成物)を手で書き換えない。
   契約に不足があれば仕様への変更要求(issues/)を起票する。生成物の再生成は S0/S3 のみ
2. **frontend の UI コンポーネントは `packages/ui/` のみ使用**: 新規コンポーネントの自作は禁止。
   不足は design(dist-design-system)への変更要求を経由する(詳細は `tier-rules.md`)
3. **formatter / linter を通過する**: コマンドは実装リポの `impl-config.yaml` の `commands` が正。
   tier 並走中(S4)は **check-only モード**で実行し、書き換えを伴う format はオーケストレータが barrier 後に実行する
4. **仕様を実装側で曲げない**: 仕様(spec.md / tier-*.md / 契約)と実装が矛盾したら、実装を仕様に合わせるか、
   仕様の問題として issues/ に書き捨てる。「動くように仕様と違うことをする」を禁止する
5. **Conventional Commits**: コミットはオーケストレータのみが行い、
   `impl({uc_id}): S4 tier-backend-api gates passed` 形式(scope に uc_id)で刻む

## 推奨(Verifier が指摘する品質基準)

- ドメインロジックの実装判断は ddd plugin の `ddd:ddd-tactical-implementation` の基準に従う
  (値オブジェクト化 / 集約境界 / 貧血モデル回避。未インストール環境ではこの節と tier-rules.md を基準にする)
- 関数・クラスは仕様の用語(RDRA の情報・状態・条件の名前)をそのまま使う。訳語・別名を発明しない
- エラーは「利用者が直せる言葉」で返す(tier-*.md のエラー表に従う)
- マジックナンバー・重複ロジックは仕様側の計算ルール・条件への参照コメントを付けて定数化する
