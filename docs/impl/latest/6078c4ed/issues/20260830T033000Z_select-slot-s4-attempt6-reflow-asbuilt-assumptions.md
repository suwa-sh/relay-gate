# select-slot S4 attempt-6(還流後再実行)の実装判断と仮置き

S4 tier-impl(tier-facade、attempt-6 の stale 再実行。spec 20260829_210828_spec_generation / CR-6078c4ed-011〜018 反映後)で、
仕様・契約に定義が無く実装側で仮置きした項目と、仕様の記載と両立させるために選んだ判断を列挙する。
いずれも blocker ではない(4 ゲートは GREEN)。S5 の反証・S8 の feedback request で仕様側へ確定を求める。

## 1. 仮置き(契約に定義が無い共有規則)

| # | 項目 | 仕様の記載 | 実装で判明した事実 / 仮置き | 提案 |
|---|---|---|---|---|
| 1.1 | 監査 outbox の置き場所・形式 | audit-event-contract.yaml failure_contract.post_launch「ローカル永続 outbox へ退避し再試行対象として永続化する」。パス・形式・再試行主体は未定義 | `facade/src/rdb_gateway.sh` `audit_outbox_dir` / `write_audit_outbox` に 1 箇所へ集約。ディレクトリは `RELAYGATE_AUDIT_OUTBOX_DIR`、未設定時は `${XDG_STATE_HOME:-$HOME/.local/state}/relaygate/audit-outbox`。ファイルは冪等キーごとに `{run_id}_{slot}_{attempt_id}_{event_name}.json`(13 項目のうち previous_hash / event_hash を除く。再試行時に lock_contract で確定するため)。一時ファイル → rename。再試行ジョブは本 UC の範囲外で未実装 | cli-command-contract.yaml に outbox の環境変数・配置・ファイル形式・再試行コマンド(または worker の責務)を定義する |
| 1.2 | 秘密鍵の ssh への渡し方 | credential_resolution「解決したファイルを秘密鍵とする」のみ | `ssh -i <鍵パス> -oBatchMode=yes -oIdentitiesOnly=yes <exec_user>@<host> <remote_command>`(`facade/src/launch_gateway.sh`)。鍵の実値は読まない。S6 / S7 の「秘密鍵として送出される」step は起動ログの `-i <パス>` 出現で観測する(issues/20260829T172256Z §2.4) | 契約に「`-i` + `IdentitiesOnly=yes`」を明記するか、渡し方は実装判断のままとするかを確定 |
| 1.3 | RELAYGATE_CREDENTIAL_DIR 未設定の扱い | tier-facade.md 環境変数表で必須 Yes。exit_codes 表には未設定時の分類が無い | presentation 層で他の環境変数と同様にバリデーションエラー(exit 2、「RELAYGATE_CREDENTIAL_DIR is required」)。credential_ref が null の slot しか無くても必須 | exit_codes 2 の説明に環境変数欠落を追記する |
| 1.4 | 秘密鍵パーミッション検査 | 「所有者のみ読み取り可能(0600)。検査失敗は業務エラー」 | group / other のビットが立っていなければ許容(0600 / 0400)。失敗は exit 1「SSH認証情報を解決できません: credential_ref={ref} (permission must be 0600)」。パスは出力しない | 0400 を許容するかを確定 |

## 2. 仕様と両立させるための実装判断(仕様変更は不要だが S5 で参照)

| # | 項目 | 判断 |
|---|---|---|
| 2.1 | slot_launch_failed / slot_launch_timeout のチェーン位置 | run_id 単位の線形チェーンのため、previous_hash は追記時点の head(起動前 transaction で最後に追記した slot_launch_attempted)。spec.md 異常系「slot_launch_attempted の後ろにチェーンされて」と整合するが、**同 slot の** slot_launch_attempted の直後にはならない(green が失敗しても直前は blue の attempted)。S2 の bats はこの前提で同 slot を要求していたため、S4 で「slot_launch_attempted の後ろ + チェーン先頭になる」へ改めた。S6 の step も同 slot を要求しないこと |
| 2.2 | lock_contract の実現(起動後の監査追記) | psql -c 単一リクエストではロック取得後にクライアント側でハッシュ計算できないため、`SELECT head_hash`(平文)→ event_hash 算出 → `BEGIN; SELECT ... FOR UPDATE; INSERT ... WHERE EXISTS(head_hash 一致); UPDATE ... WHERE head_hash 一致; COMMIT;` → 追記行数を確認、の CAS 方式。head が動いていれば再計算して最大 3 回再試行、それでも追記できなければ outbox(`append_post_launch_audit`) |
| 2.3 | 補償記録と CLI deadline | SSH 待機は「seam 上限(8 秒)」と「deadline 残余 − 予約 2 秒」の小さい方。予約は補償記録(transaction 1 + 監査追記)の時間。deadline を使い切った後の補償記録は `deadline_grace=1` により固定 2 秒の猶予で必ず試みる(`facade/bin/relaygate` deadline_run)。この猶予分だけ 10 秒の契約を最大 2 秒超過しうる(送出 timeout 時のみ) |
| 2.4 | SSH 待機の残余が無い slot | 起動イベントを送出せず FAILED(reason=deadline_exhausted)として補償記録する(送出していないことが確定しているため UNKNOWN ではない)。終了コード 1 |
| 2.5 | イベント時刻の単調増加 | datetime_rules.ordering_guarantee に従い、起動前 transaction のイベント(attempt_started × slot 数 + slot_launch_accepted + slot_launch_attempted × slot 数)は 1 回の perl 呼び出し内でイベントごとに時計を読み、同値なら取り直す(`clock_times_utc`)。補償記録のイベントも直前より後の時刻を保証(`next_event_time`) |
| 2.6 | ジョブマップ読み込みの deadline 超過 | job_map_contract の validation 表に無い「ファイル可読性確認が deadline を超えた」場合は exit 124(「ジョブマップを読み込めません: ... reason=timeout」)。契約の 3 種(未設定 / 読めない / 欠落)とは区別する |
| 2.7 | JOB_ID 未解決の判定順 | 起動対象 slot を起動順(background → foreground、同役割は blue → green)に検証し、最初の失敗で終了する。ある slot で必須フィールド欠落(exit 2)、別 slot で JOB_ID 未解決(exit 1)が同時に起きた場合は先に検証した slot の結果になる |
| 2.8 | 起動イベントのリモートコマンド | argv(fixed_args + additional_args)はリモートシェルへ渡すため `%q` でクォートするが、保存形式は JSON 配列で、要素の再分割・再結合はしない(argument_serialization.prohibited は保存形式についての禁止と解釈) |

## 3. テスト整理

- `facade/test/6078c4ed_select_slot.bats`(旧契約前提 39 件)は新契約へ移行し 48 件にした。deadline / 子プロセス掃除 / 入力検証 / canonical_form / SQL 生成 / 時刻の単調増加 / outbox を担う。新 bats(17 件)と重複する主経路のテストは削除した
- 通常実行の所要時間は約 1.2 秒(deadline_run の timeout + setsid のプロセス生成コスト。ジョブマップ抽出は slot ごと jq 1 回、時刻はまとめて perl 1 回に削減済み)

## 4. write-set 外の追随が必要な点

- `features/uc/steps` / `features/atdd/steps` の ssh スタブは接続先を `$5` で判定している。本実装の ssh 引数列(`-i <鍵> -oBatchMode=yes -oIdentitiesOnly=yes <user@host> <cmd>`)は `$5` が接続先になるよう合わせてある。引数を増やす場合はスタブの追随が必要
