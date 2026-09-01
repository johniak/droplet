#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Values below are overridden by docker-compose.e2e.yml; they only satisfy the
# interpolation of required variables in docker-compose.yml.
export DJANGO_SECRET_KEY=e2e-secret
export DROPLET_ADMIN_USER=e2e
export DROPLET_ADMIN_PASSWORD=e2e-pass-123
export LIBRARY_PATH=./backend/e2e/fixture-library

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.e2e.yml"
cleanup() { $COMPOSE down -v; }
trap cleanup EXIT
$COMPOSE up -d --build
for i in $(seq 1 60); do
  curl -sf http://localhost:8800/api/health/ >/dev/null && break
  sleep 1
done
(cd backend && "${PYTEST:-.venv/bin/pytest}" e2e -v --no-cov)
