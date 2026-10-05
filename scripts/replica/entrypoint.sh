#!/usr/bin/env bash
set -e

PGDATA="/var/lib/postgresql/data"
PRIMARY_HOST="${PRIMARY_IP}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
SLOT_NAME="${REPLICATION_SLOT}"
REPLICATOR_USER="${REPLICATOR_USER:-replicator}"
REPLICATOR_PASSWORD="${REPLICATOR_PASSWORD}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# If data dir already initialized, just start
if [ -s "$PGDATA/PG_VERSION" ]; then
  echo ">>> Data directory already initialized. Starting postgres..."
  exec gosu postgres postgres
fi

echo ">>> Preparing data directory..."
chown postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"

echo ">>> Waiting for primary at ${PRIMARY_HOST}:${PRIMARY_PORT}..."
until PGPASSWORD="${REPLICATOR_PASSWORD}" pg_isready -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U "${REPLICATOR_USER}" >/dev/null 2>&1; do
  echo "   primary not ready, retrying in 3s..."
  sleep 3
done

echo ">>> Running pg_basebackup from primary (slot=${SLOT_NAME})..."
until PGPASSWORD="${REPLICATOR_PASSWORD}" gosu postgres pg_basebackup \
    --pgdata="${PGDATA}" \
    --write-recovery-conf \
    --slot="${SLOT_NAME}" \
    --host="${PRIMARY_HOST}" \
    --port="${PRIMARY_PORT}" \
    --username="${REPLICATOR_USER}" \
    --wal-method=stream \
    --progress \
    --verbose; do
  echo "   basebackup failed, retrying in 5s..."
  sleep 5
  rm -rf "${PGDATA:?}/"* || true
done

echo ">>> Copying replica postgresql.conf..."
cp /etc/postgresql/postgresql.conf "${PGDATA}/postgresql.conf"

echo ">>> Cleaning up primary_conninfo password (rely on .pgpass)..."
# pg_basebackup already wrote postgresql.auto.conf with primary_conninfo.
# Append password if needed:
if ! grep -q "password=" "${PGDATA}/postgresql.auto.conf"; then
  sed -i "s|primary_conninfo = '\(.*\)'|primary_conninfo = '\1 password=${REPLICATOR_PASSWORD}'|" \
      "${PGDATA}/postgresql.auto.conf" || true
fi

chmod 0700 "${PGDATA}"
chown -R postgres:postgres "${PGDATA}"

echo ">>> Starting replica in standby mode..."
exec gosu postgres postgres