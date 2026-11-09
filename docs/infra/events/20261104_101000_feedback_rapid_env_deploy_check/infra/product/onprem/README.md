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
- 速報・確報の設定ファイルを置くかは inventory の変数で決める(例は `ansible/inventory.ini.example`)
  - `rapid_crosscheck_mode`(既定 off): off 以外なら `rapid-crosscheck.env` を置き、存在を確認する
  - `relay_gate_final_crosscheck_enabled`(既定 false。全ホストで同じ値): true なら実行ホストと DB ホストの両方に `final-crosscheck.env` を置き、存在を確認する。false なら両方から消す(残ったファイルでハウスキープが確報を使う設置と誤判定しないため)
- 設定ファイル中の認証情報らしい値(password / secret / token の直後に `=` がある行)は、該当ファイルと行番号を警告するだけで構築を止めない
- apply や commit はユーザーが実行する(このスキルはファイル生成のみ行う)
