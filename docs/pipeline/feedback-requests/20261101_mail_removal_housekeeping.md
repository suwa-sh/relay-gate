---
schema_version: distillery.feedback-request/v1
feedback_id: 20261101_mail_removal_housekeeping
created_at: 2026-11-01T12:00:00+09:00
source: distillery-impl
uc_id: e4ea8aaa
---

# 利用者からの変更要求(メール送信の削除・ハウスキープ・設定値の空白)

## CR-e4ea8aaa-001: メール送信をやめ、ハング検知の異常はハング検知ジョブ自身の終了結果で知らせる

- severity: spec-gap
- related_ids: [REQ-008, SPEC-008-03, SPEC-008-06, REQ-012, SPEC-012-01]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/外部システム.tsv, docs/rdra/latest/情報.tsv, docs/rdra/latest/BUC.tsv, docs/rdra/latest/条件.tsv, docs/rdra/latest/アクター.tsv, docs/nfr/latest/nfr-grade.yaml, docs/arch/latest/arch-design.yaml, docs/infra/latest/infra-event.yaml, docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-mail/tasks/main.yml, docs/infra/latest/infra/product/onprem/ansible/site.yml, docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md]

### 観測した事実

- 利用者は、メール送信機能を実装しないと決めた(2026-11-01)。メール送信のコードはまだ無い。ハング検知の UC は未実装である。
- 要求 REQ-012 は「運用者への提示は CLI の標準出力・標準エラー・終了コードと通知メールで行う」と書く。SPEC-012-01 は「ハング検知の通知は warning / error のメール送信で行う」と書く。
- SPEC-008-06 は、ハング検知定期ジョブ設定に通知先メールアドレス・送信コマンド・件名プレフィックスを定義させる(ALERT_MAIL_TO / ALERT_MAIL_CMD / ALERT_SUBJECT_PREFIX)。SPEC-008-03 は「運用者へ通知する」と書く。
- RDRA は外部システム「メール通知」、情報「通知メール」、情報「ハング検知定期ジョブ設定」のメール 3 項目、UC「background 異常の通知メールを受け取る」、条件「CLI とメールによる提示」を持つ。アクター「運用者」の説明も通知メールで異常を受け取ると書く。
- インフラ設計にメール送信用の構築ロール(relay-gate-mail)がある。アーキテクチャ設計・NFR・仕様にもメール通知を前提にした記述がある。仕様の出力規約(ui-design.md)は通知メール規約と送信の冪等規則を持つ。CLI 契約の hang-detector.sh は、異常を検出しても終了コード 0 で終わり、異常はメールで伝えると定める。
- CLI 契約は、同じ異常のメールを 1 回だけ送る判定を管理 DB の監視記録(monitor_records.monitor_status の遷移)で行う。RAPID_CROSSCHECK_MODE=off では監視記録を保存できず、判定結果は実行ログにだけ残す。
- 元の方針資料(しくみ)は、ハング検知が「通知する」とだけ書き、手段を決めていない。利用イメージはメールでの通知と、メールから経過時間を見る運用を書いている。利用イメージは利用者の承認のうえで同じ方向に書き換える。

### 現在の仕様と問題

- 実装しないメール送信が、要求から仕様までの正本に残っている。このままでは、ハング検知の実装時にメール送信を作ることになる。
- メールを消すだけでは、ジョブスケジューラの実行結果に現れない background 異常を運用者が知る経路が無くなる。代わりの経路を仕様に定める必要がある。

### 変更してほしいこと

- ハング検知は、見回り・判定・監視記録の保存を今のまま続ける。自動中止・自動再実行をしない点も変えない。
- ハング検知は、新たに見つけた background 異常をハング検知ジョブ自身の終了結果で知らせる。運用者には、ジョブスケジューラの既存のジョブ監視・障害通知で届く。
  - 異常が無ければ終了コード 0 で終わる。
  - 注意(ハング疑い)は警告終了、異常(background 実行エラー・速報クロスチェック異常)は失敗として、終了コードで区別する。警告終了の値は、確報の比較 NG と同じ考え方(ジョブステータスが警告終了になる値)とする。具体的な値は CLI 契約で確定する。
  - 見つけた異常は、標準エラーに 1 件 1 行で出す。行には対象(run_id と role、または速報比較依頼)、段階(warning / error)、経過時間を含める。
  - 通知済みの異常は、次回以降の見回りで再び知らせない。これは今のメール通知を 1 回だけ送る扱いと同じである。判定は今の監視記録の遷移規則を使う。
  - RAPID_CROSSCHECK_MODE=off では監視記録の代わりに、ハング検知が成果物ルート配下へ通知済みの印をファイルで残し、同じ規則で判定する。印は Runner Result の契約ファイル(stdout.log / stderr.log / exitcode.txt / execution-spec.json / started-at.txt / aborted.txt)とは別のファイルにし、一時ファイル → リネームで書く。置き場所とファイル名は仕様で確定する。
  - 通知の判定が終わったあとで監視記録または印の保存に失敗した場合は、その異常を次回も知らせる(知らせ漏れより重複を選ぶ)。
