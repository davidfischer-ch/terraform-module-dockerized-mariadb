locals {
  container_backup_directory = "/backup"
  container_data_directory   = "/var/lib/mysql"

  host_backup_directory = "${var.data_directory}/backup"
  host_data_directory   = "${var.data_directory}/data"

  # The paths as single-quoted shell words, whatever characters they hold.
  host_backup_directory_quoted = "'${replace(local.host_backup_directory, "'", "'\\''")}'"
  host_directories_quoted = join(" ", [
    for directory in [local.host_backup_directory, local.host_data_directory] :
    "'${replace(directory, "'", "'\\''")}'"
  ])

  # Prefix of an action's shell command, running a client as root.
  as_root = "MYSQL_PWD=\"$MARIADB_ROOT_PASSWORD\" exec"

  root_password = coalesce(var.root_password, random_password.root_password.result)

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
