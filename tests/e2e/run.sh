#!/usr/bin/env sh

# Apply the module against the local Docker daemon, check the server it runs, run every action on
# real data, then destroy everything. Runs as root: the module creates and chowns its directories.
# The Docker daemon must see the data directory at the same path: set E2E_DATA_DIRECTORY to a
# directory both share when Terraform runs in a container of its own.
#
#   E2E_IMAGE=mariadb:11.8.5 sh tests/e2e/run.sh

set -eu

# The data directory: a fresh temporary one, or the one E2E_DATA_DIRECTORY names, absent or empty.
# The cleanup removes only what this run created.
if [ -n "${E2E_DATA_DIRECTORY:-}" ]; then
  DATA_DIRECTORY="${E2E_DATA_DIRECTORY}"
  case "${DATA_DIRECTORY}" in
    /*) ;;
    *)
      echo "FAILED: E2E_DATA_DIRECTORY must be an absolute path" >&2
      exit 1
      ;;
  esac
  if [ -e "${DATA_DIRECTORY}" ] || [ -L "${DATA_DIRECTORY}" ]; then
    if [ -L "${DATA_DIRECTORY}" ] || [ ! -d "${DATA_DIRECTORY}" ] \
      || [ -n "$(ls -A "${DATA_DIRECTORY}")" ]; then
      echo "FAILED: E2E_DATA_DIRECTORY ${DATA_DIRECTORY} is not an empty directory" >&2
      exit 1
    fi
    DATA_DIRECTORY_CREATED=false
  else
    mkdir "${DATA_DIRECTORY}"
    DATA_DIRECTORY_CREATED=true
  fi
else
  DATA_DIRECTORY=$(mktemp -d)
  DATA_DIRECTORY_CREATED=true
fi

cd "$(dirname "$0")"

CONTAINER=mariadb-e2e
APP_UID="${E2E_APP_UID:-999}"

tf() {
  terraform "$@" -input=false -no-color \
    -var "image=${E2E_IMAGE}" -var "app_uid=${APP_UID}" -var "data_directory=${DATA_DIRECTORY}"
}

expect() {
  if [ "$2" != "$3" ]; then
    echo "FAILED: ${1}: expected ${3}, got ${2}" >&2
    exit 1
  fi
  echo "ok: ${1}"
}

# Run a statement as root, or as the account of the third argument, over TCP to the container's own
# hostname: the local socket skips the password.
sql() {
  docker exec -e "MYSQL_PWD=${2:-an-e2e-password}" "${CONTAINER}" \
    mariadb -h "${CONTAINER}" -u "${3:-root}" -N -B -e "$1"
}

login() {
  sql 'SELECT 1' "$1" "${2:-root}" 2> /dev/null || true
}

invoke() {
  echo "==> action ${1}"
  if ! output=$(tf apply -auto-approve "-invoke=module.mariadb.action.docker_exec.${1}" 2>&1); then
    echo "${output}" >&2
    echo "FAILED: action ${1}" >&2
    exit 1
  fi
}

# Print whether an action expected to fail succeeds or fails.
outcome() {
  if tf apply -auto-approve "-invoke=module.mariadb.action.docker_exec.${1}" > /dev/null 2>&1; then
    echo success
  else
    echo failure
  fi
}

dumps() {
  docker exec "${CONTAINER}" sh -c 'cd /backup && ls dump-*.sql 2> /dev/null' || true
}

# The bind mounts live on the daemon's filesystem, which is not this one under Docker-in-Docker:
# remove them through the daemon too.
cleanup() {
  tf destroy -auto-approve > /dev/null || true
  docker run --rm --entrypoint rm -v "${DATA_DIRECTORY}:/e2e" "${E2E_IMAGE}" \
    -rf /e2e/backup /e2e/data || true
  [ "${DATA_DIRECTORY_CREATED}" = false ] || rm -rf "${DATA_DIRECTORY}"
}
trap cleanup EXIT

waited=0
until docker info > /dev/null 2>&1; do
  waited=$((waited + 1))
  if [ "${waited}" -ge 300 ]; then
    echo "FAILED: no Docker daemon reachable within 300 seconds" >&2
    exit 1
  fi
  sleep 1
done

terraform init -input=false -no-color > /dev/null
# The module waits for a healthy container: the apply fails when the healthcheck does not pass.
tf apply -auto-approve > /dev/null

expect 'the healthcheck reports the server healthy' \
  "$(docker inspect -f '{{.State.Health.Status}}' "${CONTAINER}")" healthy
expect 'the root password given to the module opens a session' "$(login an-e2e-password)" 1
expect 'another password is refused' "$(login not-the-password)" ''
expect 'the data directory belongs to app_uid' \
  "$(docker exec "${CONTAINER}" stat -c %u /var/lib/mysql)" "${APP_UID}"

sql 'CREATE DATABASE e2e; CREATE TABLE e2e.note (id int PRIMARY KEY)'
sql 'INSERT INTO e2e.note VALUES (1), (2), (3)'
tf apply -auto-approve -replace=module.mariadb.docker_container.server > /dev/null
expect 'the data outlives the container' "$(sql 'SELECT count(*) FROM e2e.note')" 3

sql "CREATE USER 'e2e'@'%' IDENTIFIED BY 'an-account-password'"
sql "GRANT SELECT ON e2e.* TO 'e2e'@'%'"
sql "CREATE USER 'rotated'@'%' IDENTIFIED BY 'a-first-password'"
sql "CREATE DATABASE \`--no-data\`"
invoke backup
expect 'backup writes one dump' "$(dumps | wc -l)" 1
expect 'the dump belongs to app_uid' \
  "$(docker exec "${CONTAINER}" sh -c 'stat -c %u /backup/dump-*.sql')" "${APP_UID}"
expect 'the backup directory and the dump are closed to other users' \
  "$(docker exec "${CONTAINER}" sh -c 'stat -c %a /backup /backup/dump-*.sql' | paste -s -d ' ')" \
  '700 600'
expect 'backup dumps the rows whatever the database names' \
  "$(docker exec "${CONTAINER}" sh -c 'grep -c "INTO .note. VALUES" /backup/dump-*.sql')" 1

sql 'INSERT INTO e2e.note VALUES (4)'
sql "DROP USER 'e2e'@'%'"
sql "ALTER USER 'rotated'@'%' IDENTIFIED BY 'a-rotated-password'"
sql "CREATE USER 'filer'@'%' IDENTIFIED BY 'a-filer-password'; GRANT FILE ON *.* TO 'filer'@'%'"
sql "SELECT 'CREATE DATABASE planted;' INTO DUMPFILE '/backup/dump-99991231T235959Z.sql'" \
  a-filer-password filer 2> /dev/null || true
invoke restore
expect 'restore loads no dump a FILE account wrote' \
  "$(sql "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'planted'")" 0
expect 'restore brings the rows of the dump back' "$(sql 'SELECT count(*) FROM e2e.note')" 3
expect 'restore brings the accounts of the dump back' \
  "$(sql "SELECT count(*) FROM mysql.user WHERE user = 'e2e'")" 1
expect 'restore brings their grants back' \
  "$(sql "SHOW GRANTS FOR 'e2e'@'%'" | grep -c 'GRANT SELECT ON .e2e.')" 1
expect 'restore keeps the password of an existing account' \
  "$(login a-rotated-password rotated)" 1
expect "the dump leaves the image's own accounts out" \
  "$(docker exec "${CONTAINER}" sh -c \
    "grep -c -E '\`(root|healthcheck|mariadb[.]sys)\`@' /backup/dump-*.sql")" 0

for action in check analyze upgrade; do
  invoke "${action}"
done

sql 'CREATE TABLE e2e.broken (id int PRIMARY KEY, label varchar(20), KEY (label)) ENGINE=MyISAM'
sql 'INSERT INTO e2e.broken SELECT seq, seq FROM e2e.seq_1_to_1000; FLUSH TABLES'
docker exec "${CONTAINER}" truncate -s 1024 /var/lib/mysql/e2e/broken.MYI
sql 'FLUSH TABLES'
expect 'check fails on a corrupt table' "$(outcome check)" failure
sql 'DROP TABLE e2e.broken'

sql 'CREATE TABLE e2e.positive (id int PRIMARY KEY, CHECK (id > 0))'
sql 'SET check_constraint_checks = 0; INSERT INTO e2e.positive VALUES (-1)'
invoke backup
expect 'restore fails on a row the server rejects' "$(outcome restore)" failure
sql 'DROP TABLE e2e.positive'

invoke backup
expect 'backup keeps the newest dump alone' "$(dumps | wc -l)" 1

status=0
tf plan -detailed-exitcode > /dev/null || status=$?
expect 'the plan is clean after the apply and the actions' "${status}" 0