- 経過時間の傾向の確認は、メールではなく、ハング検知ジョブの出力と監視記録で行う。
- 次のものを正本から消す。
  - ハング検知定期ジョブ設定のメール 3 項目(通知先メールアドレス・送信コマンド・件名プレフィックス)。管理 DB 接続参照名は残す。
  - RDRA の外部システム「メール通知」と情報「通知メール」。UC「background 異常の通知メールを受け取る」は「ハング検知ジョブの異常終了を確認する」の趣旨に置き換える。条件「CLI とメールによる提示」は「CLI による提示」に改める。
  - インフラ設計のメール送信用の構築ロール、それを呼び出す Ansible の起動口(site.yml)の参照、インフラ実装の正本(product-impl-onprem.yaml)のメール中継の定義と、メール送信の前提(送信コマンドの配置・中継先)。
  - 仕様の出力規約(ui-design.md)の通知メール規約と送信の冪等規則。CLI 契約の hang-detector.sh のメール設定の検証と、メール送信失敗を理由とする終了コードの記述。
- 要求 REQ-012 / SPEC-012-01 の「通知メール」を外し、提示を CLI の標準出力・標準エラー・終了コードだけにする。SPEC-008-03 の「運用者へ通知する」は、ハング検知ジョブの終了結果で知らせることを明記する。

### 完了条件

- USDM・RDRA・NFR・アーキテクチャ・インフラ・仕様のどこにも、メール送信・通知メール・メール設定項目・メール用構築ロールが無い。
- ハング検知の仕様が、異常なし・注意・異常の終了コードと、標準エラーの 1 件 1 行の出力を定めている。
- 通知済みの異常を再び知らせない規則が、管理 DB を使う設定と RAPID_CROSSCHECK_MODE=off の両方について、受け入れ基準として判定できる(同じ異常で 2 回目の見回りは終了コード 0 になる)。
- `rg -i 'メール|mail|smtp' docs/{usdm,rdra,nfr,arch,infra,specs}/latest` の結果が、変更履歴の説明(_changes.md・decisions の経緯)を除いて 0 件になる。
- 監視記録の保存・自動中止しない・自動再実行しない規則は変わっていない。

## CR-e4ea8aaa-002: 成果物と管理 DB の履歴を、保持日数を過ぎたら削除するハウスキープを追加する

- severity: spec-gap
- related_ids: [REQ-008, REQ-012]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/BUC.tsv, docs/rdra/latest/情報.tsv, docs/nfr/latest/nfr-grade.yaml, docs/arch/latest/arch-design.yaml, docs/infra/latest/infra-event.yaml, docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml, docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-postgresql/tasks/main.yml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- 実行ごとに成果物ディレクトリ(stdout.log / stderr.log / exitcode.txt / execution-spec.json / started-at.txt、中止時は aborted.txt)が作られる。
- RAPID_CROSSCHECK_MODE が off 以外のときは、管理 DB に並行稼働実行(parallel_runs)・slot 実行(slot_executions)・速報実行(rapid_runs)・速報比較依頼(rapid_crosscheck_requests)・監視記録(monitor_records)の行も増える。off では管理 DB に書かず、成果物だけが残る。
- 速報比較依頼だけのリラン(background-rerun.sh --role rapid-crosscheck)は、execution-spec.json と成果物ディレクトリを持たない新しい run を作る。この run は管理 DB の行だけを持ち、さらにリラン元にもなる。
- 確報比較依頼(final_crosscheck_requests)は実行(run_id)にひも付かない独立したテーブルで、依頼ごとに completed_at を持つ。
- 管理 DB の業務用接続ロール(app_rw)の権限は SELECT / INSERT / UPDATE で、DELETE を持たない(インフラ実装の正本と PostgreSQL 構築ロール)。
- 状態の終端値はテーブルごとに異なる。並行稼働実行は COMPLETED / ABORTED で、COMPLETED は foreground の結果を中継し終えた時点を表す。background slot と速報比較依頼は、その後も実行中のことがある。
- 要求・仕様には、成果物と管理 DB の履歴を消す機能が無い。アーキテクチャ設計は「保持期間超過分の削除は手動手順で行う」としている。
- 元の方針資料には保持期間の記述が無い。
- 利用者は、ハウスキープの設定を持たせ、経過日数で履歴を自動で削除したい。既定の保持日数は 90 日とする(2026-11-01)。

