---
schema_version: distillery.feedback-request/v1
feedback_id: 20260907_abort_consistency
created_at: 2026-09-07T20:00:00+09:00
source: distillery-impl
uc_id: c770d8f0
---

## CR-c770d8f0-016: 中止済み run の判定キーを「並行稼働実行 ABORTED または slot 実行 ABORTED」に改める

- severity: spec-gap
- related_ids: [REQ-005, REQ-010, REQ-011]
- related_files: [docs/rdra/latest/条件.tsv, docs/usdm/latest/requirements.yaml]

### 観測した事実

feedback `20260907_todo_followup` の CR-c770d8f0-014 で条件「中止済み run の比較依頼作成除外」を追加し、「並行稼働実行(parallel_run)が ABORTED の run では速報比較依頼を作成しない」と定めた。しかし状態モデル「並行稼働実行」は foreground slot の結果をジョブスケジューラへ中継した時点で RUNNING → COMPLETED に遷移する。並行稼働の典型構成(blue foreground / green background)では、background slot のハング疑いを運用者が abort-green で中止する時点で parallel_run は既に COMPLETED であり、abort-green は slot 実行を ABORTED にする(aborted.txt を書く)だけで parallel_run は ABORTED にならない。spec の反証レビュー(rdra-feedback #13)がこの抜けを検出し、spec は「parallel_run が ABORTED、または対象 slot の slot 実行が ABORTED(aborted.txt 公開済み)のいずれかなら中止済み」と判定する仮採用を置いた(todo DIST-025)。

### 現在の仕様と問題

RDRA 条件の文言どおりに実装すると、最も典型的な経路(foreground 完了後の background 中止)で「abort したなら速報クロスチェックは実施しない」が成立しない。spec の仮採用と RDRA 条件文が食い違っている。

### 変更してほしいこと

- 条件「中止済み run の比較依頼作成除外」の判定を「並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(成果物ディレクトリに aborted.txt が公開済み)のいずれかに該当する run では、速報比較依頼を作成しない」に改める。判断主体は速報クロスチェック runner(dispatcher)のまま。判定材料は管理 DB の parallel_run.status と slot_executions.status(ファイル正本 aborted.txt のミラー)。
- USDM SPEC-005-02 の受け入れ条件「Given 並行稼働実行が ABORTED When 後から完了通知を受ける Then 速報比較依頼は作成されない」に「Given 並行稼働実行は COMPLETED だが対象 slot の slot 実行が ABORTED When 後から完了通知を受ける Then 速報比較依頼は作成されず、完了事実だけが記録される」を追加する。
- 下流(arch LP-023 / SP-009 の判定条件、spec の rapid-crosscheck-runner 契約の request_creation_matrix と UC spec / BDD)を追従させ、spec の仮採用注記を外す。

### 完了条件

- 条件.tsv の「中止済み run の比較依頼作成除外」が slot 実行 ABORTED も判定キーに含めている。
- USDM に上記の受け入れ条件が存在する。
- spec の rapid-crosscheck-runner 契約から「仮採用」注記が消え、RDRA 条件を参照している。

## CR-c770d8f0-017: 速報比較依頼の中止対象に REQUESTED / CLAIMED を加える

- severity: spec-gap
- related_ids: [REQ-010, REQ-007, REQ-005]
- related_files: [docs/rdra/latest/条件.tsv, docs/rdra/latest/状態.tsv, docs/usdm/latest/requirements.yaml]

### 観測した事実

元の方針資料は abort-rapid-crosscheck.sh について「速報比較依頼が RUNNING でない場合、状態を変更せずエラー終了します」と定め、RDRA 条件「依頼中止可否判定」と USDM SPEC-010-02 もそれに従う。feedback `20260907_todo_followup` の CR-c770d8f0-014 で abort-blue / abort-green が REQUESTED(未着手)の速報比較依頼も ABORTED にするようにしたが、CLAIMED の依頼は対象外のままである。速報クロスチェック依頼のライフサイクルでは CLAIMED の依頼は lease 失効で REQUESTED に戻り、別の worker が再 claim する。したがって中止済み run に CLAIMED の依頼が残っていると、運用者がそれを止める手段が無く、lease 失効後に比較が実行されうる(spec 反証レビュー rdra-feedback #15、todo DIST-026)。

### 現在の仕様と問題

「abort したなら速報クロスチェックは実施しない」を担保するには、運用者が REQUESTED / CLAIMED の速報比較依頼も明示的に中止できる必要がある。現状は RUNNING の依頼しか中止できず、CLAIMED の依頼は運用者の手を離れて再実行される経路が残る。本 CR は元資料の abort-rapid-crosscheck の対象(RUNNING のみ)を広げる変更であり、採用後は元資料側の記述を追記する(利用者作業)。

### 変更してほしいこと

- 条件「依頼中止可否判定」を「速報比較依頼は REQUESTED / CLAIMED / RUNNING のいずれかのとき中止できる。確報比較依頼は従来どおり RUNNING のときだけ中止できる(確報の未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限で扱う)」に改める。
- 状態モデル「クロスチェック依頼」に CLAIMED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」、abort-rapid-crosscheck による。速報比較依頼のみ)を追加し、既存の REQUESTED → ABORTED の遷移 UC に abort-rapid-crosscheck も加える(abort-blue / abort-green による未着手依頼の中止と併存)。
- CLAIMED の依頼を中止する際の競合規則を条件に明記する: abort-rapid-crosscheck は運用者に「worker のプロセスは停止してありますか」と対話確認し yes のときだけ、status IN ('REQUESTED','CLAIMED','RUNNING') の条件付き UPDATE で ABORTED にする。worker は claim 後・比較開始前に依頼が ABORTED になっていれば比較を開始しない(RUNNING への遷移で条件付き UPDATE が 0 件なら終了)。
- USDM SPEC-010-02 の受け入れ条件を「Given 速報比較依頼が REQUESTED または CLAIMED When abort-rapid-crosscheck を実行して yes と答える Then その依頼は ABORTED になり、worker は比較を開始しない」「Given 確報比較依頼が RUNNING でない When abort-final-crosscheck を実行する Then 状態を変更せずエラー終了する」に改める。
- 下流(arch SP-022 / LP-019 / BC-004 の abort 方針、spec の abort-rapid-crosscheck 契約・rapid-crosscheck-worker 契約の claim → RUNNING 条件付き UPDATE・rdb-schema の遷移注記・UC spec / BDD)を追従させる。

### 完了条件

- 条件.tsv の「依頼中止可否判定」が速報比較依頼について REQUESTED / CLAIMED / RUNNING を中止可能としている。
- 状態.tsv の「クロスチェック依頼」に CLAIMED → ABORTED が存在する。
- USDM SPEC-010-02 の受け入れ条件が更新されている。
- spec の abort-rapid-crosscheck 契約が REQUESTED / CLAIMED を受け付け、worker 契約に「RUNNING への条件付き UPDATE が 0 件なら比較を開始しない」がある。

## CR-c770d8f0-018: REQUESTED → ABORTED(abort-blue / abort-green)の説明を競合窓の保険として書き直す

- severity: improvement
- related_ids: [REQ-010, REQ-005]
- related_files: [docs/rdra/latest/状態.tsv]

### 観測した事実

feedback `20260907_todo_followup` の CR-c770d8f0-014 で状態モデル「クロスチェック依頼」に REQUESTED → ABORTED(abort-blue / abort-green による未着手依頼の中止)を追加し、説明を「両 slot 完了直後に中止した場合の抜けを防ぐ」とした。spec の反証レビュー(rdra-feedback #14)は、CR-016 の判定キー拡張により dispatcher 側で中止済み run の依頼作成が抑止されるため、この遷移が実際に効くのは「両 slot の完了通知で依頼が作成された直後から abort-* の実行までの短い競合窓」だけであると指摘した(todo DIST-027)。

### 現在の仕様と問題

説明文が実際の経路と一致していない。遷移自体は競合窓の保険として有用なので残す。

### 変更してほしいこと

- 状態.tsv の REQUESTED → ABORTED(遷移 UC「実行を ABORTED へ遷移させる」)の説明を「両系の完了通知で速報比較依頼が REQUESTED で作成された後に運用者が abort-blue / abort-green で slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定(条件「中止済み run の比較依頼作成除外」)と併用する」に改める。
- 関連する条件・USDM の文言に「両 slot 完了直後の抜けを防ぐ」という表現があれば同様に改める。

### 完了条件

- 状態.tsv の該当行の説明が競合窓の保険として書かれている。
