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
ROOT_PASSWORD=an-e2e-password

tf() {
  terraform "$@" -input=false -no-color \
    -var "image=${E2E_IMAGE}" -var "app_uid=${APP_UID}" -var "data_directory=${DATA_DIRECTORY}" \
    -var "root_password=${ROOT_PASSWORD}"
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
  docker exec -e "MYSQL_PWD=${2:-${ROOT_PASSWORD}}" "${CONTAINER}" \
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

container_id() {
  docker inspect -f '{{.Id}}' "${CONTAINER}"
}

# Print the mode and owner of the secrets directory and of the password file, as Terraform's host
# sees them.
secrets_access() {
  stat -c '%a %u:%g' "${DATA_DIRECTORY}/secrets" "${DATA_DIRECTORY}/secrets/root-password" \
    | paste -s -d ' '
}

# Print the MD5, SHA-1, SHA-256 and SHA-512 digests of the root password, in hex and in base64, one
# per line.
digests() {
  for algorithm in md5 sha1 sha256 sha512; do
    printf %s "${ROOT_PASSWORD}" | openssl dgst "-${algorithm}" -r | cut -d ' ' -f 1
    printf %s "${ROOT_PASSWORD}" | openssl dgst "-${algorithm}" -binary | base64 -w 0
    echo
  done
}

# Print the address and the path of each attribute holding the root password without a sensitive
# mark, one per line, in the state the first argument gives as `terraform show -json` prints it.
unmarked() {
  printf '%s\n' "$1" | jq -r --arg secret "${ROOT_PASSWORD}" '
    .. | objects | select(has("sensitive_values")) | . as $resource
    | .values | paths(type == "string" and contains($secret)) as $path
    | select([range(1; ($path | length) + 1) as $length
        | $resource.sensitive_values | getpath($path[:$length])?] | any(. == true) | not)
    | "\($resource.address) \($path | map(tostring) | join("."))"'
}

# Check that the output of the apply, the first argument, and the state hold the root password only
# under a sensitive mark, and none of its digests.
expect_no_exposure() {
  digests=$(mktemp)
  digests > "${digests}"
  forms=$(mktemp)
  { echo "${ROOT_PASSWORD}"; cat "${digests}"; } > "${forms}"
  show=$(terraform show -no-color)
  json=$(terraform show -json -no-color)
  expect 'the apply prints neither the root password nor its digests' \
    "$(printf '%s\n' "$1" | grep -c -F -f "${forms}" || true)" 0
  expect 'terraform show prints neither the root password nor its digests' \
    "$(printf '%s\n' "${show}" | grep -c -F -f "${forms}" || true)" 0
  expect 'the state holds no digest of the root password' \
    "$(printf '%s\n' "${json}" | grep -c -F -f "${digests}" || true)" 0
  expect 'the state holds the root password under a sensitive mark alone' "$(unmarked "${json}")" ''
  rm -f "${digests}" "${forms}"
}

# Change the mode or the owner of the secrets with the command of the remaining arguments, and check
# that a plan sees it and an apply restores it, the container kept.
drift() {
  description=$1
  shift
  "$@"
  status=0
  plan=$(tf plan -detailed-exitcode) || status=$?
  expect "a plan sees ${description}" "${status}" 2
  expect "the plan restores ${description}" \
    "$(printf '%s\n' "${plan}" | grep -c 'root_password_access must be replaced')" 1
  expect "the plan keeps the container and the password file" \
    "$(printf '%s\n' "${plan}" \
      | grep -c -e 'docker_container[.]server \(will\|must\) be' \
        -e 'terraform_data[.]root_password \(will\|must\) be' || true)" 0
  container=$(container_id)
  tf apply -auto-approve > /dev/null
  expect "the apply restores ${description}" "$(secrets_access)" \
    "700 ${APP_UID}:${APP_UID} 600 ${APP_UID}:${APP_UID}"
  expect 'the apply keeps the container' "$(container_id)" "${container}"
  status=0
  tf plan -detailed-exitcode > /dev/null || status=$?
  expect 'the plan is clean after the restore' "${status}" 0
}

# The bind mounts live on the daemon's filesystem, which is not this one under Docker-in-Docker:
# remove them through the daemon too.
cleanup() {
  tf destroy -auto-approve > /dev/null || true
  docker run --rm --entrypoint rm -v "${DATA_DIRECTORY}:/e2e" "${E2E_IMAGE}" \
    -rf /e2e/backup /e2e/data /e2e/secrets || true
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
output=$(tf apply -auto-approve)

expect 'the healthcheck reports the server healthy' \
  "$(docker inspect -f '{{.State.Health.Status}}' "${CONTAINER}")" healthy
expect 'the root password given to the module opens a session' "$(login "${ROOT_PASSWORD}")" 1
expect 'another password is refused' "$(login not-the-password)" ''
expect 'the data directory belongs to app_uid' \
  "$(docker exec "${CONTAINER}" stat -c %u /var/lib/mysql)" "${APP_UID}"
expect 'the root password is not in the container'"'"'s configuration' \
  "$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${CONTAINER}" \
    | grep -c -e "${ROOT_PASSWORD}" -e '^MARIADB_ROOT_PASSWORD=')" 0
expect 'the root password file is readable by app_uid alone' \
  "$(docker exec "${CONTAINER}" stat -c '%u %a' /run/secrets/root-password)" "${APP_UID} 600"
expect 'the secrets directory and the password file belong to app_uid, closed to other users' \
  "$(secrets_access)" "700 ${APP_UID}:${APP_UID} 600 ${APP_UID}:${APP_UID}"
expect_no_exposure "${output}"
status=0
tf plan -detailed-exitcode > /dev/null || status=$?
expect 'the plan is clean after the first apply' "${status}" 0

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

drift 'the secrets directory opened to other users' chmod 755 "${DATA_DIRECTORY}/secrets"
drift 'the password file opened to other users' chmod 644 "${DATA_DIRECTORY}/secrets/root-password"
drift 'the password file given to another owner' \
  chown "$((APP_UID + 1)):$((APP_UID + 1))" "${DATA_DIRECTORY}/secrets/root-password"
invoke check

# The actions drop the line feed an editor appends to the password file.
printf '%s\n' "${ROOT_PASSWORD}" > "${DATA_DIRECTORY}/secrets/root-password"
invoke check

# A root password changed on the server, then given to the module, is written to a new file, which a
# new container binds and the actions read.
sql "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('a-new-root-password');
  SET PASSWORD FOR 'root'@'%' = PASSWORD('a-new-root-password')"
ROOT_PASSWORD=a-new-root-password
container=$(container_id)
output=$(tf apply -auto-approve)
expect 'a new root password replaces the container' \
  "$([ "$(container_id)" = "${container}" ] && echo kept || echo replaced)" replaced
expect 'the new container binds the new password file' \
  "$(docker exec "${CONTAINER}" cat /run/secrets/root-password)" "${ROOT_PASSWORD}"
expect 'the secrets directory and the new password file belong to app_uid, closed to other users' \
  "$(secrets_access)" "700 ${APP_UID}:${APP_UID} 600 ${APP_UID}:${APP_UID}"
expect_no_exposure "${output}"
for action in backup restore check analyze upgrade; do
  invoke "${action}"
done

status=0
tf plan -detailed-exitcode > /dev/null || status=$?
expect 'the plan is clean after the apply and the actions' "${status}" 0

tf destroy -auto-approve > /dev/null
expect 'destroy removes the password file and the secrets directory' \
  "$(find "${DATA_DIRECTORY}" -maxdepth 1 -name secrets)" ''
