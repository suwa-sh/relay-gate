# select-slot のリモート確定・RDB・監査境界の契約不足

## 仕様の記載

- `tier-facade.md` は execution-spec.json を一度だけ確定して SSH 経由で slot を起動し、CLI 応答を 10 秒以内と定める。
- `rdb-schema.yaml` は execution_specs、runner_results、audit_logs を定義する。

## 実装で判明した事実

- SSH の受理・開始・冪等な再送確認の handshake、共有 execution-spec の配布方式、timeout 後の remote 実行状態を確定する契約がない。
- RDB の製品、接続ドライバ、ロック待機・トランザクション timeout の契約がない。
- 監査ログの event schema、出力先、保持・相関規則が定義されていない。CLI stdout は起動結果の契約であるため、ここへ独自の構造化監査イベントを追加できない。

## 提案

remote launch request/acknowledgement と run_id を使う状態遷移、execution-spec 配布責務、RDB gateway の timeout/lock 契約、監査イベントの JSON Schema と出力先を cross-cutting 契約として定義する。確定後に timeout 時の UNKNOWN/STARTING を含む回復処理と監査出力を実装する。

## attempt 4 の限定実装

- JSON job map、SQLite、PATH 上の ssh は既存のローカル検証境界に限定する。
- facade は monotonic deadline から残余時間を全外部 I/O に渡し、DB/SSH の主処理には補償用時間を予約する。
- execution-spec.json と SSH 環境へ blue_mode、green_mode、rapid_crosscheck_mode を同じ確定値として渡すが、これは handshake や共有ストレージを確定するものではない。
