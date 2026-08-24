#!/bin/bash

set -e

until pg_isready -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USER"; do
  echo "Waiting for Postgres server '$DATABASE_HOST' to become available..."
  sleep 1
done

psql -1 -v ON_ERROR_STOP=1 -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USER" -d "$DATABASE_NAME" -c "CREATE USER zitadel WITH PASSWORD 'zitadel'"
