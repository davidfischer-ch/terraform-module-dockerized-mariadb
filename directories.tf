resource "terraform_data" "data_directories" {
  triggers_replace = [
    local.host_data_directory,
    var.app_uid,
    var.app_gid
  ]

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${local.host_data_directory_quoted}
      chown -R ${var.app_uid}:${var.app_gid} ${local.host_data_directory_quoted}
    EOT
  }
}
