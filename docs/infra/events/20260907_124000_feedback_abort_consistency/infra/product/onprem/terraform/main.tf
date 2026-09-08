# relay-gate オンプレミス構成 - プロビジョニング定義(プレースホルダ)
#
# NOTE: 対象の仮想化基盤(vSphere / OpenStack / 物理サーバ)未確定のため、
# provider ブロックと実リソース定義(vsphere_virtual_machine 等)はここでは記述しない。
# 適用側が対象基盤を確定した時点で、下記構造に沿ってリソースを追加する。
#
# 想定リソース構成:
#   - execution_host_segment: ジョブスケジューラ実行ホストセグメント(var.execution_host_count 台)
#   - db_host_segment: 管理DBセグメント(var.db_host_count 台、単一インスタンス構成)
#   - segment_firewall_rules: セグメント間はSSH/DB/SMTPポートのみ許可(var.allowed_ports)
#
# 例(vSphere provider を使う場合の骨子。値は適用側で埋める):
#
# resource "vsphere_virtual_machine" "execution_host" {
#   count = var.execution_host_count
#   name  = "relay-gate-exec-${count.index}"
#   # ... datastore_id / resource_pool_id / network_interface 等は適用側で設定
# }
#
# resource "vsphere_virtual_machine" "db_host" {
#   count = var.db_host_count
#   name  = "relay-gate-db-${count.index}"
#   # ... datastore_id / resource_pool_id / network_interface 等は適用側で設定
# }

output "execution_host_segment_cidr" {
  value = var.execution_host_segment_cidr
}

output "db_host_segment_cidr" {
  value = var.db_host_segment_cidr
}
