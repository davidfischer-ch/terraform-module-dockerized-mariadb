locals {
  container_data_directory = "/var/lib/mysql"

  host_data_directory = "${var.data_directory}/data"

  root_password = coalesce(var.root_password, random_password.root_password.result)
}
