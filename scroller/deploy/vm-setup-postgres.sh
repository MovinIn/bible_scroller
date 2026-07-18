#!/bin/bash
set -euo pipefail
chmod 644 ~/certs/bscroller_cert.pem
chmod 600 ~/certs/bscroller_key.pem
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='bscroller'" | grep -q 1; then
  echo "bscroller database already exists"
  exit 0
fi
PASS=$(openssl rand -hex 16)
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOSQL
CREATE USER bscroller WITH PASSWORD '${PASS}';
CREATE DATABASE bscroller OWNER bscroller;
EOSQL
grep -q BSCROLLER_DATABASE_URL ~/.env || echo "BSCROLLER_DATABASE_URL=postgresql://bscroller:${PASS}@172.18.0.1:5432/bscroller" >> ~/.env
grep -q '^BIBLE_BRAIN_API_KEY=' ~/.env || echo "BIBLE_BRAIN_API_KEY=" >> ~/.env
echo "Created bscroller database and appended env vars"
