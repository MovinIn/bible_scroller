#!/bin/bash
# Deploy freshly-uploaded ~/bscroller-server.tar: rebuild image and restart container.
set -euo pipefail

rm -rf ~/bscroller-build
mkdir -p ~/bscroller-build
tar -xf ~/bscroller-server.tar -C ~/bscroller-build

echo "--- bundle marker in extracted index.html ---"
grep -o 'flutter_bootstrap.js[^"]*' ~/bscroller-build/static/web/index.html

cd ~/bscroller-build
docker build -t movinin/apps:bscroller_backend . 2>&1 | tail -3

cd ~
docker compose up -d bscroller
sleep 5
docker ps --filter name=bscroller --format '{{.Names}} {{.Status}}'