### 現在の仕様と問題

- 履歴が増え続け、ファイル領域と管理 DB の容量を圧迫する。手作業での削除は、消してよいものの判断(終了済みか、リランの親子か)を運用者に負わせる。

### 変更してほしいこと

- ハウスキープ専用のスクリプト(housekeep.sh)を追加する。ジョブスケジューラの定期ジョブとして 1 日 1 回起動する想定とする。業務ジョブの起動時には削除しない。
- 保持日数を設定で持つ。既定は 90 日。値は正の整数とし、設定検証で検査する。削除したくない場合は定期ジョブを登録しない。
- 削除の単位は次の 2 種類とする。
  - 実行の単位: リランの親子(parent_run_id でつながる実行)をまとめた 1 単位。単位内の各実行の成果物ディレクトリ、管理 DB の行(parallel_runs / slot_executions / rapid_runs / rapid_crosscheck_requests / monitor_records)、ハング検知が残した通知済みの印を一緒に消す。
  - 確報比較依頼の単位: 確報比較依頼 1 件。
- 実行の単位を消す条件は、単位内のすべての構成要素が終端していること。構成要素は、並行稼働実行、各 slot、速報比較依頼である。
  - 管理 DB を使う設定では、parallel_runs が COMPLETED / ABORTED、すべての slot_executions が SUCCEEDED / FAILED / ABORTED、すべての rapid_crosscheck_requests が SUCCEEDED / FAILED / ABORTED であること。
  - RAPID_CROSSCHECK_MODE=off で管理 DB の行が無い実行は、成果物だけで判定する。execution-spec.json で起動対象になっている slot(mode が off の slot は含まない)のすべてで、成果物ディレクトリに exitcode.txt または aborted.txt があること。起動対象の slot の成果物ディレクトリが無い場合や、execution-spec.json が無い実行は、終わっていないものとして残し、標準エラーに warn を出す。
  - 速報比較依頼だけのリランで作られた run は、成果物を持たないため管理 DB の行だけで判定する。
  - 1 つでも終わっていない構成要素(RUNNING、CLAIMED、REQUESTED、slot の終了ファイルが無い)があれば、経過日数にかかわらず単位ごと残す。
- 経過日数の基準は、単位内の構成要素の終了日時のうち最も遅いものとする。管理 DB の行は completed_at、成果物だけの slot は exitcode.txt または aborted.txt の更新時刻を使う。開始日時は使わない。
- 確報比較依頼は、終端状態(SUCCEEDED / FAILED / ABORTED)で、completed_at から保持日数を過ぎたものを消す。
- 削除の順序と途中失敗からの回復は次のとおりとする(何度実行しても結果が同じ)。
  - 1 つの単位の中では、成果物(ディレクトリと通知済みの印)を先に処理し、そのあと管理 DB の行を 1 つのトランザクションで消す。
  - 成果物は、削除対象と判定したら、まず成果物ルート配下の削除待ちの置き場へ rename で移す(同じファイルシステム内で 1 回の操作)。そのあと置き場から削除する。置き場に残っているものは、判定をやり直さず次回の実行で無条件に削除する。置き場の場所は仕様で確定する。
  - 管理 DB の行が残っている間は、次回の走査で同じ単位を再び見つける。既に無いファイルは削除済みとして扱い、続けて管理 DB の行を消す。
  - 成果物ルートの走査は、管理 DB の有無にかかわらず毎回行う。管理 DB の行が無い成果物ディレクトリは、成果物だけの判定規則で扱う。
  - ファイルを消してから管理 DB の行を消すまでの間に、期限切れの実行をリランしようとした場合は、リランは元の execution-spec.json が無いことをエラーとして返す(既存のリランの規則のまま)。
