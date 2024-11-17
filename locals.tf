locals {
  container_data_directory = "/var/lib/mysql"

  host_data_directory = "${var.data_directory}/data"
}
