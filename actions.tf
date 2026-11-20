# On-demand operations on the server, run with `terraform apply -invoke=<action address>`.
# Each authenticates as root with the password file the container mounts.

# Backup -------------------------------------------------------------------------------------------

# Dump every database, then the accounts but the image's own (root, healthcheck, mariadb.sys) with
# their grants, into {data_directory}/backup/dump-<UTC time>.sql, readable by app_uid alone, written
# under a .tmp name and renamed once complete. The older dumps are removed only then, and the
# unfinished ones of other runs after them: the newest complete dump is always kept.
action "docker_exec" "backup" {
  config {
    container = docker_container.server.name
    user      = "${var.app_uid}:${var.app_gid}"
    command = ["sh", "-c", <<-EOT
      set -eu
      umask 077
      export MYSQL_PWD="$(cat "$MARIADB_ROOT_PASSWORD_FILE")"
      cd '${local.container_backup_directory}'
      dump="dump-$(date -u +%Y%m%dT%H%M%SZ).sql"
      databases=$(mariadb -u root -N -B -r -e "SELECT schema_name FROM information_schema.schemata
        WHERE schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')")
      # One argument per database name, after --: a name is never read as an option or split.
      set -f
      IFS='
      '
      # shellcheck disable=SC2086
      set -- $databases
      unset IFS
      set +f
      # The rows inserted without IGNORE: a row the server rejects fails the restore.
      if [ $# -gt 0 ]; then
        mariadb-dump -u root --single-transaction --routines --events --triggers \
          --add-drop-database --databases -- "$@" > "$dump.tmp"
      fi
      # The accounts after the databases, whose tables their grants may name, the roles granted to
      # the image's accounts kept. The grants carry no password: only CREATE USER IF NOT EXISTS
      # sets one, on an account it creates.
      accounts=$(mariadb-dump -u root --system=users --insert-ignore)
      printf '%s\n' "$accounts" | sed -E \
        -e "/[\`'](root|healthcheck|mariadb[.]sys)[\`']@/{/GRANT [\`'][^\`']+[\`'] TO /!d;}" \
        -e "/^GRANT /s/ IDENTIFIED( (BY|VIA|PASSWORD|USING|OR|'[^']*'|[a-z][a-z0-9_]*))+//" \
        >> "$dump.tmp"
      mv "$dump.tmp" "$dump"
      for older in dump-*; do
        case "$older" in
          "$dump") break ;;
          *.tmp) ;;
          *) rm -f "$older" ;;
        esac
      done
      rm -f dump-*.tmp
    EOT
    ]
  }
}

# Load the newest complete dump of {data_directory}/backup: its databases dropped and created
# again, its missing accounts created, and its grants given, the existing accounts keeping their
# passwords.
action "docker_exec" "restore" {
  config {
    container = docker_container.server.name
    user      = "${var.app_uid}:${var.app_gid}"
    command = ["sh", "-c", <<-EOT
      set -eu
      export MYSQL_PWD="$(cat "$MARIADB_ROOT_PASSWORD_FILE")"
      cd '${local.container_backup_directory}'
      dump=
      for complete in dump-*.sql; do
        [ ! -f "$complete" ] || dump=$complete
      done
      if [ -z "$dump" ]; then
        echo 'No complete dump-*.sql in ${local.container_backup_directory} to restore.' >&2
        exit 1
      fi
      mariadb -u root < "$dump"
    EOT
    ]
  }
}

# Maintenance --------------------------------------------------------------------------------------

# Check every table of every database for corruption, failing when the report holds an error:
# mariadb-check exits 0 on a corrupt table.
action "docker_exec" "check" {
  config {
    container = docker_container.server.name
    user      = "${var.app_uid}:${var.app_gid}"
    command = ["sh", "-c", <<-EOT
      set -eu
      export MYSQL_PWD="$(cat "$MARIADB_ROOT_PASSWORD_FILE")"
      report=$(mariadb-check -u root --all-databases --check)
      printf '%s\n' "$report"
      case "$report" in
        *'error    :'* | *'Error    :'* | *'Operation failed'*) exit 1 ;;
      esac
    EOT
    ]
  }
}

# Refresh the key distribution statistics of every table, which the optimizer reads.
action "docker_exec" "analyze" {
  config {
    container = docker_container.server.name
    user      = "${var.app_uid}:${var.app_gid}"
    command = [
      "sh", "-c", "${local.as_root} mariadb-check -u root --all-databases --analyze"
    ]
  }
}

# Bring the system tables to the server's version, which MARIADB_AUTO_UPGRADE also does at start.
action "docker_exec" "upgrade" {
  config {
    container = docker_container.server.name
    user      = "${var.app_uid}:${var.app_gid}"
    command = [
      "sh", "-c", "${local.as_root} mariadb-upgrade -u root"
    ]
  }
}
