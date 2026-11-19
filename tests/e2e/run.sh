#!/usr/bin/env sh

# Apply the module against the local Docker daemon, check the server it runs, then destroy
# everything. Runs as root: the module creates and chowns its directories. Against a
# Docker-in-Docker daemon, whose filesystem the bind mounts live on, set E2E_APP_UID=0.
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

# Run a statement as root, over TCP to the container's own hostname: the local socket skips the
# password.
sql() {
  docker exec -e "MYSQL_PWD=${2:-an-e2e-password}" "${CONTAINER}" \
    mariadb -h "${CONTAINER}" -u root -N -B -e "$1"
}

login() {
  sql 'SELECT 1' "$1" 2> /dev/null || true
}

# The bind mounts live on the daemon's filesystem, which is not this one under Docker-in-Docker:
# remove them through the daemon too.
cleanup() {
  tf destroy -auto-approve > /dev/null || true
  docker run --rm --entrypoint rm -v "${DATA_DIRECTORY}:/e2e" "${E2E_IMAGE}" -rf /e2e/data || true
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

status=0
tf plan -detailed-exitcode > /dev/null || status=$?
expect 'the plan is clean after the apply' "${status}" 0
