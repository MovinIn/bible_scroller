#!/bin/bash
set -euo pipefail
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'EOSQL'
GRANT ALL PRIVILEGES ON DATABASE bscroller TO db_user;
\c bscroller
GRANT ALL ON SCHEMA public TO db_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO db_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO db_user;
EOSQL

# Build URL from existing cevents pattern (same db_user credentials)
CEVENTS_LINE=$(grep '^CEVENTS_SQL_URL=' ~/.env | head -1)
BSCROLLER_URL=$(echo "$CEVENTS_LINE" | sed "s/CEVENTS_SQL_URL=//" | sed "s/cevents/bscroller/" | tr -d "'")
if grep -q '^BSCROLLER_DATABASE_URL=' ~/.env; then
  sed -i "s|^BSCROLLER_DATABASE_URL=.*|BSCROLLER_DATABASE_URL=${BSCROLLER_URL}|" ~/.env
else
  echo "BSCROLLER_DATABASE_URL=${BSCROLLER_URL}" >> ~/.env
fi
echo "Updated BSCROLLER_DATABASE_URL to use db_user"
