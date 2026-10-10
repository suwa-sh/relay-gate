# tier BDD「compare_options にプレースホルダが無い」の Given と Then の値が一致しない(S4 tier-impl 起票)

- uc_id: dcd8234d(クロスチェックのジョブマップと比較定義を定義する / define-crosscheck-job-map-and-comparison-definitions)
- 起票 stage: S4 tier-impl(tier-rapid-crosscheck、attempt 1)
- 種別: 仕様どおりに実装すると tier BDD Scenario が成立しない事実(実装の blocker ではない。step 定義側で代替した)

## 仕様の記載

`tier-rapid-crosscheck.md`「ティア完了条件(BDD)」:

```gherkin
  Scenario: compare_options にプレースホルダが無い
    Given JOB001 行の compare_options が `--fast` である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る
```

検証ルール #7 の違反メッセージは `error: compare_options is missing {blue} or {green} line=N job_id=... value=...` で、`value=` には行の compare_options の値を出す(契約 validate-config.sh の stderr「行の値不正」の共通形式。任意入力は元の値をそのまま出す)。

## 実装で判明した事実

- Given のとおり compare_options を `--fast` にすると、実装の出力は `value=--fast` になり、Then の `value=--blue {blue}` と一致しない
- Then のとおり `value=--blue {blue}` を出すには、Given の compare_options が `--blue {blue}`(`{green}` だけが欠けた値)でなければならない
- feature は転写規約(意訳・修正の禁止)で spec と同文であり、実装を仕様に合わせても両立しない。どちらの値も「プレースホルダが欠けた compare_options」としてルール #7 の違反になる点は同じ

## S4 での扱い

- 実装は仕様のルール #7 どおり(`value=` に元の値)とし、曲げていない
- step 定義(`rapid-crosscheck/features/steps/define-crosscheck-job-map-and-comparison-definitions.steps.js`)の Given は、Then の期待値と整合する `--blue {blue}` を書き込む(`{green}` 欠落)。本 issue のパスを step のコメントに残した
- TDD(bats)では `--fast` の入力に対して `value=--fast` が出ることを別に確認している

## 提案

- S8(feedback): Given を「JOB001 行の compare_options が `--blue {blue}` である(`{green}` が無い)」に直すか、Then を `value=--fast` に直す。どちらかに揃えば step 定義の代替は不要になる
