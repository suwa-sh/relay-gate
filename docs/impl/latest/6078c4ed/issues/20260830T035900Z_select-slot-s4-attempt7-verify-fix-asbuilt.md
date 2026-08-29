# S4 attempt-7(tier-facade)verify findings 対応の as-built 記録

- 対象: stages/attempt-6/S5_verify.tier-facade.findings.yaml F-001(blocker)/ F-002(blocker)/ F-003(major)
- F-001 の決定と実装結果は issues/20260830T034746Z_exactly-one-foreground-rule.md に記録済み

## F-002: host / exec_user の契約外正規表現の撤去

### 仕様の記載

- cli-command-contract.yaml job_map_contract: host / exec_user は type=string, required=true。文字種の制約なし

### 実装で判明した事実・実装判断

- `facade/src/job_map_gateway.sh` の host / exec_user の正規表現検証を撤去し、非空文字列のみを要求する
- `facade/src/launch_gateway.sh` の ssh 引数列を `-i<鍵パス> -oBatchMode=yes -oIdentitiesOnly=yes -- <exec_user@host> <remote_command>` に変更した
  - `--` により、先頭が `-` の host / exec_user(例 `-oProxyCommand=...`)が ssh オプションとして解釈されない(配列渡し + クォートは既存どおり)
  - `-i` と鍵パスを 1 引数に結合し、接続先を **引数 5 番目** に保った(facade / features/uc / features/atdd の ssh スタブが `$5` で接続先を判定する)
  - 回帰テスト: `facade/test/6078c4ed_select_slot.bats`「host が先頭ハイフンの場合」「契約外の文字種を含む場合」
- **S6 向け注意**: features/uc・features/atdd の steps は旧引数列 `-n -o BatchMode=yes -- <user@host> <cmd>` の正規表現で起動ログを解析している(attempt-6 時点で既に不一致)。S6 integration writer は新引数列 `-i<key> -oBatchMode=yes -oIdentitiesOnly=yes -- <user@host> <cmd>` に合わせて解析を更新する必要がある

### 残る曖昧さ(文字種制約は実装しない。仕様側で必要なら契約に追加する提案)

- ssh は `user@host` の分解を自身の規則で行う。host に `@` を含む値、host に `:` を含む値(URI 形式・IPv6)は ssh 側の解釈に依存し、本実装は関与しない
- 提案: 実運用で SSH 設定 alias / ディレクトリ由来のユーザー名以外を許容する必要が無ければ、job_map_contract に「host / exec_user は `@` を含まない」程度の制約を追加することを S8 で検討する(現時点では契約外のため実装していない)

## F-003: ローカル deadline 発火の判別チャネル

### 仕様の記載

- tier-facade.md: 送出失敗は FAILED / attempt_failed、送出 timeout だけ UNKNOWN / attempt_unknown。リモートコマンドの終了コード範囲は制限されていない

### 実装判断

- `facade/bin/relaygate` `deadline_run_for`: timeout からの TERM を受けた内側の bash が **マーカーファイル**(`${TMPDIR:-/tmp}/relaygate-deadline.<pid>.<random>`)に `1` を書く。呼び出し後にマーカー内容でグローバル `deadline_fired` を確定する。終了コード 124 は判定に使わない
  - マーカーの生成・読み書きは bash 組み込みのリダイレクトのみ(PATH に mktemp / rm が無い環境でも動く)。削除は EXIT trap で perl `unlink`
  - `deadline_run` が残余なしで即 124 を返す経路も `deadline_fired=1` を立てる
- `launch_gateway.sh`: `deadline_fired=1` のときだけ timeout(UNKNOWN / slot_launch_timeout)。それ以外の非 0(リモートの 124 を含む)は failed(FAILED / slot_launch_failed、reason に `ssh_exit=<code>`)
- `job_map_gateway.sh` / `rdb_gateway.sh` の timeout 判定も同フラグに統一した(挙動は従来と同じ。124 を返す外部コマンドとの衝突を除く)
- 回帰テスト: `facade/test/6078c4ed_select_slot.bats`「リモートコマンドが終了コード 124 を返した場合」(exit 1、FAILED、slot_launch_failed 1 件、slot_launch_timeout 0 件)
