#!/bin/bash

# Script to backup a PostgreSQL database running in a Docker container (spawned
# via Docker Compose) using "postgres" image (https://hub.docker.com/_/postgres/).
#
# Usage: backup_dockerized_postgresql_database.sh dockercompose_filepath database_service_name_in_dockercompose_file backup_destination_dirpath
#
# How it works:
# * Give it:
#   * The Docker Compose dirpath (id. where to use `docker-compose` command from).
#   * The name of the Docker Compose service that corresponds to the PostgreSQL server.
#   * Where to create backups.
#   * the port under which Where to create backups.
# * And it will:
#   * Find the container ID (via `docker-compose ps`).
#   * Find user, password and database name from POSTGRES_* environment variables from `docker inspect`.
#   * Create, fill and copy to the container a .pgpass file.
#   * Run `pg_dump`.
#   * Print the path of created backup file.
#   * Clean.
#
# Notes:
# * Paths to `docker` and `docker-compose` can be adjusted via DOCKER_CLI_FILEPATH
#   and DOCKERCOMPOSE_CLI_FILEPATH environment variables.

set -euo pipefail

readonly PROGNAME="$(basename -- "$0")"

readonly DOCKER_CLI_FILEPATH="$(which docker)"
readonly DOCKERCOMPOSE_CLI_FILEPATH="/usr/local/bin/docker-compose"

# PostgreSQL port
readonly DATABASE_PORT=5432

# Arguments handling

if [ "$#" -lt 3 ] ; then
    (>&2 echo "Error: Missing arguments.")
    (>&2 echo "Usage: ${PROGNAME} dockercompose_filepath database_service_name_in_dockercompose_file backup_destination_dirpath")
    exit 2
fi

DOCKERCOMPOSE_DIRPATH="${1}"
DOCKERCOMPOSE_DATABASE_SERVICENAME="${2}"
BACKUP_DESTINATION_DIRPATH="${3}"

if [ ! -d "${DOCKERCOMPOSE_DIRPATH}" ] ; then
    (>&2 echo "Error: Invalid argument: dockercompose_filepath (\"${DOCKERCOMPOSE_DIRPATH}\") is not a directory.")
    exit 2
fi

if [ -z "${DOCKERCOMPOSE_DATABASE_SERVICENAME}" ] ; then
    (>&2 echo "Error: Invalid argument: database_service_name_in_dockercompose_file is empty")
    exit 2
fi

if [ ! -d "${BACKUP_DESTINATION_DIRPATH}" ] ; then
    (>&2 echo "Error: Invalid argument: backup_destination_dirpath (\"${BACKUP_DESTINATION_DIRPATH}\") is not a directory.")
    exit 2
fi

# /Arguments handling

# Move into Docker Compose directory before running docker-compose commands
cd "${DOCKERCOMPOSE_DIRPATH}"

# Get PostgreSQL's container ID
DOCKER_DATABASE_CONTAINERID="$(${DOCKERCOMPOSE_CLI_FILEPATH} ps -q "${DOCKERCOMPOSE_DATABASE_SERVICENAME}")"

# Get user, password and database name from environment variables passed to the
# container (looking for POSTGRES_USER, POSTGRES_PASSWORD and POSTGRES_DB respectively)
DB_USER="$(${DOCKER_CLI_FILEPATH} inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${DOCKER_DATABASE_CONTAINERID}" | grep '^POSTGRES_USER=' | cut -d '=' -f 2-)"
DB_PASSWORD="$(${DOCKER_CLI_FILEPATH} inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${DOCKER_DATABASE_CONTAINERID}" | grep '^POSTGRES_PASSWORD=' | cut -d '=' -f 2-)"
DB_NAME="$(${DOCKER_CLI_FILEPATH} inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${DOCKER_DATABASE_CONTAINERID}" | grep '^POSTGRES_DB=' | cut -d '=' -f 2-)"

# Create a .pgpass file locally to store the PostgreSQL credentials (which is
# then copied into the container)
LOCAL_POSTGRESQL_PGPASSFILE_FILEPATH="$(mktemp)"
echo "${DOCKERCOMPOSE_DATABASE_SERVICENAME}:${DATABASE_PORT}:${DB_NAME}:${DB_USER}:${DB_PASSWORD}" > "${LOCAL_POSTGRESQL_PGPASSFILE_FILEPATH}"
CONTAINER_POSTGRESQL_PGPASSFILE_FILEPATH="/tmp/.pgpass"
${DOCKER_CLI_FILEPATH} cp "${LOCAL_POSTGRESQL_PGPASSFILE_FILEPATH}" "${DOCKER_DATABASE_CONTAINERID}:${CONTAINER_POSTGRESQL_PGPASSFILE_FILEPATH}"

BACKUP_DATE="$(date --utc +'%F_%H-%M-%S_%Z')"
BACKUP_DESTINATION_FILEPATH="${BACKUP_DESTINATION_DIRPATH}/${DB_NAME}.${BACKUP_DATE}.sql"

# Executes `pg_dump` on database $DB_NAME as $DB_USER using the .pgpass file
# designated by "PGPASSFILE" environment variable (=)
${DOCKERCOMPOSE_CLI_FILEPATH} exec \
    -T \
    --env "PGPASSFILE=${CONTAINER_POSTGRESQL_PGPASSFILE_FILEPATH}" \
    "${DOCKERCOMPOSE_DATABASE_SERVICENAME}" \
    pg_dump \
    --clean \
    --create \
    --username="${DB_USER}" \
    "${DB_NAME}" \
    > "${BACKUP_DESTINATION_FILEPATH}"

# Prints the created dump
if [ $? -eq 0 ] ; then
    echo "${BACKUP_DESTINATION_FILEPATH}"
fi

# Move back to previous directory (now that all docker-compose commands were executed)
cd - > /dev/null

# Delete now-useless local .pgpass file
rm "${LOCAL_POSTGRESQL_PGPASSFILE_FILEPATH}"
