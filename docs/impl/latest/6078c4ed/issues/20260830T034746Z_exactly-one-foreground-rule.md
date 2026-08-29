# feature flag の組み合わせ規則: foreground はちょうど 1 件(ユーザー決定 2026-08-30)

## 決定

- 決定者: ユーザー(attempt-7 続行判断時。回答 `attempt7=A` + 追加指示)
- 内容: `BLUE_MODE` / `GREEN_MODE` の組み合わせは **foreground がちょうど 1 件** であることを入力検証で要求する。
  - 両 foreground: 拒否(既存 SR-001)
  - 両 background: **拒否(新規)**
  - 両 off: **拒否(新規。verify F-001 の未処理例外を契約化した検証エラーに置き換える)**
  - foreground 1 件 + background / off: 許可

## 現行仕様との矛盾(feedback で仕様側を更新する)

- spec.md:216 の Scenario「BLUE_MODE=background, GREEN_MODE=background の場合は両ジョブマップの hang_detect_limit_minutes の大きい方を採用する」は両 background を有効とみなしている
- spec.md:144 / tier-facade.md:109 / cli-command-contract.yaml hang_detect_limit_minutes_rule の「両 slot が background なら大きい方」は到達不能になる
- spec.md:125,134 は off を値域に含めるが、両 off の扱いは未記載(F-001)

## 実装側の扱い(意図的逸脱。S8 で変更要求化)

- 入力検証エラー(終了コード 2、stderr に原因と次アクション)として実装し、回帰テストを追加する
- S2 が転写した両 background の Scenario(tier / UC BDD、bats)は期待値を検証エラーに変更する(spec 更新後に転写を再同期)
- 監査・DB 書き込みは行わない(検証は transaction 前)

## 関連

- verify findings: stages/attempt-6/S5_verify.tier-facade.findings.yaml F-001
- review: tmp/reviews/attempt-7-decision-review.html
