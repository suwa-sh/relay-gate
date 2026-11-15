# relay-gate オンプレミス IaC スケルトン

`docs/mcl/product/output/product-impl-onprem.yaml` に対応する IaC スケルトン(未検証の雛形)。
仮想化基盤(vSphere / OpenStack / 物理サーバ)は適用側の設置環境に固定しないため、
Terraform はホスト・ネットワークセグメントの**論理定義のみ**を variables として持つプレースホルダとし、
実際のプロビジョニングは Ansible ロールで OS・ミドルウェア構成を行う 2 層構成とする。

## 構成

```
infra/product/onprem/
  terraform/     # ホスト・ネットワークセグメントの論理定義(プレースホルダ variables)
  ansible/       # OS・ミドルウェア構成(systemd / PostgreSQL / 設定配置 / バックアップ)
```

## 適用順序

1. `terraform/` で対象環境(vSphere/OpenStack/物理)向けの provider ブロックを具体化し、
   実行ホストセグメント・DBセグメントのホストを用意する(このスケルトンでは未確定)
2. `ansible/` の各ロールを対象ホストグループに適用する
3. ジョブスケジューラにハング検知定期ジョブ(5 分ごと)とハウスキープ定期ジョブ(1 日 1 回)を登録する
   (IaC の対象外。運用手順書に従う。hang-detector の警告終了・失敗が障害通知で運用者へ届く唯一の通知経路)

## 前提

- エアーギャップ環境のためインターネット経由のパッケージ取得は行わない(オフラインリポジトリ/ローカルミラーを利用)
- 全ホスト(確報 worker が動く DB セグメントを含む)がこの構築手順で同じようにデプロイされていることを前提にする。relay-gate の処理の中から設定ファイルは配らないため、比較コマンドなど設定を変えたら構築手順で配り直す
- 標準の slot runner(ローカル実行と SSH 実行)は relay-gate の提供物(2026-11-16 利用者決定)
  - facade と同じ実行ホストに、構築手順で facade と一緒に配置する。DB ホストには置かない
  - `BLUE_RUNNER` / `GREEN_RUNNER` には、標準の slot runner か、利用者が自作した runner を割り当てる。特殊な接続(標準が扱わない起動方式)だけ、利用者が runner を自作して同じ実行ホストに置く
  - SSH は既存の実行ユーザーごとの鍵と `known_hosts` を使う。新しいミドルウェアや接続経路は増えない。ファイル構成は仕様で確定
- slot ジョブマップの置き場所は、feature flag の任意の 2 キー(blue 用と green 用。キー名は仕様で確定)で変えられる
  - キーが無い・空なら、設定ファイル置き場の固定の名前(`/etc/relay-gate/<role>-job-map.csv`)を使う。9 キーだけの既存の設定はそのまま動く
  - 絶対パスと相対パスを受け付け、相対パスの基準は `feature-flag.env` のあるディレクトリ
  - 別の場所を指定する設置では、指定先へジョブマップを配る(構成管理リポジトリが正本で、所有者と読み取り専用の扱いは `/etc/relay-gate/` と同じ)。構築時の検査はファイルの存在確認だけで、指定先と配置先が一致することは導入する側が確かめる
- 管理 DB は 1 つ。すべての接続先の参照名が、同じ 1 つの管理 DB に解決されることを前提にする(2026-11-05 利用者決定)
  - 対象の参照名: `rapid-crosscheck.env` の `RAPID_DB_CONN_REF`、実行ホストと DB ホストそれぞれの `final-crosscheck.env` の `FINAL_DB_CONN_REF`、`hang-detector.env` の `HANG_DB_CONN_REF`、ハウスキープ設定 `housekeep.env` の `HOUSEKEEP_DB_CONN_REF`
  - ハウスキープは専用 DB ロール(`housekeep_del`)で、同じ管理 DB に接続する
  - 条件は参照名の文字列が同じことではなく、解決先(接続先の DB)が同じこと
  - 理由: 確報 runner が登録した依頼を、確報 worker が同じキューから取得するため。別の DB に解決されると、設定の検査を通っても確報ジョブが完了しない。速報・ハング検知・ハウスキープも同じ管理 DB の表を読み書きする
  - 構築時の検査は設定ファイルの存在確認だけで、解決先が同じことは判定しない。解決先が同じことは導入する側が確かめる
- 速報・確報の設定ファイルを置くかは inventory の変数で決める(例は `ansible/inventory.ini.example`)
  - `rapid_crosscheck_mode`(既定 off): off 以外なら `rapid-crosscheck.env` を置き、存在を確認する
  - `relay_gate_final_crosscheck_enabled`(既定 false。全ホストで同じ値): true なら実行ホストと DB ホストの両方に `final-crosscheck.env` を置き、存在を確認する。false なら両方から消す(残ったファイルでハウスキープが確報を使う設置と誤判定しないため)
- `final-crosscheck.env` は置き場ごとに中身が違う。適用側は次の 2 ファイルを `roles/relay-gate-config/files/` に用意する(配置先はどちらも `/etc/relay-gate/final-crosscheck.env`。各読み手は自分のホストのファイルだけを読む)
  - `final-crosscheck-runner.env`(実行ホスト用。確報 runner が読む): 必須 `FINAL_DB_CONN_REF`、任意 `FINAL_POLL_INTERVAL_SEC` / `FINAL_POLL_LIMIT_SEC`。`FINAL_COMPARE_COMMAND` は書かない
  - `final-crosscheck-worker.env`(DB ホスト用。確報 worker が読む): 必須 `FINAL_DB_CONN_REF` / `FINAL_COMPARE_COMMAND`、任意 `FINAL_LEASE_MINUTES` / `FINAL_WORKER_POLL_INTERVAL_SEC`。確報の比較ツール起動コマンドを持つのはこのファイルだけ
  - 起動コマンドの検証(`validate-config.sh --final-crosscheck`)は DB ホストで、そのホストの `final-crosscheck.env` に対して実行する
- 設定ファイル中の認証情報らしい値(password / secret / token の直後に `=` がある行)は、該当ファイルと行番号を警告するだけで構築を止めない
- apply や commit はユーザーが実行する(このスキルはファイル生成のみ行う)
