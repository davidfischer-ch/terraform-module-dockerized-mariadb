locals {
  container_backup_directory = "/backup"
  container_data_directory   = "/var/lib/mysql"
  container_root_password    = "/run/secrets/root-password"

  host_backup_directory   = "${var.data_directory}/backup"
  host_data_directory     = "${var.data_directory}/data"
  host_secrets_directory  = "${var.data_directory}/secrets"
  host_root_password_file = "${local.host_secrets_directory}/root-password"

  # The paths as single-quoted shell words, whatever characters they hold.
  host_backup_directory_quoted = "'${replace(local.host_backup_directory, "'", "'\\''")}'"
  host_directories_quoted = join(" ", [
    for directory in [local.host_backup_directory, local.host_data_directory] :
    "'${replace(directory, "'", "'\\''")}'"
  ])
  host_secrets_directory_quoted  = "'${replace(local.host_secrets_directory, "'", "'\\''")}'"
  host_root_password_file_quoted = "'${replace(local.host_root_password_file, "'", "'\\''")}'"

  # Prefix of an action's shell command, running a client as root.
  as_root = "MYSQL_PWD=\"$(cat \"$MARIADB_ROOT_PASSWORD_FILE\")\" exec"

  root_password = coalesce(var.root_password, random_password.root_password.result)

  owner = "${var.app_uid}:${var.app_gid}"

  # Mode and owner of the secrets directory and of the password file, as an apply leaves them.
  root_password_access = {
    directory = "700 ${local.owner}"
    file      = "600 ${local.owner}"
  }

  # The access the plan reads: an absent file is written again, a changed mode or owner restored.
  root_password_observed = data.external.root_password_access.result
  root_password_absent   = local.root_password_observed.file == "absent"
  root_password_drifted = !local.root_password_absent && (
    local.root_password_observed.directory != local.root_password_access.directory
    || local.root_password_observed.file != local.root_password_access.file
  )

  # Unknown until the apply, where it is "": a trigger holding it plans a replacement, and the state
  # keeps the "" a plan without drift holds.
  until_apply = substr(timestamp(), 0, 0)

  linux_capabilities = [
    "ALL",
    "AUDIT_CONTROL",
    "AUDIT_READ",
    "AUDIT_WRITE",
    "BLOCK_SUSPEND",
    "BPF",
    "CHECKPOINT_RESTORE",
    "CHOWN",
    "DAC_OVERRIDE",
    "DAC_READ_SEARCH",
    "FOWNER",
    "FSETID",
    "IPC_LOCK",
    "IPC_OWNER",
    "KILL",
    "LEASE",
    "LINUX_IMMUTABLE",
    "MAC_ADMIN",
    "MAC_OVERRIDE",
    "MKNOD",
    "NET_ADMIN",
    "NET_BIND_SERVICE",
    "NET_BROADCAST",
    "NET_RAW",
    "PERFMON",
    "SETFCAP",
    "SETGID",
    "SETPCAP",
    "SETUID",
    "SYS_ADMIN",
    "SYS_BOOT",
    "SYS_CHROOT",
    "SYS_MODULE",
    "SYS_NICE",
    "SYS_PACCT",
    "SYS_PTRACE",
    "SYS_RAWIO",
    "SYS_RESOURCE",
    "SYS_TIME",
    "SYS_TTY_CONFIG",
    "SYSLOG",
    "WAKE_ALARM"
  ]
}
