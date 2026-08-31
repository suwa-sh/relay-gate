# relay-gate オンプレミス実行ホスト/DBセグメントの論理定義(プレースホルダ)
# provider(vsphere / openstack / 物理サーバのインベントリ管理ツール等)は適用側の設置環境に従い
# ここでは固定しない。variables のみを定義し、provider ブロックは適用側で追加する。

variable "execution_host_segment_cidr" {
  description = "ジョブスケジューラ実行ホストセグメントのCIDR(facade / slot runner / rapid-crosscheck-runner・worker / ops CLI)"
  type        = string
}

variable "db_host_segment_cidr" {
  description = "管理DBセグメントのCIDR(final-crosscheck-worker含む)"
  type        = string
}

variable "execution_host_count" {
  description = "実行ホストセグメントに配置するホスト数(初期構成)"
  type        = number
  default     = 1
}

variable "db_host_count" {
  description = "DBセグメントに配置するホスト数(単一インスタンス構成)"
  type        = number
  default     = 1
}

variable "allowed_ports" {
  description = "セグメント間で許可するポート(SSH / DB / SMTP のみ)"
  type        = list(number)
  default     = [22, 5432, 25]
}