- 削除した件数を標準出力に出し、失敗は標準エラーに出して非 0 で終わる。
- 管理 DB の行の削除には、ハウスキープ専用の DB ロールを使う。権限は対象テーブル(parallel_runs / slot_executions / rapid_runs / rapid_crosscheck_requests / final_crosscheck_requests / monitor_records)の SELECT と DELETE だけとし、業務用接続ロール(app_rw)には DELETE を足さない。接続はハング検知と同じく接続参照名で解決し、値を設定に置かない。インフラ実装の正本と PostgreSQL 構築ロールに、このロールの作成と権限付与を加える。
- 設定のファイル名・キー名・終了コード・どの管理 DB に接続するかは、仕様(CLI 契約・設定契約)で確定する。

### 完了条件

- 要求にハウスキープの要求があり、受け入れ基準で次を判定できる。
  - 保持日数を過ぎた終了済みの実行が、成果物・管理 DB の行・通知済みの印ともに消える
  - 保持日数内の実行は残る
  - foreground の中継は終わったが background slot または速報比較依頼が終わっていない実行は、日数にかかわらず残る
  - RAPID_CROSSCHECK_MODE=off の成果物だけの実行も、同じ規則で消える・残る
  - リランの親子は、全員が期限を過ぎるまで残る
  - 確報比較依頼は、依頼ごとに completed_at で判定される
  - 削除した件数が標準出力に出る。削除に失敗すると標準エラーに出て非 0 で終わり、次回の実行で残りが消える(成果物を削除待ちの置き場へ移したあとの失敗、管理 DB の行の削除の失敗の両方)
  - 速報比較依頼だけのリランで作られた run も、同じ単位の規則で消える・残る
- ハウスキープ専用の DB ロールが、インフラ実装の正本と PostgreSQL 構築ロールにあり、業務用接続ロールに DELETE が付いていない。
- 保持日数の既定 90 日と、正の整数の検査が仕様にある。
- アーキテクチャ設計の「保持期間超過分の削除は手動」の記述が、ハウスキープの自動削除に改められている。

## CR-e4ea8aaa-003: env 形式の設定値の、前後の空白と = の前後の空白の扱いを定める

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- CLI 契約の env 形式の入力規則(config_input_rules.env_files)は、値の先頭末尾の引用符の外し方を定めている(先頭と末尾を別々に 1 文字ずつ外す)。値の前後の空白と、= の前後の空白の扱いは書いていない。
- 実装の 2 か所(feature flag 設定の読み込みと、速報クロスチェック設定の読み込み)は、どちらも次の順で処理する: 行を最初の `=` で分ける → キーの前後の空白を除く → 値の前後の空白を除く → 値の先頭・末尾の引用符を外す。空白は bash の [:space:](半角空白・タブ・CR を含む)である。
- 2 か所は行の扱いが違う。feature flag 設定は行全体の前後の空白を先に除き、`=` の無い行をキーだけの行として扱う。速報クロスチェック設定は `=` の無い行を形式違反にする。
- 前回の仕様の更新(2026-11-01)で、仕様の段階がこの隙間を確認推奨として報告した。利用者は、別の変更要求として扱うことに同意した。

### 現在の仕様と問題

- `KEY= "abc" ` のような値で、仕様の字面と実装の結果が変わる。別の設定ファイルの読み込みを実装する人ごとに、空白の扱いが分かれうる。

### 変更してほしいこと

- config_input_rules.env_files に、今の実装と同じ次の順序の規則を、引用符の外し方と同じ節に書く。
  1. 行を最初の `=` で、キーと値に分ける(値の中の `=` はそのまま値に残る)
  2. キーの前後の空白を除く
  3. 値の前後の空白を除く
  4. 値の先頭の 1 文字が `"` か `'` なら外し、それとは別に末尾の 1 文字が `"` か `'` なら外す(引用符の内側の空白は残す)
  - 空白は半角空白とタブとする。CR は、env 形式に適用済みの既存のバイト検査(CR の拒否)で拒否する規則のまま変えない
- 例を添える: `KEY= "abc" ` → キー KEY・値 abc / ` KEY = 'a b' ` → キー KEY・値 `a b` / `KEY="  a  "` → 値 `  a  ` / `KEY=a=b` → 値 `a=b`。
- `=` の無い行とコメント行の扱いは、各設定契約の今の規則のまま変えない(この要求の対象外)。
- compare_command_argv.split の再掲にも同じ規則を反映する。

### 完了条件

- env 形式の入力規則が、空白の除き方と引用符の外し方を 1 つの順序つき規則として書いている。
- 前後に空白を含む値の結果が、規則から推測なしに 1 つに決まる。
- 今の実装が、変更後の記述どおりに動いている(違う場合は差分を記録する)。
