# relay-gate オンプレミス IaC スケルトン

`docs/mcl/product/output/product-impl-onprem.yaml` に対応する IaC スケルトン(未検証の雛形)。
仮想化基盤(vSphere / OpenStack / 物理サーバ)は適用側の設置環境に固定しないため、
Terraform はホスト・ネットワークセグメントの**論理定義のみ**を variables として持つプレースホルダとし、
実際のプロビジョニングは Ansible ロールで OS・ミドルウェア構成を行う 2 層構成とする。

## 構成

```
infra/product/onprem/
  terraform/     # ホスト・ネットワークセグメントの論理定義(プレースホルダ variables)
  ansible/       # OS・ミドルウェア構成(systemd / PostgreSQL / 設定配置 / Postfix / バックアップ)
```

## 適用順序

1. `terraform/` で対象環境(vSphere/OpenStack/物理)向けの provider ブロックを具体化し、
   実行ホストセグメント・DBセグメントのホストを用意する(このスケルトンでは未確定)
2. `ansible/` の各ロールを対象ホストグループに適用する

## 前提

- エアーギャップ環境のためインターネット経由のパッケージ取得は行わない(オフラインリポジトリ/ローカルミラーを利用)
- apply や commit はユーザーが実行する(このスキルはファイル生成のみ行う)
