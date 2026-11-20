resource "random_password" "root_password" {
  length  = 32
  special = false
}

# Mode and owner (`<mode> <uid>:<gid>`) of the secrets directory and of the password file, or
# "absent", read on the Terraform host at each plan.
data "external" "root_password_access" {
  program = ["sh", "-c", <<-EOT
    set -eu
    access() {
      if [ -e "$1" ]; then stat -c '%a %u:%g' -- "$1"; else echo absent; fi
    }
    directory=$(access ${local.host_secrets_directory_quoted})
    file=$(access ${local.host_root_password_file_quoted})
    printf '{"directory": "%s", "file": "%s"}\n' "$directory" "$file"
  EOT
  ]
}

# The root password in {data_directory}/secrets/root-password, read through
# MARIADB_ROOT_PASSWORD_FILE by the image's entrypoint and by the actions. Written again at each
# change of the password, of the path or of the owner, and when the file is absent.
resource "terraform_data" "root_password" {
  triggers_replace = [
    sensitive(local.root_password),
    local.host_root_password_file,
    local.owner,
    local.root_password_absent ? local.until_apply : "",
  ]

  # The paths the destroy provisioner removes, which may reference self alone.
  input = {
    directory = local.host_secrets_directory
    file      = local.host_root_password_file
  }

  # The password reaches the shell through its environment alone, out of the command and the plan.
  # The file is complete, closed and owned by app_uid before it takes the final name.
  provisioner "local-exec" {
    environment = {
      OWNER              = local.owner
      ROOT_PASSWORD      = local.root_password
      ROOT_PASSWORD_FILE = local.host_root_password_file
      SECRETS_DIRECTORY  = local.host_secrets_directory
    }
    command = <<-EOT
      set -eu
      umask 077
      mkdir -p "$SECRETS_DIRECTORY"
      written=$(mktemp "$ROOT_PASSWORD_FILE.XXXXXX")
      trap 'rm -f "$written"' EXIT
      printf %s "$ROOT_PASSWORD" > "$written"
      chmod 600 "$written"
      chown "$OWNER" "$written"
      mv -f "$written" "$ROOT_PASSWORD_FILE"
      chmod 700 "$SECRETS_DIRECTORY"
      chown "$OWNER" "$SECRETS_DIRECTORY"
    EOT
  }

  # Remove the file, and the secrets directory once empty.
  provisioner "local-exec" {
    when = destroy
    environment = {
      ROOT_PASSWORD_FILE = self.input.file
      SECRETS_DIRECTORY  = self.input.directory
    }
    command = <<-EOT
      set -eu
      rm -f "$ROOT_PASSWORD_FILE"
      rmdir "$SECRETS_DIRECTORY" 2> /dev/null || true
    EOT
  }

  depends_on = [terraform_data.data_directories]
}

# Restore the mode and owner of the secrets directory and of the password file, changed while the
# password was not. The container keeps running on the same file.
resource "terraform_data" "root_password_access" {
  triggers_replace = [local.root_password_drifted ? local.until_apply : ""]

  provisioner "local-exec" {
    environment = {
      OWNER              = local.owner
      ROOT_PASSWORD_FILE = local.host_root_password_file
      SECRETS_DIRECTORY  = local.host_secrets_directory
    }
    command = <<-EOT
      set -eu
      chmod 700 "$SECRETS_DIRECTORY"
      chmod 600 "$ROOT_PASSWORD_FILE"
      chown "$OWNER" "$SECRETS_DIRECTORY" "$ROOT_PASSWORD_FILE"
    EOT
  }

  depends_on = [terraform_data.root_password]
}
