---
schema_version: distillery.feedback-request/v1
feedback_id: 20261115_runner_relative_path
created_at: 2026-11-15T16:30:00+09:00
source: distillery-impl
uc_id: c5a81e37
---

# 利用者からの変更要求(feature flag の実体パスに相対パスを受け付ける)

## CR-c5a81e37-001: feature flag の runner / worker の実体パスに相対パスを受け付け、基準を設定ファイルのあるディレクトリにする

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-01, SPEC-005-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md, docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md]

### 観測した事実

- 元の方針資料は、feature flag の設定例を 2 か所に示し、どちらも実体パスを相対パスで書いている。
  - しくみの資料: `BLUE_RUNNER=./blue-runner.sh` / `GREEN_RUNNER=./green-runner.sh` / `RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh` / `RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh`
  - 利用イメージの資料: `BLUE_RUNNER=./legacy-runner.sh` / `GREEN_RUNNER=./beam-runner.sh` / `RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh` / `RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh`
- 現在の仕様は、この 4 キーを絶対パス必須とし、相対パスを `error: path is not absolute key=<KEY> path=<v>`(終了コード 2)で拒否する。方針資料の設定例は、現在の仕様では検証を通らない。
- この規則は 2026-08-30 の仕様の初回生成時に足されたもので、要求(USDM)・方針資料・判断記録のどこにも理由の記載が無い。USDM に 4 キーの絶対パスの受け入れ基準は無い。
- 同じ種類の規則(slot ジョブマップの work_dir と script の絶対パス検査)は、2026-09-22 の利用者決定でやめた。そのときの判断記録は「feature flag の runner パスの絶対パス検査は変えない」とだけ書き、理由を書いていない。
- 利用者は 2026-11-15 に、この規則の理由を確認したうえで次のとおり決定した: 「相対パスを受け付ける。基準は設定ファイルのあるディレクトリとし、仕様に明記する」。
- 設定検証を手元で試すサンプルをリポジトリに置こうとしたとき、絶対パス必須のために、置いたままのファイルでは通らず、展開先のパスを埋め込む生成の手順が要った(決定のきっかけ)。

### 現在の仕様と問題

- 方針資料の設定例が検証を通らない(仕様が方針資料から離れている)。
- 相対パスを受け付けるだけでは、どこを基準に実体を探すかが決まらない。ジョブスケジューラから起動されるときの作業ディレクトリは決まっていないため、作業ディレクトリを基準にすると、起動する場所で指す先が変わる。

### 変更してほしいこと

1. feature-flag.env の `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER` の 4 キーは、絶対パスと相対パスのどちらも受け付ける。`error: path is not absolute` は、この 4 キーでは出さない。
2. 相対パス(`/` で始まらない値)の基準は、その feature-flag.env があるディレクトリとする。プロセスの作業ディレクトリは基準にしない。`./runner.sh`、`runner.sh`、`../runners/runner.sh` のどの書き方も同じ基準で解決する。`~` や環境変数の展開はしない(値は文字のまま扱う)。
3. 解決した後の扱いを 1 つに定める。
   - 存在・実行権限の検査、runner への `--help` の問い合わせ、runner の起動、slot runner へ環境変数で渡す速報クロスチェック runner の値は、どれも解決後のパスで行う。
   - 検証結果の表示(`validate-config.sh --feature-flag` の stdout の `blue_runner:` などの行)と、実行不可の error 行の `path=` に、設定に書いた値と解決後のパスのどちらを出すかを決める。推奨は解決後の絶対パス(実際に使われる実体が読み手に分かるため)。
   - 設定ファイルのパスが相対パスで渡されたとき、シンボリックリンクのときの基準の決め方も定める。
4. 検証コマンドと、同じ設定を読む実行時の読み手(ジョブを起動するコマンドなど、feature-flag.env を読むすべての処理)に同じ規則を適用する。4 キーを扱う各機能の仕様(feature flag を設定する / slot runner の実体スクリプトを割り当てる / slot 実行モードを選択して runner を起動する、ほか 4 キーの絶対パスに触れている箇所)と CLI 契約を揃える。
5. 相対パスの設定が通ることと、基準が作業ディレクトリではなく設定ファイルのあるディレクトリであることを判定できる BDD シナリオを、該当する機能に追加する。相対パスを拒否する既存のシナリオは、新しい規則に合わせて置き換える。
6. この要求の範囲は feature-flag.env の 4 キーだけとする。速報・確報の比較ツール起動コマンドのコマンド部分の絶対パス検査(2026-10 の利用者決定。USDM に受け入れ基準がある。方針資料に相対パスの例は無い)は変えない。
7. 現在の実装(4 キーの相対パスを拒否する)が新しい契約と違うことを、実装との差分として仕様の判断記録に残す。

### 完了条件

- 方針資料の 2 つの設定例の 4 キーの書き方(`./blue-runner.sh` など)が、実体が設定ファイルと同じディレクトリにあれば検証を通ることが、仕様から読み取れる。
- 相対パスの基準(設定ファイルのあるディレクトリ)と、解決後のパスの使い方・表示が、CLI 契約から 1 つに決まる。
- 検証コマンドと実行時の読み手で、同じ設定から同じ実体が選ばれる。
- 相対パスの設定を判定する BDD シナリオが該当する機能にあり、4 キーの相対パスを拒否するシナリオが残っていない。
- 比較ツール起動コマンドの絶対パス検査は変わっていない。
