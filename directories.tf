resource "terraform_data" "data_directories" {
  triggers_replace = [
    local.host_backup_directory,
    local.host_data_directory,
    var.app_uid,
    var.app_gid
  ]

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${local.host_directories_quoted}
      chown -R ${var.app_uid}:${var.app_gid} ${local.host_directories_quoted}
      chmod 700 ${local.host_backup_directory_quoted}
    EOT
  }
}
